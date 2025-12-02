
#ifdef __SWITCH__

#include <switch.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

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

        printf("--- MKXP-Z Switch Log Start ---\n");
    }
}

extern "C" {

// This hook is called by libnx before main()
void userAppInit(void) {
    // 1. Initialize ROMFS (read-only filesystem inside the NRO)
    romfsInit();

    // 2. Setup logging to sdmc:/mkxpz_log.txt
    setup_file_logging();
    
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

#endif // __SWITCH__
