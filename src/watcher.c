#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>
#include <sys/proc_info.h>
#include <libproc.h>

// Path to the inject script — update to match your clone
#ifndef INJECT_SCRIPT
#define INJECT_SCRIPT "/usr/local/bin/instantspaces-inject"
#endif

#ifndef INJECT_MODE
#define INJECT_MODE "min0125"
#endif

// Find the PID of the running Dock process
static pid_t find_dock_pid(void) {
    pid_t pids[1024];
    int n = proc_listallpids(pids, sizeof(pids));
    for (int i = 0; i < n; i++) {
        char name[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(pids[i], name, sizeof(name)) > 0) {
            if (strstr(name, "/Dock")) {
                return pids[i];
            }
        }
    }
    return 0;
}

// Re-inject by exec'ing auto-inject.sh as a child process
static void reinject(void) {
    pid_t child = fork();
    if (child == 0) {
        // Child: exec the inject script
        execl(INJECT_SCRIPT, INJECT_SCRIPT, INJECT_MODE, NULL);
        // Only reached if execl fails
        perror("execl inject script");
        _exit(1);
    }
    // Parent: don't wait — fire and forget
    // launchd manages the watcher's lifecycle; injection confirms itself via log
}

int main(void) {
    // Create the kqueue mailbox
    int kq = kqueue();
    if (kq == -1) {
        perror("kqueue");
        return 1;
    }

    while (1) {
        // Step 1: find Dock — retry until it appears
        pid_t dock_pid = 0;
        while (dock_pid == 0) {
            dock_pid = find_dock_pid();
            if (dock_pid == 0) sleep(1);
        }
        printf("[watcher] watching Dock pid=%d\n", dock_pid);

        // Step 2: register NOTE_EXIT on the Dock PID
        struct kevent change;
        EV_SET(&change, dock_pid, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
        if (kevent(kq, &change, 1, NULL, 0, NULL) == -1) {
            perror("kevent register");
            sleep(1);
            continue;
        }

        // Step 3: block until Dock exits — zero CPU while waiting
        struct kevent event;
        if (kevent(kq, NULL, 0, &event, 1, NULL) == -1) {
            perror("kevent wait");
            sleep(1);
            continue;
        }

        printf("[watcher] Dock exited (pid=%d), re-injecting...\n", dock_pid);

        // Step 4: give launchd time to respawn Dock, then re-inject
        sleep(2);
        reinject();

        // Loop back — find the new Dock PID and re-register
    }

    close(kq);
    return 0;
}
