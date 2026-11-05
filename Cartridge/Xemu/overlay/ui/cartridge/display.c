/* Changed by ul0gic for Cartridge on 2026-11-01. */
#include "qemu/osdep.h"
#include "block/aio.h"
#include "qapi/error.h"
#include "qapi/qapi-commands-block.h"
#include "qemu/main-loop.h"
#include "qemu/rcu.h"
#include "qemu/thread.h"
#include "system/runstate.h"
#include "system/system.h"
#include "ui/console.h"
#include "ui/xemu-settings.h"
#include "ui/xui/xemu-hud.h"
#include "hw/xbox/smbus.h"
#include "hw/xbox/nv2a/nv2a.h"

#include <epoxy/gl.h>
#include <SDL3/SDL.h>

#include "hw/xbox/nv2a/pgraph/thirdparty/gloffscreen/cgl.h"
#include "cartridge-host.h"

// ui/xemu.c:78
static const int64_t vblank_interval_ns = 16666666LL;

struct cartridge_console {
    DisplayChangeListener dcl;
    DisplaySurface *surface;
};

static struct cartridge_console scon;
static QemuSemaphore display_init_sem;
static QemuSemaphore display_shutdown_sem;
static QemuSemaphore display_wake;
static QemuSemaphore start_done;
static QemuThread display_thread;
static QemuThread vblank_thread;
static QemuThread qemu_main_thread;
static bool qemu_exiting;
static bool stop_requested;
static int vblank_pending;
static int exit_status;
static CartridgeXemuStatus start_status;
static int main_argc;
static char **main_argv;

static QemuMutex task_lock;
static CartridgeDisplayTask task_fn;
static void *task_opaque;
static QemuSemaphore task_done;
static bool display_done;

static CGLContextObj window_ctx;

static struct {
    GLuint prog;
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLint flipy_loc;
    GLint scale_offset_loc;
    GLint tex_scale_offset_loc;
    GLint tex_loc;
    GLint palette_loc;
    GLuint fbo[2];
    GLuint target[2];
    uint32_t width[2];
    uint32_t height[2];
    uint32_t next;
} blit;

void tcg_register_init_ctx(void);

void xemu_main_loop_lock(void)
{
    qemu_mutex_lock_main_loop();
    bql_lock();
}

void xemu_main_loop_unlock(void)
{
    bql_unlock();
    qemu_mutex_unlock_main_loop();
}

SDL_Window *xemu_get_window(void)
{
    return NULL;
}

void xemu_toggle_fullscreen(void)
{
}

int xemu_is_fullscreen(void)
{
    return 0;
}

