/* Changed by ul0gic for Cartridge on 2026-11-01. */
/*
 *  Offscreen OpenGL abstraction layer - CGL (Apple) specific
 *
 *  Copyright (c) 2013 Wayo
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>

#include "gloffscreen.h"
#include "cgl.h"

struct _GloContext {
    CGLContextObj cglContext;
};

CGLContextObj glo_cgl_create_shared(CGLContextObj share)
{
    CGLPixelFormatAttribute attributes[] = {
        kCGLPFAAccelerated,
        kCGLPFAOpenGLProfile,
        (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFAAlphaSize, (CGLPixelFormatAttribute)8,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)24,
        kCGLPFAStencilSize, (CGLPixelFormatAttribute)8,
        (CGLPixelFormatAttribute)0
    };

    CGLPixelFormatObj pix = NULL;
    GLint num = 0;
    CGLError err = CGLChoosePixelFormat(attributes, &pix, &num);
    if (err != kCGLNoError || pix == NULL) {
        fprintf(stderr, "%s: CGLChoosePixelFormat failed: %s\n", __func__,
                CGLErrorString(err));
        return NULL;
    }

    CGLContextObj context = NULL;
    err = CGLCreateContext(pix, share, &context);
    CGLDestroyPixelFormat(pix);
    if (err != kCGLNoError) {
        fprintf(stderr, "%s: CGLCreateContext failed: %s\n", __func__,
                CGLErrorString(err));
        return NULL;
    }
    return context;
}

/* Create an OpenGL context sharing with the one current on this thread */
GloContext *glo_context_create(void)
{
    GloContext *context = (GloContext *)malloc(sizeof(GloContext));
    if (context == NULL) {
        fprintf(stderr, "%s: Out of memory\n", __func__);
        exit(1);
    }

    context->cglContext = glo_cgl_create_shared(CGLGetCurrentContext());
    if (context->cglContext == NULL) {
        fprintf(stderr, "%s: Failed to create GL context\n", __func__);
        exit(1);
    }

    glo_set_current(context);

    return context;
}

/* Set current context */
void glo_set_current(GloContext *context)
{
    if (context == NULL) {
        CGLSetCurrentContext(NULL);
    } else {
        CGLSetCurrentContext(context->cglContext);
    }
}

/* Destroy a previously created OpenGL context */
void glo_context_destroy(GloContext *context)
{
    if (!context) return;
    glo_set_current(NULL);
    CGLDestroyContext(context->cglContext);
    free(context);
}
