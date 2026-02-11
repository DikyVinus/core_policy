#pragma once

#include <stddef.h>
#include <sys/types.h>

int  coreshift_generate_lists(void);
void coreshift_preload_rollback(void);
int  coreshift_boost_pkg(const char *pkg);
int  coreshift_demote_background(void);
int  spawn_capture(char *const argv[], char *buf, size_t cap);
int  read_cmdline(pid_t pid, char *out, size_t cap);
int resolve_local(const char *name, char *out, size_t cap);
int read_default_ime(char *out, size_t cap);
void daemon_loop(void);
extern int trace_enabled;