static GLuint compile_shader(GLenum type, const char *src)
{
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        return 0;
    }
    glShaderSource(shader, 1, &src, NULL);
    glCompileShader(shader);

    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE) {
        char err_buf[512];
        glGetShaderInfoLog(shader, sizeof(err_buf), NULL, err_buf);
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR,
                           "display shader compilation failed: %s", err_buf);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static bool blit_init_program(void)
{
    const char *vert_src =
        "#version 150 core\n"
        "uniform bool in_FlipY;\n"
        "uniform vec4 in_ScaleOffset;\n"
        "uniform vec4 in_TexScaleOffset;\n"
        "in vec2 in_Position;\n"
        "in vec2 in_Texcoord;\n"
        "out vec2 Texcoord;\n"
        "void main() {\n"
        "    vec2 t = in_Texcoord;\n"
        "    if (in_FlipY) t.y = 1-t.y;\n"
        "    Texcoord = t*in_TexScaleOffset.xy + in_TexScaleOffset.zw;\n"
        "    gl_Position = vec4(in_Position*in_ScaleOffset.xy+in_ScaleOffset.zw, 0.0, 1.0);\n"
        "}\n";
    // Alpha is forced opaque: xemu presents into an opaque window.
    const char *frag_src =
        "#version 400 core\n"
        "uniform sampler2D tex;\n"
        "uniform uint palette[256];\n"
        "float gamma_ch(int ch, float col)\n"
        "{\n"
        "    return float(bitfieldExtract(palette[uint(col * 255.0)], ch*8, 8)) / 255.0;\n"
        "}\n"
        "vec4 gamma(vec4 col)\n"
        "{\n"
        "    return vec4(gamma_ch(0, col.r), gamma_ch(1, col.g), gamma_ch(2, col.b), col.a);\n"
        "}\n"
        "in  vec2 Texcoord;\n"
        "out vec4 out_Color;\n"
        "void main() {\n"
        "    out_Color = vec4(gamma(texture(tex, Texcoord)).rgb, 1.0);\n"
        "}\n";

    GLuint vert = compile_shader(GL_VERTEX_SHADER, vert_src);
    GLuint frag = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    if (vert == 0 || frag == 0) {
        return false;
    }

    blit.prog = glCreateProgram();
    glAttachShader(blit.prog, vert);
    glAttachShader(blit.prog, frag);
    glBindFragDataLocation(blit.prog, 0, "out_Color");
    glLinkProgram(blit.prog);
    glDeleteShader(vert);
    glDeleteShader(frag);

    GLint linked;
    glGetProgramiv(blit.prog, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR,
                           "display program link failed");
        return false;
    }
    glUseProgram(blit.prog);

    blit.flipy_loc = glGetUniformLocation(blit.prog, "in_FlipY");
    blit.scale_offset_loc = glGetUniformLocation(blit.prog, "in_ScaleOffset");
    blit.tex_scale_offset_loc =
        glGetUniformLocation(blit.prog, "in_TexScaleOffset");
    blit.tex_loc = glGetUniformLocation(blit.prog, "tex");
    blit.palette_loc = glGetUniformLocation(blit.prog, "palette");

    const GLfloat verts[4][4] = {
        { -1.0f, -1.0f,  0.0f,  0.0f },
        { -1.0f,  1.0f,  0.0f,  1.0f },
        {  1.0f,  1.0f,  1.0f,  1.0f },
        {  1.0f, -1.0f,  1.0f,  0.0f },
    };
    const GLint indices[] = { 0, 1, 2, 3 };

    glGenVertexArrays(1, &blit.vao);
    glBindVertexArray(blit.vao);

    glGenBuffers(1, &blit.vbo);
    glBindBuffer(GL_ARRAY_BUFFER, blit.vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_COPY);

    glGenBuffers(1, &blit.ebo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, blit.ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices,
                 GL_STATIC_DRAW);

    GLint loc = glGetAttribLocation(blit.prog, "in_Position");
    if (loc >= 0) {
        glVertexAttribPointer(loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
                              (void *)0);
        glEnableVertexAttribArray(loc);
    }
    loc = glGetAttribLocation(blit.prog, "in_Texcoord");
    if (loc >= 0) {
        glVertexAttribPointer(loc, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
                              (void *)(2 * sizeof(GLfloat)));
        glEnableVertexAttribArray(loc);
    }
    return true;
}

static bool blit_init_targets(void)
{
    glGenTextures(2, blit.target);
    glGenFramebuffers(2, blit.fbo);
    for (uint32_t i = 0; i < 2; i++) {
        IOSurfaceRef surface = cartridge_host_surface(i);
        blit.width[i] = (uint32_t)IOSurfaceGetWidth(surface);
        blit.height[i] = (uint32_t)IOSurfaceGetHeight(surface);

        glBindTexture(GL_TEXTURE_RECTANGLE, blit.target[i]);
        CGLError err = CGLTexImageIOSurface2D(
            window_ctx, GL_TEXTURE_RECTANGLE, GL_RGBA, (GLsizei)blit.width[i],
            (GLsizei)blit.height[i], GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV,
            surface, 0);
        if (err != kCGLNoError) {
            cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR,
                               "CGLTexImageIOSurface2D surface=%u failed: %s",
                               i, CGLErrorString(err));
            return false;
        }

        glBindFramebuffer(GL_FRAMEBUFFER, blit.fbo[i]);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_RECTANGLE, blit.target[i], 0);
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        if (status != GL_FRAMEBUFFER_COMPLETE) {
            cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR,
                               "surface=%u framebuffer incomplete 0x%x", i,
                               status);
            return false;
        }
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_RECTANGLE, 0);
    return true;
}

static void blit_finalize(void)
{
    glDeleteFramebuffers(2, blit.fbo);
    glDeleteTextures(2, blit.target);
    glDeleteBuffers(1, &blit.ebo);
    glDeleteBuffers(1, &blit.vbo);
    glDeleteVertexArrays(1, &blit.vao);
    glDeleteProgram(blit.prog);
}

