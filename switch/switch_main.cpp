
#ifdef __SWITCH__

// Avoid pulling in Ruby's assert.h from libnx service.h:
// we don't need Ruby APIs in this TU, and ruby/config.h
// is not available in our cross-build include layout.
#define RUBY_ASSERT_H 1

#include <switch.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

// Verbose SWITCH_TRACE output (src/util/switch-trace.h), on when this exists
#define DEBUG_FLAG_FILE "sdmc:/switch/mkxp-z/debug.txt"

// Written before main() so a crash in userAppInit()/the game picker still
// leaves a breadcrumb on the SD card. Kept separate from mkxpz_log.txt.
#define BOOT_LOG_FILE "sdmc:/mkxpz_boot.log"

extern "C" {
int switch_trace_enabled = 0;
}

// Raw open/write/close: safe before libc constructors have run.
static void boot_log(const char *msg) {
    int fd = open(BOOT_LOG_FILE, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        write(fd, msg, strlen(msg));
        close(fd);
    }
}

// Open one log candidate and report the result to the boot log, so a silent
// logging failure (seen on hardware: sdmc:/mkxpz_log.txt would not open)
// can never again hide what main() did.
static int open_log_fd(const char *path, int flags) {
    int fd = open(path, flags, 0666);
    char msg[192];
    if (fd >= 0)
        snprintf(msg, sizeof(msg), "logging: stdout -> %s ok\n", path);
    else
        snprintf(msg, sizeof(msg), "logging: open %s FAILED (errno=%d)\n",
                 path, errno);
    boot_log(msg);
    return fd;
}

// Helper to redirect stdout/stderr to a file on the SD card
void setup_file_logging() {
    // O_TRUNC clears the file every time you launch the app.
    // Preferred location is the SD root log; on hardware the open of the
    // pre-existing (emulator-created) file failed, so fall back to the
    // switch folder, then to appending to the boot log itself.
    int fd = open_log_fd("sdmc:/mkxpz_log.txt", O_WRONLY | O_CREAT | O_TRUNC);
    if (fd < 0)
        fd = open_log_fd("sdmc:/switch/mkxpz_log.txt",
                         O_WRONLY | O_CREAT | O_TRUNC);
    if (fd < 0)
        fd = open_log_fd(BOOT_LOG_FILE, O_WRONLY | O_CREAT | O_APPEND);

    if (fd >= 0) {
        // Redirect stdout (1) and stderr (2) to the file descriptor
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        
        // Close the original file descriptor (dup2 kept a copy)
        close(fd);

        // CRITICAL: Disable buffering. 
        // If the app crashes, buffered text won't be written to the file.
        // With _IONBF, every printf is written immediately.
        setvbuf(stdout, NULL, _IONBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);

        struct stat st;
        switch_trace_enabled = stat(DEBUG_FLAG_FILE, &st) == 0;
        printf("--- MKXP-Z Switch Log Start ---%s\n",
               switch_trace_enabled ? " (debug tracing on)" : "");
    }
}

static bool socketsReady = false;

extern "C" {

// This hook is called by libnx before main()
void userAppInit(void) {
    // Start a fresh boot log for this launch.
    int fd = open(BOOT_LOG_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        const char *msg = "userAppInit: start\n";
        write(fd, msg, strlen(msg));
        close(fd);
    }

    // 1. Initialize ROMFS (read-only filesystem inside the NRO)
    Result rc = romfsInit();
    boot_log(R_SUCCEEDED(rc) ? "userAppInit: romfsInit ok\n"
                             : "userAppInit: romfsInit FAILED\n");

    // 2. Logging to sdmc:/mkxpz_log.txt is set up by main() via
    //    switch_enable_logging(), after the game picker: the picker draws
    //    on the libnx console, which needs stdout.

    // 3. Networking is deliberately DISABLED here. Starting the BSD socket
    //    service in userAppInit() crashes on real hardware with
    //    2168-0002 (0x4A8), before main() or any logging runs. The Ruby
    //    socket extension is still linked; without this service, socket
    //    operations simply fail with errors instead of taking down the app.
    // socketsReady = R_SUCCEEDED(socketInitializeDefault());

    boot_log("userAppInit: done (networking disabled)\n");
}

// This hook is called after main() returns
void userAppExit(void) {
    if (socketsReady)
        socketExit();
    romfsExit();
}

} // extern "C"

// Breadcrumb hook for src/main.cpp (picker and early startup stages).
extern "C" void switch_boot_mark(const char *msg) {
    boot_log(msg);
}

// Stub so src/main.cpp's call links correctly
extern "C" void switch_enable_logging() {
    setup_file_logging();
}

#endif // __SWITCH__
