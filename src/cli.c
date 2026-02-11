#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <sys/system_properties.h>

#include "core.h"

#define TRACE(fmt, ...) \
    do { if (trace_enabled) fprintf(stderr, "[trace] " fmt "\n", ##__VA_ARGS__); } while (0)

static char *xml_buf = NULL;
static size_t xml_len = 0;
static char lang[3] = "en";

static int is_lang_code(const char *s) {
    return s && strlen(s) == 2 &&
           ((s[0] >= 'a' && s[0] <= 'z') || (s[0] >= 'A' && s[0] <= 'Z')) &&
           ((s[1] >= 'a' && s[1] <= 'z') || (s[1] >= 'A' && s[1] <= 'Z'));
}

static void set_lang2(const char *s) {
    lang[0] = s[0];
    lang[1] = s[1];
    lang[2] = 0;
}

static void detect_lang(int argc, char **argv) {
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--lang") && is_lang_code(argv[i + 1])) {
            set_lang2(argv[i + 1]);
            TRACE("lang from CLI: %s", lang);
            return;
        }
    }

#ifdef __ANDROID__
    char prop[PROP_VALUE_MAX];
    if (__system_property_get("persist.sys.locale", prop) > 0 ||
        __system_property_get("ro.product.locale", prop) > 0) {
        if (strlen(prop) >= 2) {
            set_lang2(prop);
            TRACE("lang from android: %s", lang);
            return;
        }
    }
#endif

    const char *e = getenv("LANG");
    if (e && strlen(e) >= 2) {
        set_lang2(e);
        TRACE("lang from env: %s", lang);
        return;
    }

    strcpy(lang, "en");
    TRACE("lang fallback: en");
}

static int load_lang_xml(void) {
    char full[PATH_MAX];

    if (resolve_local("cli.xml", full, sizeof(full)) < 0)
        return -1;

    FILE *f = fopen(full, "rb");
    if (!f)
        return -1;

    fseek(f, 0, SEEK_END);
    xml_len = ftell(f);
    fseek(f, 0, SEEK_SET);

    xml_buf = malloc(xml_len + 1);
    if (!xml_buf) {
        fclose(f);
        return -1;
    }

    fread(xml_buf, 1, xml_len, f);
    xml_buf[xml_len] = 0;
    fclose(f);

    TRACE("loaded %s (%zu bytes)", full, xml_len);
    return 0;
}

static void xml_unescape(char *s) {
    char *w = s;
    for (; *s; s++) {
        if (s[0] == '&' && !strncmp(s, "&lt;", 4)) {
            *w++ = '<'; s += 3;
        } else if (s[0] == '&' && !strncmp(s, "&gt;", 4)) {
            *w++ = '>'; s += 3;
        } else if (s[0] == '&' && !strncmp(s, "&amp;", 5)) {
            *w++ = '&'; s += 4;
        } else {
            *w++ = *s;
        }
    }
    *w = 0;
}

static char *xml_get(const char *id, const char *fallback) {
    if (!xml_buf)
        return strdup(fallback ? fallback : "");

    char key[64];
    snprintf(key, sizeof(key), "<section id=\"%s\">", id);

    char *sec = strstr(xml_buf, key);
    if (!sec)
        return strdup(fallback ? fallback : "");

    char *body = sec + strlen(key);
    char *end  = strstr(body, "</section>");
    if (!end)
        return strdup(fallback ? fallback : "");

    char tag[8];
    snprintf(tag, sizeof(tag), "<%s>", lang);

    char *s = strstr(body, tag);
    if (!s || s >= end) {
        s = strstr(body, "<en>");
        if (!s || s >= end)
            return strdup(fallback ? fallback : "");
        s += 4;
    } else {
        s += strlen(tag);
    }

    size_t len = 0;
    while (s + len < end && s[len] != '<')
        len++;

    char *out = malloc(len + 1);
    if (!out)
        return strdup(fallback ? fallback : "");

    memcpy(out, s, len);
    out[len] = 0;
    xml_unescape(out);
    return out;
}

struct cmd_alias {
    char *alias;
    const char *cmd;
};

static struct cmd_alias aliases[32];
static size_t alias_count = 0;

static void add_alias(const char *alias, const char *cmd) {
    if (!alias || !*alias)
        return;

    for (size_t i = 0; i < alias_count; i++) {
        if (!strcmp(aliases[i].alias, alias))
            return;
    }

    aliases[alias_count].alias = strdup(alias);
    aliases[alias_count].cmd   = cmd;
    alias_count++;
}

