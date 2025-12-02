#ifdef __SWITCH__
#include <switch.h>
#include <stdio.h>
#include <unistd.h>

extern "C" {
    void userAppInit(void);
    void userAppExit(void);
}

void userAppInit(void) { romfsInit(); socketInitializeDefault(); }
void userAppExit(void) { socketExit(); romfsExit(); }
#endif
