import evdev
from evdev import ecodes, UInput
import subprocess
import time
import threading
import sys
import os

# --- CONFIGURATION ---
# Triggers (Workspace Switch)
CODE_LEFT_TRIGGER = 10   
CODE_RIGHT_TRIGGER = 9   
TRIGGER_THRESHOLD = 200

# Thumbstick (Mouse Move)
CODE_MOUSE_X = 2         
CODE_MOUSE_Y = 5         
MOUSE_SPEED = 15.0       
DEADZONE = 0.10          

# Buttons
CODE_STICK_CLICK = 318   # Right Stick Click -> Left Mouse Click
CODE_TOGGLE_MODE = 315   # Start Button -> Toggle Game Mode
CODE_SUPER_KEY   = 314   # Select/Back Button -> Super Key (Windows Key)

# D-Pad (Scrolling)
CODE_DPAD_X = 16         
CODE_DPAD_Y = 17         
SCROLL_DELAY = 0.1       

# Identification
REQUIRED_AXES = {ecodes.ABS_GAS, ecodes.ABS_BRAKE}
# ---------------------

state = {
    "dx": 0.0,
    "dy": 0.0,
    "scroll_y": 0,
    "scroll_x": 0,
    "running": True,
    "paused": False
}

def notify(message, urgency="normal"):
    """Sends a desktop notification"""
    try:
        subprocess.run([
            "notify-send", "-a", "Gamepad Control", "-u", urgency, "-t", "3000",
            "Controller Status", message
        ])
    except:
        pass

def switch_workspace(direction):
    if state["paused"]: return
    cmd = "m-1" if direction == "left" else "m+1"
    subprocess.run(["hyprctl", "dispatch", "workspace", cmd], stdout=subprocess.DEVNULL)

def find_controller():
    try:
        paths = evdev.list_devices()
        for path in paths:
            try:
                dev = evdev.InputDevice(path)
                caps = dev.capabilities()
                if ecodes.EV_ABS in caps:
                    codes = {c[0] for c in caps[ecodes.EV_ABS]}
                    if REQUIRED_AXES.issubset(codes):
                        return dev
            except:
                continue
    except:
        pass
    return None

def normalize_axis(value, abs_info):
    min_v = abs_info.min
    max_v = abs_info.max
    if max_v == min_v: return 0.0
    center = (max_v + min_v) / 2
    span = (max_v - min_v) / 2
    norm = (value - center) / span
    if abs(norm) < DEADZONE: return 0.0
    return norm

def update_thread(ui):
    last_scroll_time = 0
    while state["running"]:
        if state["paused"]:
            time.sleep(0.5)
            continue

        current_time = time.time()
        
        # Mouse Move
        if state["dx"] != 0 or state["dy"] != 0:
            try:
                ui.write(ecodes.EV_REL, ecodes.REL_X, int(state["dx"] * MOUSE_SPEED))
                ui.write(ecodes.EV_REL, ecodes.REL_Y, int(state["dy"] * MOUSE_SPEED))
                ui.syn()
            except OSError:
                break 

        # Scroll
        if state["scroll_y"] != 0 or state["scroll_x"] != 0:
            if current_time - last_scroll_time > SCROLL_DELAY:
                try:
                    if state["scroll_y"] != 0:
                        ui.write(ecodes.EV_REL, ecodes.REL_WHEEL, state["scroll_y"])
                    if state["scroll_x"] != 0:
                        ui.write(ecodes.EV_REL, ecodes.REL_HWHEEL, state["scroll_x"])
                    ui.syn()
                    last_scroll_time = current_time
                except OSError:
                    break
        time.sleep(0.016)

def main():
    print("Daemon started. Waiting for controller...")
    first_connect = True 

    while True:
        device = find_controller()
        if device is None:
            time.sleep(1)
            continue
        
        print(f"Connected: {device.name}")
        if not first_connect:
            notify(f"Connected to {device.name}")
        first_connect = False 

        try:
            # Capability Map: We now declare KEY_LEFTMETA (Super)
            cap = {
                ecodes.EV_REL: (ecodes.REL_X, ecodes.REL_Y, ecodes.REL_WHEEL, ecodes.REL_HWHEEL),
                ecodes.EV_KEY: (ecodes.BTN_LEFT, ecodes.BTN_RIGHT, ecodes.KEY_LEFTMETA) 
            }
            ui = UInput(cap, name="Gamepad-Virtual-Mouse")
        except PermissionError:
            print("ERROR: Permission denied for /dev/uinput.")
            sys.exit(1)

        try:
            abs_x = device.absinfo(CODE_MOUSE_X)
            abs_y = device.absinfo(CODE_MOUSE_Y)
        except:
            abs_x = None

        state["running"] = True
        state["dx"] = 0.0
        state["dy"] = 0.0
        state["scroll_y"] = 0
        state["scroll_x"] = 0
        state["paused"] = False
        
        t = threading.Thread(target=update_thread, args=(ui,), daemon=True)
        t.start()

        left_trig_active = False
        right_trig_active = False
        toggle_btn_active = False

        try:
            for event in device.read_loop():
                
                # --- BUTTONS (Start/Select/Click) ---
                if event.type == ecodes.EV_KEY:
                    
                    # 1. Toggle Mode (Start Button)
                    if event.code == CODE_TOGGLE_MODE:
                        if event.value == 1 and not toggle_btn_active: 
                            state["paused"] = not state["paused"]
                            status = "GAME MODE (Paused)" if state["paused"] else "DESKTOP MODE (Active)"
                            print(f"[{status}]")
                            notify(status)
                            state["dx"] = 0; state["dy"] = 0; state["scroll_x"] = 0; state["scroll_y"] = 0
                            toggle_btn_active = True
                        elif event.value == 0:
                            toggle_btn_active = False
                        continue
                    
                    # If Paused, ignore other buttons
                    if state["paused"]: continue

                    # 2. Mouse Click (Stick Click)
                    if event.code == CODE_STICK_CLICK:
                        ui.write(ecodes.EV_KEY, ecodes.BTN_LEFT, event.value)
                        ui.syn()
                    
                    # 3. Super Key (Select/Back Button)
                    elif event.code == CODE_SUPER_KEY:
                        ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTMETA, event.value)
                        ui.syn()

                # --- AXES (Movement/Scroll) ---
                elif event.type == ecodes.EV_ABS and not state["paused"]:
                    
                    if event.code == CODE_MOUSE_X and abs_x:
                        state["dx"] = normalize_axis(event.value, abs_x)
                    elif event.code == CODE_MOUSE_Y and abs_y:
                        state["dy"] = normalize_axis(event.value, abs_y)
                    
                    elif event.code == CODE_LEFT_TRIGGER:
                        if event.value > TRIGGER_THRESHOLD and not left_trig_active:
                            switch_workspace("left")
                            left_trig_active = True
                        elif event.value < TRIGGER_THRESHOLD:
                            left_trig_active = False
                    elif event.code == CODE_RIGHT_TRIGGER:
                        if event.value > TRIGGER_THRESHOLD and not right_trig_active:
                            switch_workspace("right")
                            right_trig_active = True
                        elif event.value < TRIGGER_THRESHOLD:
                            right_trig_active = False

                    elif event.code == CODE_DPAD_Y:
                        state["scroll_y"] = -event.value 
                    elif event.code == CODE_DPAD_X:
                        state["scroll_x"] = event.value

        except OSError:
            print("Device disconnected.")
            notify("Controller Disconnected", "critical")
            state["running"] = False
            ui.close()
            t.join()

if __name__ == "__main__":
    main()
