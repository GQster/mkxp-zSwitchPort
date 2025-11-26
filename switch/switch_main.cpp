#include <switch.h>
#include "main.h"

int main(int argc, char* argv[]) {
    socketInitializeDefault();
    nxlinkStdio();
    romfsInit();
    hidInitialize();

    Engine::run(argc, argv);

    hidExit();
    romfsExit();
    socketExit();
    return 0;
}