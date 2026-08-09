// Live joystick dumper for the TrimUI Brick.
// Prints raw SDL joystick state: axes, hat, buttons - on every change.
// Build with SDK SDL2 headers, run with LD_LIBRARY_PATH=/usr/trimui/lib.
#include <SDL2/SDL.h>
#include <stdio.h>
#include <unistd.h>

int main(void)
{
    if (SDL_Init(SDL_INIT_JOYSTICK) < 0) {
        printf("SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    printf("joysticks: %d\n", SDL_NumJoysticks());
    if (SDL_NumJoysticks() < 1) return 1;
    SDL_Joystick *joy = SDL_JoystickOpen(0);
    if (!joy) { printf("open failed: %s\n", SDL_GetError()); return 1; }
    int nax = SDL_JoystickNumAxes(joy);
    int nbt = SDL_JoystickNumButtons(joy);
    int nht = SDL_JoystickNumHats(joy);
    printf("name: %s axes=%d buttons=%d hats=%d\n",
           SDL_JoystickName(joy), nax, nbt, nht);

    static int ax[32], bt[64], ht[8];
    for (int i = 0; i < 32; i++) ax[i] = 0x7fffffff;
    for (int i = 0; i < 64; i++) bt[i] = -1;
    for (int i = 0; i < 8; i++) ht[i] = -1;

    printf("READY: press buttons and D-pad...\n");
    fflush(stdout);
    for (int loop = 0; loop < 20000; loop++) {
        SDL_PumpEvents();
        for (int a = 0; a < nax && a < 32; a++) {
            int v = SDL_JoystickGetAxis(joy, a);
            if (v != ax[a]) {
                ax[a] = v;
                printf("AXIS %d = %d\n", a, v);
                fflush(stdout);
            }
        }
        for (int h = 0; h < nht && h < 8; h++) {
            int v = SDL_JoystickGetHat(joy, h);
            if (v != ht[h]) {
                ht[h] = v;
                printf("HAT %d = %d (%s%s%s%s)\n", h, v,
                       (v & SDL_HAT_UP) ? "UP" : "",
                       (v & SDL_HAT_DOWN) ? "DOWN" : "",
                       (v & SDL_HAT_LEFT) ? "LEFT" : "",
                       (v & SDL_HAT_RIGHT) ? "RIGHT" : "");
                fflush(stdout);
            }
        }
        for (int b = 0; b < nbt && b < 64; b++) {
            int v = SDL_JoystickGetButton(joy, b);
            if (v != bt[b]) {
                bt[b] = v;
                printf("BUTTON %d = %d\n", b, v);
                fflush(stdout);
            }
        }
        SDL_Delay(30);
    }
    SDL_JoystickClose(joy);
    SDL_Quit();
    return 0;
}