static void load_cmd_aliases(void) {
    struct {
        const char *id;
        const char *cmd;
    } map[] = {
        { "alias_preload",  "preload"  },
        { "alias_rollback", "rollback" },
        { "alias_boost",    "boost"    },
        { "alias_demote",   "demote"   },
        { "alias_daemon",   "daemon"   },
    };

    for (size_t i = 0; i < sizeof(map)/sizeof(map[0]); i++) {
        char *loc = xml_get(map[i].id, "");
        add_alias(loc, map[i].cmd);
        free(loc);

        add_alias(map[i].cmd, map[i].cmd); 
    }

    TRACE("loaded %zu command aliases", alias_count);
}

static void free_cmd_aliases(void) {
    for (size_t i = 0; i < alias_count; i++) {
        free(aliases[i].alias);
        aliases[i].alias = NULL;
    }
    alias_count = 0;
}


static const char *resolve_cmd(const char *arg) {
    if (!arg)
        return NULL;

    for (size_t i = 0; i < alias_count; i++) {
        if (!strcmp(arg, aliases[i].alias))
            return aliases[i].cmd;
    }

    return arg;
}

static const char *cmd_to_alias_id(const char *cmd) {
    if (!strcmp(cmd, "preload"))  return "alias_preload";
    if (!strcmp(cmd, "rollback")) return "alias_rollback";
    if (!strcmp(cmd, "boost"))    return "alias_boost";
    if (!strcmp(cmd, "demote"))   return "alias_demote";
    if (!strcmp(cmd, "daemon"))   return "alias_daemon";
    return NULL;
}

static void usage(const char *prog) {
    char *title = xml_get("title", "coreshift");
    char *usage_h = xml_get("usage", "USAGE");

    char *a_pre   = xml_get("alias_preload", "preload");
    char *a_roll  = xml_get("alias_rollback","rollback");
    char *a_boost = xml_get("alias_boost",   "boost");
    char *a_demo  = xml_get("alias_demote",  "demote");
    char *a_daem  = xml_get("alias_daemon",  "daemon");

    char *arg_pkg = xml_get("arg_package", "<package>");

    char *c_pre   = xml_get("cmd_preload", "");
    char *c_roll  = xml_get("cmd_rollback","");
    char *c_boost = xml_get("cmd_boost",   "");
    char *c_demo  = xml_get("cmd_demote",  "");
    char *c_daem  = xml_get("cmd_daemon",  "");

    fprintf(stderr,
        "%s\n\n"
        "%s\n"
        "  %s %s\n"
        "  %s %s\n"
        "  %s %s %s\n"
        "  %s %s\n"
        "  %s %s\n\n"
        "COMMANDS\n"
        "  %-10s %s\n"
        "  %-10s %s\n"
        "  %-10s %s\n"
        "  %-10s %s\n"
        "  %-10s %s\n",
        title,
        usage_h,
        prog, a_pre,
        prog, a_roll,
        prog, a_boost, arg_pkg,
        prog, a_demo,
        prog, a_daem,
        a_pre,  c_pre,
        a_roll, c_roll,
        a_boost,c_boost,
        a_demo, c_demo,
        a_daem, c_daem
    );

    free(title);
    free(usage_h);
    free(a_pre); free(a_roll); free(a_boost); free(a_demo); free(a_daem);
    free(arg_pkg);
    free(c_pre); free(c_roll); free(c_boost); free(c_demo); free(c_daem);
}

int main(int argc, char **argv) {
    const char *prog = argv[0] ? argv[0] : "coreshift";

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-t")) {
            trace_enabled = 1;
            memmove(&argv[i], &argv[i + 1],
                    (argc - i - 1) * sizeof(char *));
            argc--;
            i--;
        }
    }

    detect_lang(argc, argv);
    load_lang_xml();
    load_cmd_aliases();

    if (argc < 2) {
        usage(prog);
        return 1;
    }

    const char *cmd = resolve_cmd(argv[1]);

int ret;

/* command dispatch */
if (!strcmp(cmd, "preload"))
    ret = coreshift_generate_lists() < 0;
else if (!strcmp(cmd, "rollback")) {
    coreshift_preload_rollback();
    ret = 0;
}
else if (!strcmp(cmd, "boost")) {
    if (argc != 3) {
        char *arg_pkg = xml_get("arg_package", "<package>");
        const char *aid = cmd_to_alias_id(cmd);
char *disp_cmd = xml_get(aid ? aid : "alias_boost", cmd);

fprintf(stderr, "%s %s %s\n", prog, disp_cmd, arg_pkg);
free(disp_cmd);
        free(arg_pkg);
        ret = 1;
    } else {
        ret = coreshift_boost_pkg(argv[2]) < 0;
    }
}
else if (!strcmp(cmd, "demote"))
    ret = coreshift_demote_background() < 0;
else if (!strcmp(cmd, "daemon")) {
    daemon_loop();
    ret = 0;
}
else {
    usage(prog);
    ret = 1;
}

free_cmd_aliases();
free(xml_buf);
xml_buf = NULL;
xml_len = 0;

return ret;
}