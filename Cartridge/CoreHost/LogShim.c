#include "CoreHostC.h"

#include <dispatch/dispatch.h>
#include <os/log.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static cartridge_log_sink_t log_sink;

void cartridge_set_log_sink(cartridge_log_sink_t sink)
{
    log_sink = sink;
}

static const char *level_name(enum retro_log_level level)
{
    switch (level) {
    case RETRO_LOG_DEBUG: return "debug";
    case RETRO_LOG_INFO: return "info";
    case RETRO_LOG_WARN: return "warn";
    case RETRO_LOG_ERROR: return "error";
    default: return "unknown";
    }
}

static os_log_type_t level_type(enum retro_log_level level)
{
    switch (level) {
    case RETRO_LOG_DEBUG: return OS_LOG_TYPE_DEBUG;
    case RETRO_LOG_INFO: return OS_LOG_TYPE_INFO;
    case RETRO_LOG_ERROR: return OS_LOG_TYPE_ERROR;
    default: return OS_LOG_TYPE_DEFAULT;
    }
}

void cartridge_log_callback(enum retro_log_level level, const char *fmt, ...)
{
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("io.corelift.Cartridge", "core");
    });

    char buffer[4096];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof buffer, fmt, args);
    va_end(args);

    size_t length = strlen(buffer);
    while (length > 0 && (buffer[length - 1] == '\n' || buffer[length - 1] == '\r')) {
        buffer[--length] = '\0';
    }

    os_log_with_type(log, level_type(level), "[%{public}s] %{public}s", level_name(level), buffer);
    if (log_sink != NULL) {
        log_sink(level, buffer);
    }
}

void cartridge_fill_log_callback(struct retro_log_callback *callback)
{
    callback->log = cartridge_log_callback;
}
