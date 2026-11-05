/* Changed by ul0gic for Cartridge on 2026-11-01. */
#ifndef GLOFFSCREEN_CGL_H_
#define GLOFFSCREEN_CGL_H_

// OpenGL is deprecated on macOS but is the only renderer xemu builds there.
#define GL_SILENCE_DEPRECATION

#include <OpenGL/OpenGL.h>

CGLContextObj glo_cgl_create_shared(CGLContextObj share);

#endif