static void xb_surface_gl_create_texture(DisplaySurface *surface)
{
    assert(QEMU_IS_ALIGNED(surface_stride(surface),
                           surface_bytes_per_pixel(surface)));

    switch (surface_format(surface)) {
    case PIXMAN_BE_b8g8r8x8:
    case PIXMAN_BE_b8g8r8a8:
        surface->glformat = GL_BGRA_EXT;
        surface->gltype = GL_UNSIGNED_BYTE;
        break;
    case PIXMAN_BE_x8r8g8b8:
    case PIXMAN_BE_a8r8g8b8:
        surface->glformat = GL_RGBA;
        surface->gltype = GL_UNSIGNED_BYTE;
        break;
    case PIXMAN_r5g6b5:
        surface->glformat = GL_RGB;
        surface->gltype = GL_UNSIGNED_SHORT_5_6_5;
        break;
    default:
        g_assert_not_reached();
    }

    if (!surface->texture) {
        glGenTextures(1, &surface->texture);
    }
    glBindTexture(GL_TEXTURE_2D, surface->texture);
    glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT,
                  surface_stride(surface) / surface_bytes_per_pixel(surface));
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB,
                 surface_width(surface),
                 surface_height(surface),
                 0, surface->glformat, surface->gltype,
                 surface_data(surface));
    glPixelStorei(GL_UNPACK_ROW_LENGTH_EXT, 0);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
}

static void copy_to_surface(GLuint tex, bool flip_y, uint32_t index,
                            uint32_t *out_width, uint32_t *out_height)
{
    GLint tw, th;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &tw);
    glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &th);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

    uint32_t width = (uint32_t)tw;
    uint32_t height = (uint32_t)th;
    if (width > blit.width[index] || height > blit.height[index]) {
        double scale = MIN((double)blit.width[index] / width,
                           (double)blit.height[index] / height);
        width = (uint32_t)(width * scale);
        height = (uint32_t)(height * scale);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, blit.fbo[index]);
    glViewport(0, 0, (GLsizei)width, (GLsizei)height);
    glUseProgram(blit.prog);
    glBindVertexArray(blit.vao);
    glUniform1i(blit.flipy_loc, flip_y);
    glUniform4f(blit.scale_offset_loc, 1.0, 1.0, 0, 0);
    glUniform4f(blit.tex_scale_offset_loc, 1.0, 1.0, 0, 0);
    glUniform1i(blit.tex_loc, 0);

    const uint8_t *palette = nv2a_get_dac_palette();
    GLuint entries[256];
    for (int i = 0; i < 256; i++) {
        entries[i] = (palette[i * 3 + 2] << 16) | (palette[i * 3 + 1] << 8) |
                     palette[i * 3];
    }
    glUniform1uiv(blit.palette_loc, 256, entries);

    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    if (!nv2a_get_screen_off()) {
        glDrawElements(GL_TRIANGLE_FAN, 4, GL_UNSIGNED_INT, NULL);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    *out_width = width;
    *out_height = height;
}

static void render_frame(void)
{
    bool flip_required = false;
    bool release_surface_texture = false;

    GLuint tex = nv2a_get_framebuffer_surface();
    if (tex == 0) {
        xemu_main_loop_lock();
        xb_surface_gl_create_texture(scon.surface);
        tex = scon.surface->texture;
        scon.surface->texture = 0;
        flip_required = true;
        release_surface_texture = true;
        xemu_main_loop_unlock();
    }

    // GL's first row is the bottom of the image; an IOSurface's is the top.
    uint32_t index = blit.next;
    uint32_t width, height;
    copy_to_surface(tex, !flip_required, index, &width, &height);
    glFinish();

    if (release_surface_texture) {
        glDeleteTextures(1, &tex);
    }
    nv2a_release_framebuffer_surface();

    cartridge_host_frame_ready(index, width, height);
    blit.next = index ^ 1;
}

static void gl_switch(DisplayChangeListener *dcl, DisplaySurface *new_surface)
{
    struct cartridge_console *con = container_of(dcl, struct cartridge_console,
                                                 dcl);
    con->surface = new_surface;
}

