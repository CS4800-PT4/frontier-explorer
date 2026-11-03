# Known issues (sim-sev / live demo)

## Offboard bridge: do not start Explorer before `o` (offboard)

**Symptom:** With the offboard bridge running (`hardware.launch.py` / `jetson-runner/04_run_stack.sh`), after takeoff (`t`) if you start `frontier_explorer` / `explorer_node` *before* selecting offboard mode (`o`), the explorer (or the bridge session) crashes.

**Correct order:**
1. Start the stack (bridge up, explorer off).
2. Takeoff / arm (`t`), wait for a stable hover.
3. Select offboard (`o`) so the vehicle is ready to follow goals.
4. *Then* start the Explorer program (`explorer_node`).
5. Hover freeze (`p`) / land (`l`) / disarm (`d`) as needed.

**Do not:** run Explorer between takeoff and `o`.

**Scripts:** `sim-sev/live-demo/run_demo.sh` and `sim-sev/jetson-runner/06_run_demo.sh` enforce this order (offboard before Explorer). Manual demos must follow the same sequence.

**Noted:** 2026-11-02 (Fedora copy at `/home/sev/frontier-explorer`; also applies on Ubuntu / Jetson live runs).
