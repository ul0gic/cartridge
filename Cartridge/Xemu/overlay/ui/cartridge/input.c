/* Changed by ul0gic for Cartridge on 2026-11-01. */
#include "qemu/osdep.h"
#include "ui/xemu-input.h"

#include "cartridge-host.h"

void cartridge_input_init(void)
{
    ControllerState *con = g_new0(ControllerState, 1);
    con->type = INPUT_DEVICE_CARTRIDGE_HOST;
    con->name = "Cartridge";
    con->bound = -1;
    con->peripheral_types[0] = PERIPHERAL_NONE;
    con->peripheral_types[1] = PERIPHERAL_NONE;

    bound_drivers[0] = DRIVER_S;
    xemu_input_bind(0, con, 0);
    QTAILQ_INSERT_TAIL(&available_controllers, con, entry);

    cartridge_host_log(CARTRIDGE_XEMU_LOG_INFO, "pad bound port=1 driver=%s",
                       DRIVER_S);
}

void xemu_input_update_cartridge_controller_state(ControllerState *state)
{
    static const struct {
        uint16_t pad;
        uint16_t controller;
    } binary[] = {
        { CARTRIDGE_XEMU_PAD_DPAD_UP, CONTROLLER_BUTTON_DPAD_UP },
        { CARTRIDGE_XEMU_PAD_DPAD_DOWN, CONTROLLER_BUTTON_DPAD_DOWN },
        { CARTRIDGE_XEMU_PAD_DPAD_LEFT, CONTROLLER_BUTTON_DPAD_LEFT },
        { CARTRIDGE_XEMU_PAD_DPAD_RIGHT, CONTROLLER_BUTTON_DPAD_RIGHT },
        { CARTRIDGE_XEMU_PAD_START, CONTROLLER_BUTTON_START },
        { CARTRIDGE_XEMU_PAD_BACK, CONTROLLER_BUTTON_BACK },
        { CARTRIDGE_XEMU_PAD_LEFT_THUMB, CONTROLLER_BUTTON_LSTICK },
        { CARTRIDGE_XEMU_PAD_RIGHT_THUMB, CONTROLLER_BUTTON_RSTICK },
    };

    CartridgeXemuPad pad = { 0 };
    cartridge_host_read_pad(&pad);

    uint16_t buttons = 0;
    for (size_t i = 0; i < ARRAY_SIZE(binary); i++) {
        if (pad.buttons & binary[i].pad) {
            buttons |= binary[i].controller;
        }
    }
    buttons |= pad.a ? CONTROLLER_BUTTON_A : 0;
    buttons |= pad.b ? CONTROLLER_BUTTON_B : 0;
    buttons |= pad.x ? CONTROLLER_BUTTON_X : 0;
    buttons |= pad.y ? CONTROLLER_BUTTON_Y : 0;
    buttons |= pad.black ? CONTROLLER_BUTTON_BLACK : 0;
    buttons |= pad.white ? CONTROLLER_BUTTON_WHITE : 0;
    state->buttons = buttons;

    // hw/xbox/xid.c:98-99 shift trigger axes right by 7 to get 0-255.
    state->axis[CONTROLLER_AXIS_LTRIG] = (int16_t)(pad.left_trigger << 7);
    state->axis[CONTROLLER_AXIS_RTRIG] = (int16_t)(pad.right_trigger << 7);
    state->axis[CONTROLLER_AXIS_LSTICK_X] = pad.left_x;
    state->axis[CONTROLLER_AXIS_LSTICK_Y] = pad.left_y;
    state->axis[CONTROLLER_AXIS_RSTICK_X] = pad.right_x;
    state->axis[CONTROLLER_AXIS_RSTICK_Y] = pad.right_y;
}
