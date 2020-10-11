# GLFW Gamepad functions
# https://www.glfw.org/docs/latest/input_guide.html#gamepad

const AXIS_LEFT_X       = 1
const AXIS_LEFT_Y       = 2
const AXIS_RIGHT_X      = 3
const AXIS_RIGHT_Y      = 4

const BUTTON_DPAD_UP    = 12
const BUTTON_DPAD_RIGHT = 13
const BUTTON_DPAD_DOWN  = 14
const BUTTON_DPAD_LEFT  = 15

struct GLFWgamepadstate
	buttons::SVector{15, UInt8}  # unsigned char buttons[15];    // GLFW_PRESS or GLFW_RELEASE
	axes::SVector{6, Float32}    # float axes[6];                // -1.0 to 1.0 inclusive
end

#= GetGamepadState
This function retrieves the state of the specified joystick remapped to an Xbox-like gamepad.
If the specified joystick is not present or does not have a gamepad mapping this function will return GLFW_FALSE but will not generate an error. Call glfwJoystickPresent to check whether it is present regardless of whether it has a mapping.
Not all devices have all the buttons or axes provided by GLFWgamepadstate. Unavailable buttons and axes will always report GLFW_RELEASE and 0.0 respectively.
Possible errors include GLFW_NOT_INITIALIZED and GLFW_INVALID_ENUM.
Added in version 3.3 (MWB !!! How can we make sure the user is using GLFW 3.3?)
=#

GetGamepadState(joy::GLFW.Joystick, state) = Bool(ccall((:glfwGetGamepadState, GLFW.libglfw), Cint, (Cint, Ref{GLFWgamepadstate}), joy, state))

# Functions ported over from JoystickInterface.py
function deadband(value, band_radius)
    return max(value - band_radius, 0) + min(value + band_radius, 0)
end

function clipped_first_order_filter(input, target, max_rate, tau)
    rate = (target - input) / tau
    return clamp(rate, -max_rate, max_rate)
end

function handle_scalar_settings(s::mjSim, buttons, axes)
    config  = s.robot.controller.config
    state   = s.robot.state
    command = s.robot.command

    # Velocity
    command.horizontal_velocity[1] = axes[AXIS_LEFT_Y] * -config.max_x_velocity
    command.horizontal_velocity[2] = axes[AXIS_LEFT_X] * -config.max_y_velocity

    # Yaw
    command.yaw_rate = axes[AXIS_RIGHT_X] * -config.max_yaw_rate

    # Pitch
    pitch = axes[AXIS_RIGHT_Y] * -config.max_pitch
    #println("pitch: $pitch")
    deadbanded_pitch = deadband(pitch, config.pitch_deadband)
    pitch_rate = clipped_first_order_filter(
        state.pitch,
        deadbanded_pitch,
        config.max_pitch_rate,
        config.pitch_time_constant
    )
    #println("pitch_rate: $pitch_rate")
    message_dt = 1.0 / s.refreshrate
    command.pitch = state.pitch + message_dt * pitch_rate
    #println("Setting command.pitch to $(command.pitch)")

    # Roll
    dpadx = Int(buttons[BUTTON_DPAD_RIGHT]) - Int(buttons[BUTTON_DPAD_LEFT])
    if dpadx != 0
        roll = state.roll + message_dt * config.roll_speed * dpadx
        command.roll = clamp(roll, -1.0, 1.0)
    end

    # Height
    dpady = Int(buttons[BUTTON_DPAD_UP]) - Int(buttons[BUTTON_DPAD_DOWN])
    if dpady != 0
        height = state.height - message_dt * config.z_speed * dpady
        command.height = clamp(height, -0.25, -0.025)
    end
end

prev_buttons = @SVector fill(0x00, 15)
button_commands = SVector{15, RobotCmd}(
    CYCLE_HOP,          # GLFW_GAMEPAD_BUTTON_CROSS
    NO_COMMAND, NO_COMMAND, NO_COMMAND,
    TOGGLE_ACTIVATION,  # GLFW_GAMEPAD_BUTTON_LEFT_BUMPER
    TOGGLE_TROT,        # GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER
    NO_COMMAND, NO_COMMAND, NO_COMMAND, NO_COMMAND,
    NO_COMMAND, NO_COMMAND, NO_COMMAND, NO_COMMAND, NO_COMMAND)

function handle_behavior_state_change(s::mjSim, buttons)
    triggered = buttons .& (prev_buttons .⊻ buttons)
    global prev_buttons = deepcopy(buttons)

    for (doit, robotcmd) in zip(triggered, button_commands)
        if Bool(doit)
            # println("Executing Robot Command: $(repr(robotcmd))")
            execute_robotcmd(s, robotcmd)
        end
    end
end

function gamepad(s::mjSim, joy::GLFW.Joystick)
    state = Ref{GLFWgamepadstate}()

    if GetGamepadState(joy, state)
        buttons = state[].buttons

        handle_behavior_state_change(s, buttons)
        handle_scalar_settings(s, buttons, state[].axes)
    end
end
