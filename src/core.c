/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright (C) 2026 Diky_I
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <sched.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <elf.h>
#include "core.h"
#include <stddef.h>
#include <sys/system_properties.h>

extern char **environ;

#define CORELIST_DYNAMIC      "core_preload.core"
#define CORELIST_STATIC       "core_preload_static.core"
#define CORELIST_LOCK         "core_preload_static.lock"

#define PROC_ROOT             "/proc"
#define STATUS_FMT            "/proc/%d/status"

#define MAX_PKGS              32
#define MAX_EVENTS            8192
#define MAX_PATH              512
#define MAX_LOCK_BYTES        (300ULL * 1024 * 1024)

#define MAX_MAPS 1024
#define MAX_SEGS 32
#define MAX_LINE 512
#define MAX_PKG  128

static inline int is_root(void) {
    return geteuid() == 0;
}

static const char *system_demote_names[] = {
    "log",
    "smartcharging",
    "batterywarning",
    NULL
};

static const char *root_demote_names[] = {
    "statsd",
    "incidentd",
    "mdnsd",
    "update_engine",
    "mnld",
    "agpsd",
    "fuelgauged",
    NULL
};

static int already_boosted(pid_t tid) {
    int pol = sched_getscheduler(tid);
    return (pol == SCHED_RR || pol == SCHED_FIFO);
}

static int cgroup_write_pid(const char *path, pid_t pid) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0)
        return -errno;

    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%d\n", pid);

    ssize_t n = write(fd, buf, len);
    close(fd);

    return (n == len) ? 0 : -EIO;
}

static int run_taskprofile(pid_t tid, const char *p1, const char *p2) {
    char tidbuf[16];
    snprintf(tidbuf, sizeof(tidbuf), "%d", tid);

    char *argv[] = {
        (char *)"settaskprofile",
        tidbuf,
        (char *)p1,
        (char *)p2,
        NULL
    };

    pid_t pid;
    int rc = posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc != 0)
        return -rc;

    int status;
    while (waitpid(pid, &status, 0) == -1) {
        if (errno != EINTR)
            return -errno;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return -EACCES;

    return 0;
}

static void ensure_root_rlimits(void) {
    static int done;
    if (done)
        return;

    struct rlimit rl;
    rl.rlim_cur = rl.rlim_max = MAX_LOCK_BYTES;
    setrlimit(RLIMIT_MEMLOCK, &rl);

    rl.rlim_cur = rl.rlim_max = RLIM_INFINITY;
    setrlimit(RLIMIT_RTPRIO, &rl);

    done = 1;
}

static int name_in_list(const char *name, const char *const *list) {
    for (int i = 0; list[i]; i++)
        if (!strcmp(name, list[i]))
            return 1;
    return 0;
}

static void apply_root_boost(pid_t tid) {
    struct sched_param sp = { .sched_priority = 1 };
    sched_setscheduler(tid, SCHED_RR, &sp);
    setpriority(PRIO_PROCESS, tid, -10);
}

static void normalize_root_sched(pid_t pid, const char *name) {
    if (name_in_list(name, root_demote_names))
        return;

    struct sched_param sp = { .sched_priority = 0 };
    sched_setscheduler(pid, SCHED_OTHER, &sp);
    setpriority(PRIO_PROCESS, pid, 0);
}

static int core_boost_internal(pid_t tid) {
    if (already_boosted(tid))
        return 0;

    int rc = run_taskprofile(tid, "SCHED_SP_RT_APP", "InputPolicy");
    if (rc < 0)
        return rc;

    if (is_root()) {
        ensure_root_rlimits();
        apply_root_boost(tid);
    }

    return 0;
}

static int core_demote_internal(pid_t id) {
    if (id <= 0)
        return -EINVAL;

    if (is_root()) {
        cgroup_write_pid("/dev/blkio/background/cgroup.procs", id);
        cgroup_write_pid("/dev/cpuctl/background/cgroup.procs", id);
        cgroup_write_pid("/dev/cpuset/restricted/cgroup.procs", id);

        struct sched_param sp = { .sched_priority = 0 };
        sched_setscheduler(id, SCHED_IDLE, &sp);
        setpriority(PRIO_PROCESS, id, 19);

        return 0;
    }

    int rc = run_taskprofile(id,
                             "CPUSET_SP_RESTRICTED",
                             "SCHED_SP_BACKGROUND");
    if (rc < 0)
        return rc;

    setpriority(PRIO_PROCESS, id, 19);
    return 0;
}