static bool gl_check_format(DisplayChangeListener *dcl,
                            pixman_format_code_t format)
{
    switch (format) {
    case PIXMAN_BE_b8g8r8x8:
    case PIXMAN_BE_b8g8r8a8:
    case PIXMAN_r5g6b5:
        return true;
    default:
        return false;
    }
}

static const DisplayChangeListenerOps dcl_ops = {
    .dpy_name             = "cartridge-gl",
    .dpy_gfx_switch       = gl_switch,
    .dpy_gfx_check_format = gl_check_format,
};

static void process_vblank(struct cartridge_console *con)
{
    assert(bql_locked());
    graphic_hw_update(con->dcl.con);
}

static void *vblank_timer_thread(void *opaque)
{
    struct cartridge_console *con = opaque;
    int64_t next_vblank = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);

    while (!qatomic_read(&qemu_exiting)) {
        next_vblank += vblank_interval_ns;

        int64_t now = qemu_clock_get_ns(QEMU_CLOCK_REALTIME);
        if (now < next_vblank) {
            SDL_DelayPrecise(next_vblank - now);
        } else if (now > next_vblank + vblank_interval_ns) {
            next_vblank = now;
        }

        if (!qatomic_read(&qemu_exiting)) {
            xemu_main_loop_lock();
            process_vblank(con);
            xemu_main_loop_unlock();
            qatomic_set(&vblank_pending, 1);
            qemu_sem_post(&display_wake);
        }
    }

    return NULL;
}

static void display_early_init(DisplayOptions *o)
{
    assert(o->type == DISPLAY_TYPE_XEMU);
    display_opengl = 1;
}

static void display_init(DisplayState *ds, DisplayOptions *o)
{
    assert(o->type == DISPLAY_TYPE_XEMU);

    QemuConsole *con = qemu_console_lookup_by_index(0);
    assert(con != NULL);
    scon.dcl.ops = &dcl_ops;
    scon.dcl.con = con;
    register_displaychangelistener(&scon.dcl);

    qemu_thread_create(&vblank_thread, "vblank-timer", vblank_timer_thread,
                       &scon, QEMU_THREAD_JOINABLE);

    qemu_sem_post(&display_init_sem);
}

static QemuDisplay qemu_display_cartridge = {
    .type       = DISPLAY_TYPE_XEMU,
    .early_init = display_early_init,
    .init       = display_init,
};

static void register_cartridge_display(void)
{
    qemu_display_register(&qemu_display_cartridge);
}

type_init(register_cartridge_display);

static void *qemu_main(void *opaque)
{
    qemu_init(main_argc, main_argv);
    exit_status = qemu_main_loop();
    if (!qatomic_read(&stop_requested)) {
        cartridge_host_guest_stopped();
    }
    qatomic_set(&qemu_exiting, true);
    qemu_sem_post(&display_wake);
    bql_unlock();
    qemu_mutex_unlock_main_loop();

    qemu_sem_wait(&display_shutdown_sem);
    bql_lock();
    qemu_cleanup(exit_status);
    bql_unlock();

    return NULL;
}

static void run_pending_task(void)
{
    qemu_mutex_lock(&task_lock);
    CartridgeDisplayTask fn = task_fn;
    void *opaque = task_opaque;
    task_fn = NULL;
    task_opaque = NULL;
    qemu_mutex_unlock(&task_lock);

    if (fn) {
        fn(opaque);
        qemu_sem_post(&task_done);
    }
}

static bool display_gl_init(void)
{
    window_ctx = glo_cgl_create_shared(NULL);
    if (window_ctx == NULL) {
        return false;
    }
    CGLSetCurrentContext(window_ctx);

    if (epoxy_gl_version() < 40) {
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR,
                           "OpenGL 4.0 is not available (%d)",
                           epoxy_gl_version());
        return false;
    }

    cartridge_host_log(CARTRIDGE_XEMU_LOG_INFO, "GL_VENDOR: %s",
                       glGetString(GL_VENDOR));
    cartridge_host_log(CARTRIDGE_XEMU_LOG_INFO, "GL_RENDERER: %s",
                       glGetString(GL_RENDERER));
    cartridge_host_log(CARTRIDGE_XEMU_LOG_INFO, "GL_VERSION: %s",
                       glGetString(GL_VERSION));

    nv2a_context_init();

    CGLSetCurrentContext(window_ctx);
    return blit_init_program() && blit_init_targets();
}

