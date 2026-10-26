
#ifdef __SWITCH__

// Avoid pulling in Ruby's assert.h from libnx service.h:
// we don't need Ruby APIs in this TU, and ruby/config.h
// is not available in our cross-build include layout.
#define RUBY_ASSERT_H 1

#include <switch.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

// Verbose SWITCH_TRACE output (src/util/switch-trace.h), on when this exists
#define DEBUG_FLAG_FILE "sdmc:/switch/mkxp-z/debug.txt"

extern "C" {
int switch_trace_enabled = 0;
}

// Helper to redirect stdout/stderr to a file on the SD card
void setup_file_logging() {
    // Open a file on the SD card root
    // O_TRUNC clears the file every time you launch the app
    int fd = open("sdmc:/mkxpz_log.txt", O_WRONLY | O_CREAT | O_TRUNC, 0666);
    
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

extern "C" {

// This hook is called by libnx before main()
void userAppInit(void) {
    // 1. Initialize ROMFS (read-only filesystem inside the NRO)
    romfsInit();

    // 2. Logging to sdmc:/mkxpz_log.txt is set up by main() via
    //    switch_enable_logging(), after the game picker: the picker draws
    //    on the libnx console, which needs stdout.

    // 3. Network Sockets - DISABLED to prevent crash
    // socketInitializeDefault(); 
    // nxlinkStdio();
}

// This hook is called after main() returns
void userAppExit(void) {
    // socketExit(); // Disabled
    romfsExit();
}

} // extern "C"

// Stub so src/main.cpp's call links correctly
extern "C" void switch_enable_logging() {
    setup_file_logging();
}

#endif // __SWITCH__