int core_boost_tid(pid_t tid) {
    if (tid <= 0)
        return -EINVAL;
    return core_boost_internal(tid);
}

int core_demote_tid(pid_t tid) {
    if (tid <= 0)
        return -EINVAL;
    return core_demote_internal(tid);
}

typedef struct {
    void  *addr;
    size_t size;
    int    locked;
} seg_t;

typedef struct {
    char   path[PATH_MAX];
    char   pkg[MAX_PKG];
    void  *base;
    size_t size;
    seg_t  segs[MAX_SEGS];
    int    seg_count;
    int    permanent;
} map_t;

static map_t maps[MAX_MAPS];
static int map_count;

static size_t total_locked;
static int last_lock_ok;
static int last_lock_fail;
static int last_lock_errno;
static long page_size;

static int preload_done;
static pthread_mutex_t preload_mutex = PTHREAD_MUTEX_INITIALIZER;

static void fault_in(void *addr, size_t size) {
    volatile unsigned char *p = addr;
    for (size_t i = 0; i < size; i += page_size)
        (void)p[i];
}

static void lock_seg(map_t *m, void *addr, size_t size) {
    if (m->seg_count >= MAX_SEGS) {
        last_lock_fail++;
        last_lock_errno = last_lock_errno ?: ENOSPC;
        return;
    }

    if (total_locked + size > MAX_LOCK_BYTES) {
        last_lock_fail++;
        last_lock_errno = last_lock_errno ?: ENOMEM;
        m->segs[m->seg_count++] = (seg_t){ addr, size, 0 };
        return;
    }

    if (mlock(addr, size) == 0) {
        fault_in(addr, size);
        total_locked += size;
        last_lock_ok++;
        m->segs[m->seg_count++] = (seg_t){ addr, size, 1 };
    } else {
        last_lock_fail++;
        last_lock_errno = last_lock_errno ?: errno;
        m->segs[m->seg_count++] = (seg_t){ addr, size, 0 };
    }
}

static int elf_lock(map_t *m) {
    if (m->size < SELFMAG)
        return -EINVAL;

    if (!page_size) {
        page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0)
            return -EINVAL;
    }

    if (memcmp(m->base, ELFMAG, SELFMAG))
        return -EINVAL;

#if __SIZEOF_POINTER__ == 8
    Elf64_Ehdr *eh = (Elf64_Ehdr *)m->base;
    Elf64_Phdr *ph = (Elf64_Phdr *)((char *)m->base + eh->e_phoff);
    for (int i = 0; i < eh->e_phnum; i++) {
        if (ph[i].p_type != PT_LOAD || !(ph[i].p_flags & PF_R) || !ph[i].p_filesz)
            continue;
        size_t off = ph[i].p_offset & ~(page_size - 1);
        size_t len = (ph[i].p_filesz + (ph[i].p_offset - off) + page_size - 1)
                     & ~(page_size - 1);
        if (off + len <= m->size)
            lock_seg(m, (char *)m->base + off, len);
    }
#else
    Elf32_Ehdr *eh = (Elf32_Ehdr *)m->base;
    Elf32_Phdr *ph = (Elf32_Phdr *)((char *)m->base + eh->e_phoff);
    for (int i = 0; i < eh->e_phnum; i++) {
        if (ph[i].p_type != PT_LOAD || !(ph[i].p_flags & PF_R) || !ph[i].p_filesz)
            continue;
        size_t off = ph[i].p_offset & ~(page_size - 1);
        size_t len = (ph[i].p_filesz + (ph[i].p_offset - off) + page_size - 1)
                     & ~(page_size - 1);
        if (off + len <= m->size)
            lock_seg(m, (char *)m->base + off, len);
    }
#endif
    return 0;
}

