/**
 * sshfs-win.c
 *
 * Copyright 2015-2021 Bill Zissimopoulos
 */
/*
 * This file is part of SSHFS-Win.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <assert.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>

char sshfs[PATH_MAX];
char ssh_command_opt[PATH_MAX];
char fsp_domain[1024] = "", fsp_user[1024] = "", fsp_home[PATH_MAX] = "";

#if 0
#define execve pr_execv
static void pr_execv(const char *path, char *argv[], ...)
{
    fprintf(stderr, "%s\n", path);
    for (; 0 != *argv; argv++)
        fprintf(stderr, "    %s\n", *argv);
}
#endif

static void usage(void)
{
    fprintf(stderr,
        "usage: sshfs-win cmd SSHFS_COMMAND_LINE\n"
        "    SSHFS_COMMAND_LINE  command line to pass to sshfs\n"
        "\n"
        "usage: sshfs-win svc PREFIX X: [-user [DOMAIN/]USERNAME] [-home HOME] [SSHFS_OPTIONS]\n"
        "    PREFIX              Windows UNC prefix (note single backslash). USE ONLY BACKSLASH!!\n"
        "                        \\sshfs[.SUFFIX]\\[LOCUSER=]REMUSER@HOST[!PORT][\\PATH]\n"
        "                        \\sshfs[.SUFFIX]\\alias[\\PATH]\n"
        "                        sshfs: remote user home dir\n"
        "                        sshfs.r: remote root dir\n"
        "                        sshfs.k: remote user home dir with key authentication\n"
        "                        sshfs.kr: remote root dir with key authentication\n"
        "    LOCUSER             local user (DOMAIN+USERNAME) (literally a + character)\n"
        "    REMUSER             remote user\n"
        "    HOST                remote host\n"
        "    PORT                remote port\n"
        "    PATH                remote path (relative to remote home or root)\n"
        "    X:                  mount drive\n"
        "    DOMAIN:             local user domain\n"
        "    USERNAME            local user name without domain\n"
        "    HOME:               local user home folder\n"
        "    SSHFS_OPTIONS       additional options to pass to SSHFS\n"
        "\n"
        "    Search path for autentication keys are HOME/.ssh/id_rsa.REMUSER first and then HOME/.ssh/id_rsa\n");
    exit(2);
}

static void concat_argv(char *dst[], char *src[])
{
    for (; 0 != *dst; dst++)
        ;
    for (; 0 != (*dst = *src); dst++, src++)
        ;
}

static void opt_escape(const char *opt, char *escaped, size_t size)
{
    const char *p = opt;
    char *q = escaped, *endq = escaped + size;
    for (; *p && (endq > q + 1); p++, q++)
    {
        if (',' == *p || '\\' == *p)
            *q++ = '\\';
        *q = *p;
    }
    *q = '\0';
}

static uint32_t reg_get(const char *cls, const char *name)
{
    char regpath[256];
    int regfd;
    uint32_t value = -1;

    snprintf(regpath, sizeof regpath,
        "/proc/registry32/HKEY_LOCAL_MACHINE/Software/WinFsp/Services/%s/%s", cls, name);

    regfd = open(regpath, O_RDONLY);
    if (-1 != regfd)
    {
        if (sizeof value != read(regfd, &value, sizeof value))
            value = -1;
        close(regfd);
    }

    return value;
}

static int fixenv_and_execv(const char *path, char **argv)
{
    static char *default_environ[] = { "PATH=/bin", 0 };
    extern char **environ;
    char **oldenv, **oldp;
    char **newenv, **newp;
    size_t len, siz;
    int res;

    oldenv = environ;

    siz = 0;
    for (oldp = oldenv; *oldp; oldp++)
    {
        if (0 == strncmp(*oldp, "PATH=", 5))
        {
            len = strlen(*oldp + 5);
            siz += len + sizeof "PATH=/usr/bin:";
        }
        else
        {
            len = strlen(*oldp);
            siz += len + 1;
        }
    }
    oldp++;

    newenv = malloc((oldp - oldenv) * sizeof(char *) + siz);
    if (0 != newenv)
    {
        siz = (oldp - oldenv) * sizeof(char *);
        for (oldp = oldenv, newp = newenv; *oldp; oldp++, newp++)
        {
            *newp = (char *)newenv + siz;
            if (0 == strncmp(*oldp, "PATH=", 5))
            {
                len = strlen(*oldp + 5);
                siz += len + sizeof "PATH=/usr/bin:";
                memcpy(*newp, "PATH=/usr/bin:", sizeof "PATH=/usr/bin:" - 1);
                memcpy(*newp + sizeof "PATH=/usr/bin:" - 1, *oldp + 5, len + 1);
            }
            else
            {
                len = strlen(*oldp);
                siz += len + 1;
                memcpy(*newp, *oldp, len + 1);
            }
        }
        *newp = 0;
    }
    else
    {
        newenv = default_environ;
        newp = newenv + 1;
    }

#if 1
    res = execve(path, argv, newenv);
#else
    char **p;
    for (p = newenv; *p; p++)
        printf("%s\n", *p);
    assert(newp == p);
#endif

    if (newenv != default_environ)
        free(newenv);

    return res;
}

static int do_cmd(int local_argc, char *local_argv[])
{
    if (200 < local_argc)
        usage();

    char *sshfs_argv[256] =
    {
        sshfs, 0,
    };

    concat_argv(sshfs_argv, local_argv);

    fixenv_and_execv(sshfs, sshfs_argv);
    return 1;
}

static int do_svc(int local_argc, char *local_argv[])
{
    struct passwd *passwd = 0;
    char idmap[64] = "", authmeth[64 + 1024] = "", volpfx[256] = "", portopt[256] = "", remote[256] = "";
    char escaped[1024] = "";
    char locuser_wdom[1024] = "", locuser[1024] = "";
    char *cls, *locdom, *remuser, *host, *port, *root, *path, *p, *tmpp;
    char *remote_string, *local_mount;

    char *sshfs_argv[256] = { [ 0 ... 255] = 0};
    int sshfs_argv_idx = 0;
    
    remote_string = local_argv[0];
    local_mount = local_argv[1];

    snprintf(volpfx, sizeof volpfx, "--VolumePrefix=%s", remote_string);

    /* translate backslash to forward slash */
    for (p = remote_string; *p; p++)
        if ('\\' == *p)
            *p = '/';

    /* skip class name */
    p = remote_string;
    while ('/' == *p)
        p++;
    cls = p;
    while (*p && ('/' != *p))
        p++;
    if (*p)
        *p++ = '\0';
    while ('/' == *p)
        p++;
    root = 1 == reg_get(cls, "sshfs.rootdir") ? "/" : "";

    /* parse instance name (syntax: [locuser=]user@host[!port]) */
    tmpp = p;
    locdom = remuser = host = port = 0;
    while (*p && ('/' != *p))
    {
        if ('+' == *p) {
            *p = '\0';
            locdom = tmpp;
            tmpp = p + 1;
        }
        if ('=' == *p) {
            *p = '\0';
            snprintf(locuser, sizeof locuser, "%s", tmpp);
            tmpp = p + 1;
        }
        if ('@' == *p) {
            *p = '\0';
            remuser = tmpp;
            tmpp = p + 1;
            host = tmpp;
        }
        if ('!' == *p) {
            *p = '\0';
            tmpp = p + 1;
            port = p + 1;
        }
        p++;
    }
    if (*p)
        *p++ = '\0';
    path = p;
    if (port != 0)
    {
        opt_escape(port, escaped, sizeof escaped);
        snprintf(portopt, sizeof portopt, "-oPort=%s", escaped);
    }
    else
    {
        portopt[0] = '\0';
    }
    snprintf(remote, sizeof remote, "%s@%s:%s%s", remuser, host, root, path);
    fprintf(stderr, "%s\n", remote);
    
    if ((0 != locdom) && (0 != *locuser)) {
      snprintf(locuser_wdom, sizeof locuser_wdom, "%s/%s", locdom, locuser);
    } else if (0 != *locuser) {
      snprintf(locuser_wdom, sizeof locuser_wdom, "%s", locuser);
    } else {
      if (fsp_domain[0] != 0) {
        snprintf(locuser_wdom, sizeof locuser_wdom, "%s/%s", fsp_domain, fsp_user);
      } else {
        snprintf(locuser_wdom, sizeof locuser_wdom, "%s", fsp_user);
      }
      snprintf(locuser, sizeof locuser, "%s", fsp_user);
    }

    snprintf(idmap, sizeof idmap, "-ouid=-1,gid=-1");
    /* get uid/gid from local user name */
    passwd = getpwnam(locuser_wdom);
    if ((0 == passwd) && (0 != *locuser))
        passwd = getpwnam(locuser);
    if (0 != passwd)
        snprintf(idmap, sizeof idmap, "-ouid=%d,gid=%d", passwd->pw_uid, passwd->pw_gid);

    if (1 == reg_get(cls, "Credentials"))
        snprintf(authmeth, sizeof authmeth,
            "-opassword_stdin,password_stdout");
    else if (0 != passwd)
    {
        char tmpstr[1024];
        snprintf(tmpstr, sizeof tmpstr, "c:/Users/%s/.ssh/id_rsa.%s", passwd->pw_name, remuser);
        if (!access(tmpstr, F_OK) == 0) {
          snprintf(tmpstr, sizeof tmpstr, "c:/Users/%s/.ssh/id_rsa", passwd->pw_name);
        }
        opt_escape(tmpstr, escaped, sizeof escaped);
        snprintf(authmeth, sizeof authmeth,
            "-oPreferredAuthentications=publickey,IdentityFile=\"%s\"", escaped);
    }
    else
    {
        char tmpstr[1024];
        snprintf(tmpstr, sizeof tmpstr, "%s/.ssh/id_rsa.%s", fsp_home, remuser);
        if (!access(tmpstr, F_OK) == 0) {
          snprintf(tmpstr, sizeof tmpstr, "%s/.ssh/id_rsa", fsp_home);
        }
        opt_escape(tmpstr, escaped, sizeof escaped);
        snprintf(authmeth, sizeof authmeth,
            "-oPreferredAuthentications=publickey,IdentityFile=\"%s\"", escaped);
    }

    sshfs_argv[sshfs_argv_idx++] = sshfs;
    sshfs_argv[sshfs_argv_idx++] = "-f";
    sshfs_argv[sshfs_argv_idx++] = "-orellinks";
    sshfs_argv[sshfs_argv_idx++] = "-ofstypename=SSHFS";
    sshfs_argv[sshfs_argv_idx++] = ssh_command_opt;
    sshfs_argv[sshfs_argv_idx++] = "-oUserKnownHostsFile=/dev/null";
    sshfs_argv[sshfs_argv_idx++] = "-oStrictHostKeyChecking=no";
    sshfs_argv[sshfs_argv_idx++] = idmap;
    sshfs_argv[sshfs_argv_idx++] = authmeth;
    sshfs_argv[sshfs_argv_idx++] = volpfx;
    if ('\0' != portopt[0])
      sshfs_argv[sshfs_argv_idx++] = portopt;
    sshfs_argv[sshfs_argv_idx++] = remote;
    sshfs_argv[sshfs_argv_idx++] = local_mount;
    
    if (2 <= local_argc)
        concat_argv(sshfs_argv, local_argv + 2);
      