static void *display_thread_main(void *opaque)
{
    rcu_register_thread();

    if (!display_gl_init()) {
        CGLSetCurrentContext(NULL);
        if (window_ctx != NULL) {
            CGLDestroyContext(window_ctx);
        }
        start_status = CARTRIDGE_XEMU_GL_FAILED;
        qemu_sem_post(&start_done);
        rcu_unregister_thread();
        return NULL;
    }
    CGLSetCurrentContext(NULL);

    qemu_thread_create(&qemu_main_thread, "qemu_main", qemu_main, NULL,
                       QEMU_THREAD_JOINABLE);
    qemu_sem_wait(&display_init_sem);

    tcg_register_init_ctx();
    qemu_set_current_aio_context(qemu_get_aio_context());

    xemu_main_loop_lock();
    cartridge_input_init();
    xemu_main_loop_unlock();

    CGLSetCurrentContext(window_ctx);
    start_status = CARTRIDGE_XEMU_OK;
    qemu_sem_post(&start_done);

    while (true) {
        qemu_sem_wait(&display_wake);
        run_pending_task();
        if (qatomic_read(&qemu_exiting)) {
            break;
        }
        if (qatomic_xchg(&vblank_pending, 0)) {
            render_frame();
        }
    }

    qemu_mutex_lock(&task_lock);
    display_done = true;
    qemu_mutex_unlock(&task_lock);
    run_pending_task();

    qemu_sem_post(&display_shutdown_sem);
    qemu_thread_join(&qemu_main_thread);
    qemu_thread_join(&vblank_thread);

    blit_finalize();
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(window_ctx);
    rcu_unregister_thread();
    return NULL;
}

CartridgeXemuStatus cartridge_display_start(int argc, char **argv)
{
    main_argc = argc;
    main_argv = argv;

    qemu_mutex_init(&task_lock);
    qemu_sem_init(&task_done, 0);
    qemu_sem_init(&display_wake, 0);
    qemu_sem_init(&start_done, 0);
    qemu_sem_init(&display_init_sem, 0);
    qemu_sem_init(&display_shutdown_sem, 0);

    qemu_thread_create(&display_thread, "cartridge-display",
                       display_thread_main, NULL, QEMU_THREAD_JOINABLE);
    qemu_sem_wait(&start_done);

    if (start_status != CARTRIDGE_XEMU_OK) {
        qemu_thread_join(&display_thread);
    }
    return start_status;
}

bool cartridge_display_run(CartridgeDisplayTask task, void *opaque)
{
    qemu_mutex_lock(&task_lock);
    if (display_done) {
        qemu_mutex_unlock(&task_lock);
        return false;
    }
    task_fn = task;
    task_opaque = opaque;
    qemu_mutex_unlock(&task_lock);

    qemu_sem_post(&display_wake);
    qemu_sem_wait(&task_done);
    return true;
}

static void request_shutdown(void *opaque)
{
    xemu_main_loop_lock();
    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
    xemu_main_loop_unlock();
}

void cartridge_display_stop(void)
{
    qatomic_set(&stop_requested, true);
    cartridge_display_run(request_shutdown, NULL);
    qemu_thread_join(&display_thread);
}

void xemu_eject_disc(Error **errp)
{
    Error *error = NULL;

    xbox_smc_eject_button();
    xemu_settings_set_string(&g_config.sys.files.dvd_path, "");

    // Xbox software may request that the drive open, but do it now anyway
    qmp_eject("ide0-cd1", NULL, true, false, &error);
    if (error) {
        error_propagate(errp, error);
    }

    xbox_smc_update_tray_state();
}

void xemu_load_disc(const char *path, Error **errp)
{
    Error *error = NULL;

    // Ensure an eject sequence is always triggered so Xbox software reloads
    xbox_smc_eject_button();
    xemu_settings_set_string(&g_config.sys.files.dvd_path, "");

    qmp_blockdev_change_medium("ide0-cd1", NULL, path, "raw", false, false,
                               false, 0, &error);
    if (error) {
        error_propagate(errp, error);
    } else {
        xemu_settings_set_string(&g_config.sys.files.dvd_path, path);
    }

    xbox_smc_update_tray_state();
}