static int map_file(const char *path, const char *pkg, int permanent) {
    if (map_count >= MAX_MAPS)
        return -ENOMEM;

    char canon[PATH_MAX];
    if (!realpath(path, canon))
        return -errno;

    for (int i = 0; i < map_count; i++) {
        if (!strcmp(maps[i].path, canon)) {
            if (permanent)
                maps[i].permanent = 1;
            return 0;
        }
    }

    int fd = open(canon, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -errno;

    struct stat st;
    if (fstat(fd, &st) || st.st_size == 0) {
        close(fd);
        return -EINVAL;
    }

    void *addr = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (addr == MAP_FAILED)
        return -errno;

    map_t *m = &maps[map_count++];
    snprintf(m->path, sizeof(m->path), "%s", canon);
    snprintf(m->pkg, sizeof(m->pkg), "%s", pkg ? pkg : "");
    m->base = addr;
    m->size = st.st_size;
    m->seg_count = 0;
    m->permanent = permanent;
    return 0;
}

static int lock_all(void) {
    last_lock_ok = last_lock_fail = last_lock_errno = 0;
    for (int i = 0; i < map_count; i++)
        elf_lock(&maps[i]);
    return last_lock_fail ? -last_lock_fail : 0;
}

__attribute__((visibility("default")))
void coreshift_preload_rollback(void) {
    pthread_mutex_lock(&preload_mutex);

    for (int i = 0; i < map_count; i++) {
        map_t *m = &maps[i];

        for (int s = 0; s < m->seg_count; s++) {
            if (m->segs[s].locked) {
                munlock(m->segs[s].addr, m->segs[s].size);
                if (total_locked >= m->segs[s].size)
                    total_locked -= m->segs[s].size;
                else
                    total_locked = 0;
            }
        }

        if (m->base && m->size)
            munmap(m->base, m->size);

        memset(m, 0, sizeof(*m));
    }

    map_count = 0;
    last_lock_ok = 0;
    last_lock_fail = 0;
    last_lock_errno = 0;
    preload_done = 0;

    pthread_mutex_unlock(&preload_mutex);
}

int core_lock(const char *list_path) {
    if (!list_path)
        return -EINVAL;

    pthread_mutex_lock(&preload_mutex);
    if (preload_done) {
        pthread_mutex_unlock(&preload_mutex);
        return -EALREADY;
    }

    FILE *f = fopen(list_path, "r");
    if (!f) {
        pthread_mutex_unlock(&preload_mutex);
        return -errno;
    }

    int permanent = strstr(list_path, "static") != NULL;
    char line[MAX_LINE], pkg[MAX_PKG] = "";
    int failures = 0;

    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n")] = 0;
        if (!line[0])
            continue;

        if (line[0] == '[') {
            char *e = strchr(line, ']');
            if (e && e > line + 1) {
                *e = 0;
                snprintf(pkg, sizeof(pkg), "%s", line + 1);
            }
            continue;
        }

        if (map_file(line, pkg, permanent) < 0)
            failures++;
    }

    fclose(f);
    pthread_mutex_unlock(&preload_mutex);

    return failures ? -failures : 0;
}

int core_last_lock_ok(void)    { return last_lock_ok; }
int core_last_lock_fail(void)  { return last_lock_fail; }
int core_last_lock_errno(void) { return last_lock_errno; }

__attribute__((visibility("default")))
int spawn_capture(char *const argv[], char *buf, size_t cap) {
    if (!argv || !argv[0] || !buf || cap < 2)
        return -EINVAL;

    int pfd[2];
    if (pipe2(pfd, O_CLOEXEC) != 0)
        return -errno;

    posix_spawn_file_actions_t fa;
    int rc = posix_spawn_file_actions_init(&fa);
    if (rc != 0) {
        close(pfd[0]);
        close(pfd[1]);
        return -rc;
    }

    posix_spawn_file_actions_adddup2(&fa, pfd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa, pfd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa, pfd[0]);
    posix_spawn_file_actions_addclose(&fa, pfd[1]);

    pid_t pid;
    rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);

    close(pfd[1]);

    if (rc != 0) {
        close(pfd[0]);
        return -rc;
    }

    ssize_t off = 0;
    int truncated = 0;

    for (;;) {
        ssize_t n = read(pfd[0], buf + off, cap - 1 - off);
        if (n > 0) {
            off += n;
            if (off >= (ssize_t)cap - 1) {
                truncated = 1;
                break;
            }
            continue;
        }
        if (n == 0)
            break;
        if (errno == EINTR)
            continue;
        close(pfd[0]);
        waitpid(pid, NULL, 0);
        return -errno;
    }

    close(pfd[0]);

    int status;
    while (waitpid(pid, &status, 0) == -1) {
        if (errno != EINTR)
            return -errno;
    }

    buf[off] = 0;

    if (off == 0)
        return -ENODATA;

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return -ECHILD;

    return truncated ? -ENOSPC : 0;
}

