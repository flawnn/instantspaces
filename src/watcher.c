#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/proc_info.h>
#include <libproc.h>

// Installed by: make install-agent
// Configured by: INJECT_MODE at build time (-DINJECT_MODE='"zero"')
#ifndef INJECT_SCRIPT
#define INJECT_SCRIPT "/usr/local/bin/instantspaces-watcher-inject"
#endif

#ifndef INJECT_MODE
#define INJECT_MODE "min0125"
#endif

// Find the PID of the running Dock process by path
static pid_t find_dock_pid(void) {
    pid_t pids[1024];
    int n = proc_listallpids(pids, sizeof(pids));
    for (int i = 0; i < n; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], path, sizeof(path)) > 0) {
            // Match the full Dock binary path, not just any process containing "Dock"
            if (strstr(path, "/Dock.app/Contents/MacOS/Dock")) {
                return pids[i];
            }
        }
    }
    return 0;
}

// Fork and exec the inject script; reap the child to avoid zombies
static void reinject(void) {
    pid_t child = fork();
    if (child < 0) {
        perror("[watcher] fork");
        return;
    }
    if (child == 0) {
        execl(INJECT_SCRIPT, INJECT_SCRIPT, INJECT_MODE, NULL);
        perror("[watcher] execl");
        _exit(1);
    }
    // Wait for the child so it doesn't become a zombie process
    int status;
    waitpid(child, &status, 0);
    if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
        printf("[watcher] inject script exited with code %d\n", WEXITSTATUS(status));
    }
}

int main(void) {
    int kq = kqueue();
    if (kq == -1) {
        perror("[watcher] kqueue");
        return 1;
    }

    // Initial inject on startup — Dock is already running when the LaunchAgent fires at login
    printf("[watcher] startup: waiting for Dock...\n");
    while (find_dock_pid() == 0) sleep(1);
    sleep(2); // let Dock finish initialising before injecting
    printf("[watcher] startup: injecting\n");
    reinject();

    // Main loop: watch Dock for exit, re-inject on each restart
    while (1) {
        // Find current Dock PID — retry if not yet running
        pid_t dock_pid = 0;
        while (dock_pid == 0) {
            dock_pid = find_dock_pid();
            if (dock_pid == 0) sleep(1);
        }
        printf("[watcher] watching Dock pid=%d\n", dock_pid);

        // Register NOTE_EXIT on the Dock PID — fires the moment Dock exits
        struct kevent change;
        EV_SET(&change, dock_pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
        if (kevent(kq, &change, 1, NULL, 0, NULL) == -1) {
            perror("[watcher] kevent register");
            sleep(1);
            continue;
        }

        // Block here — zero CPU until Dock exits
        struct kevent event;
        if (kevent(kq, NULL, 0, &event, 1, NULL) == -1) {
            perror("[watcher] kevent wait");
            sleep(1);
            continue;
        }

        printf("[watcher] Dock exited (pid=%d), waiting for relaunch...\n", dock_pid);

        // Give launchd ~2s to respawn Dock before injecting
        sleep(2);
        printf("[watcher] re-injecting\n");
        reinject();
    }

    close(kq); // unreachable — loop runs indefinitely
    return 0;
}
