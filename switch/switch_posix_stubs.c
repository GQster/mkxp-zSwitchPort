#ifdef __SWITCH__
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <signal.h>
#include <errno.h>

// pthread_kill stub
int pthread_kill(pthread_t thread, int sig) {
    (void)thread; (void)sig;
    return 0; // Success
}

// sysconf stub
long sysconf(int name) {
    (void)name;
    return 0; // Return 0 for most things
}

// getuid stub
uid_t getuid(void) {
    return 0; // Root/Single user
}

// getpwuid stub
struct passwd *getpwuid(uid_t uid) {
    (void)uid;
    return NULL; // No password entry
}

// pipe stub
int pipe(int pipefd[2]) {
    (void)pipefd;
    errno = ENOSYS;
    return -1;
}

// geteuid stub
uid_t geteuid(void) {
    return 0;
}

// getgid stub
gid_t getgid(void) {
    return 0;
}

// getegid stub
gid_t getegid(void) {
    return 0;
}

// waitpid stub
pid_t waitpid(pid_t pid, int *status, int options) {
    (void)pid; (void)status; (void)options;
    errno = ECHILD;
    return -1;
}

// umask stub
mode_t umask(mode_t mask) {
    (void)mask;
    return 0;
}

// execv stub
int execv(const char *path, char *const argv[]) {
    (void)path; (void)argv;
    errno = ENOSYS;
    return -1;
}

// getppid stub
pid_t getppid(void) {
    return 0;
}

// getpwnam stub
struct passwd *getpwnam(const char *name) {
    (void)name;
    return NULL;
}

// endpwent stub
void endpwent(void) {
}

// execl stub
int execl(const char *path, const char *arg, ...) {
    (void)path; (void)arg;
    errno = ENOSYS;
    return -1;
}

// execle stub
int execle(const char *path, const char *arg, ...) {
    (void)path; (void)arg;
    errno = ENOSYS;
    return -1;
}

// rb_mjit_fork stub (Ruby MJIT)
pid_t rb_mjit_fork(void) {
    errno = ENOSYS;
    return -1;
}

// chown stub
int chown(const char *pathname, uid_t owner, gid_t group) {
    (void)pathname; (void)owner; (void)group;
    return 0;
}

// popen stub
FILE *popen(const char *command, const char *type) {
    (void)command; (void)type;
    return NULL;
}

// pclose stub
int pclose(FILE *stream) {
    (void)stream;
    return -1;
}
#endif
