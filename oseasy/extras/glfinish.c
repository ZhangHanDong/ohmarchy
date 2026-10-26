// ohmarchy-glfinish.so: LD_PRELOAD for Hyprland in the Oseasy VM, where glFlush
// waits for rendering like glFinish.
//
// Hyprland calls glFinish before a commit only when it knows it renders in
// software, and it decides that from the DRM driver's name (llvmpipe, softpipe).
// On efidrm, the only KMS device here, it takes llvmpipe for a GPU, ends the
// frame with glFlush (an implicit sync point that llvmpipe does not wait on) and
// commits a frame llvmpipe is still drawing: the screen keeps whatever tiles were
// done, until the next frame. oseasy/hyprland/0001-*.patch is the fix for
// upstream; this stays until a Hyprland with it reaches the image.
#define _GNU_SOURCE
#include <dlfcn.h>

void glFlush(void) {
  static void (*finish)(void);
  if (!finish)
    finish = (void (*)(void))dlsym(RTLD_NEXT, "glFinish");
  finish();
}
