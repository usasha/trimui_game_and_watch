// Minimal SDL2 present benchmark for the TrimUI Brick "mali" video driver.
// Build with the TrimUI SDK SDL2 headers, run on the device with
// LD_LIBRARY_PATH=/usr/trimui/lib and SDL_VIDEODRIVER=mali.
// Measures effective present rate of a solid-color window, with and
// without an EGL/renderer path (SDL_RenderPresent).
#include <SDL2/SDL.h>
#include <stdio.h>

static void bench_window(SDL_Window *win, int frames)
{
    SDL_Surface *surf = SDL_GetWindowSurface(win);
    if (!surf) { printf("GetWindowSurface failed: %s\n", SDL_GetError()); return; }
    Uint32 t0 = SDL_GetTicks();
    for (int i = 0; i < frames; i++) {
        SDL_FillRect(surf, NULL, (i & 1) ? 0x00ff0000 : 0x000000ff);
        SDL_UpdateWindowSurface(win);
    }
    Uint32 t1 = SDL_GetTicks();
    printf("window-surface: %d frames in %u ms = %.1f fps\n", frames, t1 - t0,
           1000.0f * frames / (t1 - t0));
}

static void bench_renderer(SDL_Window *win, int frames, int accel)
{
    Uint32 flags = accel ? SDL_RENDERER_ACCELERATED : SDL_RENDERER_SOFTWARE;
    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, flags);
    if (!ren) { printf("CreateRenderer(%s) failed: %s\n", accel ? "accel" : "soft", SDL_GetError()); return; }
    SDL_Texture *tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGBA32,
                                         SDL_TEXTUREACCESS_STREAMING, 1671, 1080);
    if (!tex) { printf("CreateTexture failed: %s\n", SDL_GetError()); SDL_DestroyRenderer(ren); return; }
    static Uint32 px[1671 * 1080];
    memset(px, 0x80, sizeof(px));
    Uint32 t0 = SDL_GetTicks();
    for (int i = 0; i < frames; i++) {
        SDL_UpdateTexture(tex, NULL, px, 1671 * 4);
        SDL_RenderCopy(ren, tex, NULL, NULL);
        SDL_RenderPresent(ren);
    }
    Uint32 t1 = SDL_GetTicks();
    printf("renderer(%s) + 1671x1080 texture: %d frames in %u ms = %.1f fps\n",
           accel ? "accel" : "soft", frames, t1 - t0, 1000.0f * frames / (t1 - t0));
    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
}

int main(int argc, char **argv)
{
    int w = argc > 1 ? atoi(argv[1]) : 640;
    int h = argc > 2 ? atoi(argv[2]) : 480;
    int frames = argc > 3 ? atoi(argv[3]) : 120;
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }
    SDL_Window *win = SDL_CreateWindow("present-test", 0, 0, w, h,
                                       SDL_WINDOW_SHOWN);
    if (!win) {
        printf("CreateWindow failed: %s\n", SDL_GetError());
        return 1;
    }
    printf("video driver: %s\n", SDL_GetCurrentVideoDriver());
    bench_window(win, frames);
    SDL_DestroyWindow(win);
    win = SDL_CreateWindow("present-test-renderer", 0, 0, w, h, SDL_WINDOW_SHOWN);
    bench_renderer(win, frames, 0);
    SDL_DestroyWindow(win);
    win = SDL_CreateWindow("present-test-accel", 0, 0, w, h, SDL_WINDOW_SHOWN);
    bench_renderer(win, frames, 1);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