static int collect_notification_pkgs(char out[][128], int max) {
    char buf[64 * 1024];
    char *argv[] = {
        "/system/bin/cmd",
        "notification",
        "list",
        NULL
    };

    if (spawn_capture(argv, buf, sizeof(buf)) != 0)
        return 0;

    int n = 0;
    char *l = strtok(buf, "\n");

    while (l && n < max) {
        if (l[0] != '0') {
            l = strtok(NULL, "\n");
            continue;
        }

        char *p = strchr(l, '|');
        if (!p) goto next;
        p++;

        char *e = strchr(p, '|');
        if (!e) goto next;
        *e = 0;

        int dup = 0;
        for (int i = 0; i < n; i++)
            if (!strcmp(out[i], p))
                dup = 1;

        if (!dup) {
            strncpy(out[n], p, 127);
            out[n][127] = 0;
            n++;
        }

    next:
        l = strtok(NULL, "\n");
    }

    return n;
}

static int is_numeric(const char *s) {
    return s && *s && strspn(s, "0123456789") == strlen(s);
}

static int collect_pkg_pids(const char *pkg, pid_t *out, int max) {
    char buf[1024];
    char *argv[] = {
        "/system/bin/pidof",
        (char *)pkg,
        NULL
    };

    if (spawn_capture(argv, buf, sizeof(buf)) != 0)
        return 0;

    int n = 0;
    char *t = strtok(buf, " ");
    while (t && n < max) {
        if (is_numeric(t))
            out[n++] = atoi(t);
        t = strtok(NULL, " ");
    }
    return n;
}

static int should_demote(int uid, const char *name) {
    if (uid == 0)
        return 0;

    if (uid == 1000)
        return name_in_list(name, system_demote_names);

    return 1;
}

__attribute__((visibility("default")))
int resolve_local(const char *name, char *out, size_t cap) {
    char exe[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0) return -1;
    exe[n] = 0;

    char *p = strrchr(exe, '/');
    if (!p) return -1;
    *p = 0;

    snprintf(out, cap, "%s/%s", exe, name);
    return 0;
}

static int resolve_base(char *out, size_t cap) {
    ssize_t n = readlink("/proc/self/exe", out, cap - 1);
    if (n <= 0) return -1;
    out[n] = 0;
    char *p = strrchr(out, '/');
    if (!p) return -1;
    *p = 0;
    return 0;
}

static int read_status(pid_t pid, int *uid, char *name) {
    char path[64];
    snprintf(path, sizeof(path), STATUS_FMT, pid);

    FILE *f = fopen(path, "r");
    if (!f) return -1;

    char line[256];
    *uid = -1;
    name[0] = 0;

    while (fgets(line, sizeof(line), f)) {
        if (!strncmp(line, "Uid:", 4))
            sscanf(line + 4, "%d", uid);
        else if (!strncmp(line, "Name:", 5))
            sscanf(line + 5, "%63s", name);
    }

    fclose(f);
    return (*uid >= 0 && name[0]) ? 0 : -1;
}

__attribute__((visibility("default")))
int read_cmdline(pid_t pid, char *out, size_t cap) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);

    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return -1;

    ssize_t n = read(fd, out, cap - 1);
    close(fd);
    if (n <= 0)
        return -1;

    out[n] = 0;

    for (ssize_t i = 0; i < n; i++) {
        if (out[i] == '\0') {
            out[i] = '\0';
            break;
        }
    }

    return 0;
}

static int read_comm(pid_t pid, pid_t tid, char *out, size_t cap) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/task/%d/comm", pid, tid);
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n = read(fd, out, cap - 1);
    close(fd);
    if (n <= 0) return -1;
    out[n] = 0;
    out[strcspn(out, "\n")] = 0;
    return 0;
}

static int perf_thread(const char *comm) {
    return strstr(comm, "RenderThread") ||
           strstr(comm, "RenderEngine") ||
           strstr(comm, "hwui") ||
           strstr(comm, "SurfaceSync") ||
           strstr(comm, "appSf");
}