#if 0
    for(sshfs_argv_idx = 0; sshfs_argv[sshfs_argv_idx] != 0; sshfs_argv_idx++)
      fprintf(stderr, "%s\n", sshfs_argv[sshfs_argv_idx]);
#endif
      
    fixenv_and_execv(sshfs, sshfs_argv);
    return 1;

#undef SSHFS_ARGS
}

int main(int argc, char *argv[])
{
    const char *mode = argv[1];
    
    char path[PATH_MAX];
    char *ptr;
    char *local_argv[] = { [ 0 ... 255] = 0};
    char *domain_sep;
    int local_argc;
    
    if (argc < 4) {
      usage();
      return 1;
    }
    
    local_argc = argc - 2;
    
    // identify the folder where the executables are and set sshfs and ssh absolute path
    readlink("/proc/self/exe", path, PATH_MAX);
//    fprintf(stderr, "%s\n", path);
    ptr = strrchr(path, '/');
    *(++ptr) = 0;
    strcpy(sshfs, path);
    strcat(sshfs, "sshfs.exe");
    strcpy(ssh_command_opt, "-ossh_command=");
    strcat(ssh_command_opt, path);
    strcat(ssh_command_opt, "ssh.exe");
    
    // parse argv for -user and -home options and remove them from arguments list
    for (int i = 2, j = 0; i < argc; i++) {
      if (strcasecmp(argv[i], "-user") == 0) {
        local_argc -= 2;
        domain_sep = strchr(argv[i+1], '/');
        if (domain_sep == NULL) {
          domain_sep = strchr(argv[i+1], '\\');
        }
        if (domain_sep) {
          *domain_sep = 0;          
          strncpy(fsp_domain, argv[i+1], sizeof(fsp_domain));
          strncpy(fsp_user, domain_sep + 1, sizeof(fsp_user));
        } else {
          strncpy(fsp_user, argv[i+1], sizeof(fsp_user));
        }
        i++;
      } else if (strcasecmp(argv[i], "-home") == 0) {
        local_argc -= 2;
        strncpy(fsp_home, argv[i+1], sizeof(fsp_home));
        /* translate backslash to forward slash */
        for (char *p = fsp_home; *p; p++)
            if ('\\' == *p)
                *p = '/';
        i++;
      } else {
        local_argv[j++] = argv[i];
      }
    }

    if ((0 != mode) && (0 == strcmp("cmd", mode)))
        return do_cmd(local_argc, local_argv);
    if ((0 != mode) && (0 == strcmp("svc", mode)))
        return do_svc(local_argc, local_argv);

    usage();
    return 1;
}
