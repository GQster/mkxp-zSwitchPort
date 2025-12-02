#ifndef SWITCH_FILESYSTEM_SHIM_H
#define SWITCH_FILESYSTEM_SHIM_H

#ifdef __SWITCH__
#include <sys/stat.h>
#include <errno.h>

/* AT_* constants */
#ifndef AT_FDCWD
#define AT_FDCWD (-100)
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif

/* Stub unsupported POSIX functions */
static inline int symlink(const char *target, const char *linkpath) {
    (void)target; (void)linkpath;
    errno = ENOSYS;
    return -1;
}

static inline ssize_t readlink(const char *pathname, char *buf, size_t bufsiz) {
    (void)pathname; (void)buf; (void)bufsiz;
    errno = EINVAL;
    return -1;
}

static inline int utimensat(int dirfd, const char *pathname, 
                            const struct timespec times[2], int flags) {
    (void)dirfd; (void)pathname; (void)times; (void)flags;
    return 0;
}

static inline int truncate(const char *path, off_t length) {
    (void)path; (void)length;
    errno = ENOSYS;
    return -1;
}

#endif /* __SWITCH__ */
#endif /* SWITCH_FILESYSTEM_SHIM_H */