__attribute__((visibility("default")))
int find_pid_by_pkg(const char *pkg, pid_t *out) {
    if (!pkg || !*pkg || !out)
        return -EINVAL;

    static const char *top_cgroup;
    static int resolved;

    if (!resolved) {
        if (access("/dev/cpuset/top-app/cgroup.procs", R_OK) == 0)
            top_cgroup = "/dev/cpuset/top-app/cgroup.procs";
        else if (access("/dev/stune/top-app/cgroup.procs", R_OK) == 0)
            top_cgroup = "/dev/stune/top-app/cgroup.procs";
        else
            top_cgroup = NULL;
        resolved = 1;
    }

    if (!top_cgroup)
        return -ESRCH;

    FILE *f = fopen(top_cgroup, "r");
    if (!f)
        return -ESRCH;

    char line[64];
    char cmdline[256];

    while (fgets(line, sizeof(line), f)) {
        pid_t pid = (pid_t)atoi(line);
        if (pid <= 0)
            continue;

        if (read_cmdline(pid, cmdline, sizeof(cmdline)) != 0)
            continue;

        if (!strcmp(cmdline, pkg)) {
            *out = pid;
            fclose(f);
            return 0;
        }
    }

    fclose(f);
    return -ESRCH;
}

static int runtime_elf_class(void) {
    return (sizeof(void*) == 8) ? ELFCLASS64 : ELFCLASS32;
}

static const char *abi_libdir(void) {
    return (runtime_elf_class() == ELFCLASS64)
        ? "/system/lib64"
        : "/system/lib";
}

static int elf_matches_runtime(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;

    unsigned char id[EI_NIDENT];
    int ok = read(fd, id, sizeof(id)) == sizeof(id) &&
             memcmp(id, ELFMAG, SELFMAG) == 0 &&
             id[EI_CLASS] == runtime_elf_class();

    close(fd);
    return ok;
}

static const char *STATIC_LIBS[] = {
    "libc.so",
    "libm.so",
    "libdl.so",
    "liblog.so",
    "libz.so",
    "libc++.so",
    "libcrypto.so",
    NULL
};

static int collect_recent_pkgs(char out[][128], int max) {
    FILE *fp = popen("/system/bin/dumpsys usagestats", "r");
    if (!fp)
        return 0;

    char *events[MAX_EVENTS];
    int ev_n = 0;

    char line[1024];
    while (fgets(line, sizeof(line), fp) && ev_n < MAX_EVENTS) {
        if (!strstr(line, "type=ACTIVITY_"))
            continue;

        char *p = strstr(line, "package=");
        if (!p)
            continue;

        p += 8;
        char *e = strchr(p, ' ');
        if (e) *e = 0;

        events[ev_n++] = strdup(p);
    }

    pclose(fp);

    int out_n = 0;
    for (int i = ev_n - 1; i >= 0 && out_n < max; i--) {
        int dup = 0;
        for (int j = 0; j < out_n; j++)
            if (!strcmp(out[j], events[i]))
                dup = 1;
        if (!dup) {
            strncpy(out[out_n], events[i], 127);
            out[out_n][127] = 0;
            out_n++;
        }
    }

    for (int i = 0; i < ev_n; i++)
        free(events[i]);

    return out_n;
}

static void scan_libs_recursive(
    FILE *out,
    const char *pkg,
    const char *dir,
    int *written,
    int so_limit,
    int *header_written
) {
    if (*written >= so_limit)
        return;

    DIR *d = opendir(dir);
    if (!d)
        return;

    struct dirent *e;
    while ((e = readdir(d)) && *written < so_limit) {
        if (e->d_name[0] == '.')
            continue;

        char path[MAX_PATH];
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);

        struct stat st;
        if (stat(path, &st) != 0)
            continue;

        if (S_ISDIR(st.st_mode)) {
            scan_libs_recursive(out, pkg, path, written, so_limit, header_written);
        } else if (S_ISREG(st.st_mode)) {
            size_t len = strlen(e->d_name);
            if (len <= 3 || strcmp(e->d_name + len - 3, ".so"))
                continue;
            if (!elf_matches_runtime(path))
                continue;

            if (!*header_written) {
                fprintf(out, "[%s]\n", pkg);
                *header_written = 1;
            }

            fprintf(out, "%s\n", path);
            (*written)++;
        }
    }

    closedir(d);
}

