#include <switch.h>
#include <stdio.h>
#include <stdarg.h>

static FILE* gLog = NULL;

static void log_printf(const char* fmt, ...) {
    va_list args;

    // To stdout (console / nxlink, if it ever works)
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);

    // To file on sdmc:/
    if (gLog) {
        va_start(args, fmt);
        vfprintf(gLog, fmt, args);
        va_end(args);
        fflush(gLog);
    }

    fflush(stdout);
}

static void log_buttons_down(u64 kDown) {
    if (!kDown)
        return;

    log_printf("ButtonsDown: ");
    if (kDown & HidNpadButton_A)        log_printf("A ");
    if (kDown & HidNpadButton_B)        log_printf("B ");
    if (kDown & HidNpadButton_X)        log_printf("X ");
    if (kDown & HidNpadButton_Y)        log_printf("Y ");

    if (kDown & HidNpadButton_L)        log_printf("L ");
    if (kDown & HidNpadButton_R)        log_printf("R ");
    if (kDown & HidNpadButton_ZL)       log_printf("ZL ");
    if (kDown & HidNpadButton_ZR)       log_printf("ZR ");

    if (kDown & HidNpadButton_StickL)   log_printf("LStick ");
    if (kDown & HidNpadButton_StickR)   log_printf("RStick ");

    if (kDown & HidNpadButton_Plus)     log_printf("Plus ");
    if (kDown & HidNpadButton_Minus)    log_printf("Minus ");

    if (kDown & HidNpadButton_Up)       log_printf("DpadUp ");
    if (kDown & HidNpadButton_Down)     log_printf("DpadDown ");
    if (kDown & HidNpadButton_Left)     log_printf("DpadLeft ");
    if (kDown & HidNpadButton_Right)    log_printf("DpadRight ");

    log_printf("(mask=0x%016lx)\n", kDown);
}

int main(int argc, char* argv[]) {
    // Mount SD card so sdmc:/ works in both emulator and hardware
    Result fsRc = fsdevMountSdmc();
    // We won't early-exit on failure; just log it.
    consoleInit(NULL);

        if (R_SUCCEEDED(fsRc)) {
        gLog = fopen("sdmc:/hello_log.txt", "w");
        if (gLog)
            setvbuf(gLog, NULL, _IONBF, 0);
        log_printf("fs: Mounted sdmc and opened hello_log.txt\n");
    } else {
        printf("fs: fsdevMountSdmc failed: 0x%x\n", fsRc);
    }

    PadState pad;
    padConfigureInput(1, HidNpadStyleSet_NpadStandard);
    padInitializeDefault(&pad);

    log_printf("Hello, Nintendo Switch!\n");
    log_printf("Logging to sdmc:/hello_log.txt\n");
    log_printf("Press buttons; their names will be logged.\n");
    log_printf("Press + to exit.\n\n");

    while (appletMainLoop()) {
        padUpdate(&pad);

        u64 kDown = padGetButtonsDown(&pad);
        if (kDown) {
            log_buttons_down(kDown);
        }

        if (kDown & HidNpadButton_Plus)
            break;

        consoleUpdate(NULL);
    }

    consoleExit(NULL);

    if (gLog) {
        fclose(gLog);
        gLog = NULL;
    }

    fsdevUnmountAll();
    return 0;
}