static int write_app_libs(FILE *out, const char *pkg, int so_limit) {
    char buf[64 * 1024];
    char *argv[] = {
        "/system/bin/cmd",
        "package",
        "path",
        (char *)pkg,
        NULL
    };

    if (spawn_capture(argv, buf, sizeof(buf)) != 0)
        return 0;

    int written = 0;
    int header_written = 0;

    char *l = strtok(buf, "\n");
    while (l && written < so_limit) {
        if (!strncmp(l, "package:", 8)) {
            char *apk = l + 8;
            char *s = strrchr(apk, '/');
            if (!s) {
                l = strtok(NULL, "\n");
                continue;
            }
            *s = 0;

            char libroot[MAX_PATH];
            snprintf(libroot, sizeof(libroot), "%s/lib", apk);

            scan_libs_recursive(out, pkg, libroot,
                                &written, so_limit, &header_written);
        }
        l = strtok(NULL, "\n");
    }

    if (header_written)
        fputc('\n', out);

    return written;
}

__attribute__((visibility("default")))
int read_default_ime(char *out, size_t cap) {
    char buf[256];
    char *argv[] = {
        "/system/bin/settings",
        "get",
        "secure",
        "default_input_method",
        NULL
    };

    if (spawn_capture(argv, buf, sizeof(buf)) != 0)
        return -1;

    buf[strcspn(buf, "\n")] = 0;
    char *s = strchr(buf, '/');
    if (s) *s = 0;

    strncpy(out, buf, cap - 1);
    out[cap - 1] = 0;

    return out[0] ? 0 : -1;
}

__attribute__((visibility("default")))
void daemon_loop(void) {
    char ime[128] = "";
    read_default_ime(ime, sizeof(ime));

    static const char *top_cgroups[] = {
        "/dev/cpuset/top-app/cgroup.procs",
        "/dev/stune/top-app/cgroup.procs",
        NULL
    };

    int tick = 0;

    for (;;) {
        if ((tick % 240) == 0)
            coreshift_demote_background();

        int boosted = 0;

        for (int i = 0; top_cgroups[i] && !boosted; i++) {
            FILE *f = fopen(top_cgroups[i], "r");
            if (!f)
                continue;

            char line[64];
            while (fgets(line, sizeof(line), f)) {
                pid_t pid = atoi(line);
                if (pid <= 0)
                    continue;

                char pkg[256];
                if (read_cmdline(pid, pkg, sizeof(pkg)) != 0)
                    continue;

                if (!strchr(pkg, '.'))
                    continue;

                if (ime[0] && !strcmp(pkg, ime))
                    continue;

                if (coreshift_boost_pkg(pkg) == 0) {
                    boosted = 1;
                    break;
                }
            }

            fclose(f);
        }

        sleep(15);
        tick++;
    }
}

static pid_t get_init_service_pid(const char *name) {
    char key[PROP_NAME_MAX];
    char val[PROP_VALUE_MAX];

    snprintf(key, sizeof(key), "init.svc_debug_pid.%s", name);

    if (__system_property_get(key, val) <= 0)
        return -1;

    if (!val[0] || !is_numeric(val))
        return -1;

    pid_t pid = (pid_t)atoi(val);
    return pid > 0 ? pid : -1;
}

static void demote_root_services_from_props(void) {
    for (int i = 0; root_demote_names[i]; i++) {
        const char *name = root_demote_names[i];
        pid_t pid = get_init_service_pid(name);

        if (pid <= 0)
            continue;

        core_demote_tid(pid);
    }
}

__attribute__((visibility("default")))
int coreshift_boost_pkg(const char *pkg) {
    if (!pkg || !*pkg) return -EINVAL;

    pid_t pid;
    if (find_pid_by_pkg(pkg, &pid) != 0) {
        return -ESRCH;
    }

    char taskdir[64];
    snprintf(taskdir, sizeof(taskdir), "/proc/%d/task", pid);

    DIR *td = opendir(taskdir);
    if (!td) {
        return 0;
    }

    struct dirent *e;
    char comm[64];
    int count = 0;

    while ((e = readdir(td))) {
        if (!isdigit(e->d_name[0])) continue;

        pid_t tid = (pid_t)atoi(e->d_name);
        if (read_comm(pid, tid, comm, sizeof(comm)) != 0) {
            continue;
        }

        if (tid == pid || perf_thread(comm)) {
            core_boost_tid(tid);
            count++;
        }
    }

    closedir(td);

    return 0;
}

__attribute__((visibility("default")))
int coreshift_demote_background(void) {
    if (is_root())
         demote_root_services_from_props();

    char notif_pkgs[64][128];
    int notif_n = collect_notification_pkgs(notif_pkgs, 64);

    pid_t notif_pids[256];
    int notif_pid_n = 0;

    for (int i = 0; i < notif_n; i++)
        notif_pid_n += collect_pkg_pids(
            notif_pkgs[i],
            notif_pids + notif_pid_n,
            256 - notif_pid_n
        );

    DIR *proc = opendir(PROC_ROOT);
    if (!proc)
        return -ENOENT;

    pid_t self = getpid();
    struct dirent *e;

    while ((e = readdir(proc))) {
        if (!is_numeric(e->d_name))
            continue;

        pid_t pid = atoi(e->d_name);
        if (pid == self)
            continue;

        for (int i = 0; i < notif_pid_n; i++)
            if (pid == notif_pids[i])
                goto skip;

        int uid;
        char name[64];
        if (read_status(pid, &uid, name) != 0)
            continue;

        if (!should_demote(uid, name))
            continue;

        char taskdir[64];
        snprintf(taskdir, sizeof(taskdir), "/proc/%d/task", pid);

        if (is_root()) {
            core_demote_tid(pid);
            normalize_root_sched(pid, name);
            continue;
        }

        DIR *td = opendir(taskdir);
        if (!td) {
            core_demote_tid(pid);
            continue;
        }

        struct dirent *t;
        while ((t = readdir(td))) {
            if (is_numeric(t->d_name))
                core_demote_tid((pid_t)atoi(t->d_name));
        }
        closedir(td);

    skip:
        ;
    }

    closedir(proc);
    return 0;
}

__attribute__((visibility("default")))
int coreshift_generate_lists(void) {
    char base[MAX_PATH];
    if (resolve_base(base, sizeof(base)) != 0)
        return -ENOENT;

    char lock_path[MAX_PATH];
    snprintf(lock_path, sizeof(lock_path),
             "%s/%s", base, CORELIST_LOCK);

    if (access(lock_path, F_OK) != 0) {
        char stat_path[MAX_PATH];
        snprintf(stat_path, sizeof(stat_path),
                 "%s/%s", base, CORELIST_STATIC);

        FILE *st = fopen(stat_path, "w");
        if (st) {
            const char *libdir = abi_libdir();
            for (int i = 0; STATIC_LIBS[i]; i++) {
                char full[MAX_PATH];
                snprintf(full, sizeof(full),
                         "%s/%s", libdir, STATIC_LIBS[i]);
                struct stat sb;
                if (stat(full, &sb) == 0 &&
                    S_ISREG(sb.st_mode) &&
                    elf_matches_runtime(full)) {
                    fprintf(st, "%s\n", full);
                }
            }
            fclose(st);
            close(open(lock_path, O_CREAT | O_EXCL, 0600));
        }
    }

    char dyn_path[MAX_PATH];
    snprintf(dyn_path, sizeof(dyn_path),
             "%s/%s", base, CORELIST_DYNAMIC);

    FILE *dyn = fopen(dyn_path, "w");
    if (!dyn)
        return -EACCES;

    char pkgs[MAX_PKGS][128];
    int n = collect_recent_pkgs(pkgs, MAX_PKGS);

    int64_t mem =
        (int64_t)sysconf(_SC_PHYS_PAGES) *
        (int64_t)sysconf(_SC_PAGESIZE);

    int so_limit = (mem < (7LL * 1024 * 1024 * 1024)) ? 5 : 8;

    for (int i = 0; i < n; i++)
        write_app_libs(dyn, pkgs[i], so_limit);

    fclose(dyn);

    char stat_file[PATH_MAX];
    char dyn_file[PATH_MAX];

    if (resolve_local(CORELIST_STATIC, stat_file, sizeof(stat_file)) != 0)
        return -ENOENT;
    if (resolve_local(CORELIST_DYNAMIC, dyn_file, sizeof(dyn_file)) != 0)
        return -ENOENT;

    core_lock(stat_file);
    core_lock(dyn_file);

    pthread_mutex_lock(&preload_mutex);
    if (!preload_done) {
        lock_all();
        preload_done = 1;
    }
    pthread_mutex_unlock(&preload_mutex);

    return 0;
}
