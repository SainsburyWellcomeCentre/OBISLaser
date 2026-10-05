# Architecture

How the `obis` package is built and why. The API is in [`api-reference.md`](api-reference.md), and
the laser's command set is in [`scpi.md`](scpi.md).

## 1. Goals and non-goals

**Goals**
- Full control of a Coherent OBIS laser from MATLAB: every modulation mode, the setpoint,
  emission, readback of what the laser reports, and raw SCPI for anything else.
- Usable standalone (scripts, the control window) and embedded in a closed-loop host such as a
  Bpod protocol, where the power is set from a soft-code callback between trials.
- Safe by default: a known state on connect, emission off on every exit path the software
  controls, and a power limit the user sets and the code enforces by refusing.
- Testable without hardware: a simulated laser behind the same interface.

**Non-goals**
- Anything experiment-specific. Irradiance at a particular sample, DMD field areas, soft-code
  numbers and trial queues belong to the client (`LuminoseHF`'s `+lhf/+laser`).
- Measuring light. The package reports what the laser accepted and what the laser's own
  photodiode reads; a power meter is the user's.
- Several lasers behind one object. Make one `obis.Laser` per laser; nothing here shares state.

## 2. Decisions

### D1. Synchronous request/reply, handshaking on

Each command is one line, and the call returns when the laser has answered `OK`, or raises when it
answers `ERR-<code>` or nothing within `TimeoutS`. `connect` sends
`SYST:COMM:HAND ON` first (the short form: the rig's OBIS Remote refuses the long one), so every command gets that answer whatever the laser was
left in.

*Why.*
- The OBIS answers in milliseconds over USB serial, so a call that waits costs little and tells
  the caller that the laser accepted the command.
- The code this replaces wrote without reading. With handshaking on, the unread `OK` lines pile
  up, and a later query reads one of them instead of its value: `getPower_mW` would have
  returned NaN. Nothing called it, so the fault never showed.
- An asynchronous design like DoricLED's bridge is needed only when the vendor library blocks or
  prints asynchronously. A serial port does neither.

### D2. Layered package; the transport is injectable

`obis.Laser` speaks SCPI. A `obis.transport.Transport` only moves lines: open, write a line, read
a line with a timeout, flush, close. There are two transports:
- `SerialTransport` wraps MATLAB's `serialport`.
- `SimulatedTransport` answers like the laser, keeps the state those commands change, and
  injects faults.

Tests, examples, demos and a Bpod emulator session run the same `Laser` code as the rig.

### D3. Commanded state plus the laser's own readback

The object's properties (`Mode`, `CommandedPowermW`, `IsEnabled`) are what the laser last
accepted, or what was read back at connect. `status()`, `powermW()` and `setpointmW()` ask the
laser now. Nothing claims to know the light.

### D4. Safety limits are user-owned, explicit and cannot be bypassed

- `MaxPowermW` defaults to the laser's own `LIMit:HIGH`. The user lowers it, and can never raise
  it above that.
- `setPower` above it is refused with `obis:Laser:aboveLimit`. The power is never reduced
  silently.
- Lowering the limit below the current setpoint is refused (`limitBelowCommanded`), so the limit
  is never already exceeded.
- `command()`, the raw passthrough, refuses power commands, so it cannot get round the limit.

Everything else (mode, emission, raw queries) stays the user's choice.

### D5. Known state on connect; emission off on every software exit

- `connect` turns emission off. It reads the mode and setpoint back and does not change them, so
  connecting never changes how the laser behaves once enabled.
- `disconnect`, `delete`, closing a window that owns the laser, and `stopAll` turn emission off.
- `stopAll` is tried in every state, even Faulted, and never throws, so cleanup paths can call it
  unconditionally.

Nothing can cover MATLAB being killed (README, *Safety*).

### D6. One command at a time

`Laser` is not re-entrant. `IsBusy` is set while a command waits, and a second command in that
window raises `obis:Laser:busy` rather than stealing the first one's reply. The GUI's readback
timer checks `IsBusy` and skips its turn. When the GUI attaches to someone else's laser, auto
refresh starts off, because a Bpod soft-code callback can fire at any time.

### D7. Calibration is a pure value class

`obis.Calibration` holds a measured setpoint/power table and interpolates linearly in both
directions:
- Rows with no measured power are dropped, because below the lasing threshold they say nothing.
- The table must rise monotonically.
- Values outside it are refused, never extrapolated.
- `scaled(k)` turns power into any proportional quantity (irradiance, power at another plane).
  The geometry that defines `k` stays with the client.

### D8. The GUI is a programmatic uifigure

The window is built in code, as in DoricLED and SpinCam, so it can be read, reviewed and tested
headless (`'Visible', false`). Mode and Power are pending until their Set button. Emission and
EMISSION OFF act at once, and Esc is EMISSION OFF. A window that owns its laser disconnects it on
close; an attached one never does.

## 3. Class overview

| Class / function | Role |
|---|---|
| `obis.Laser` | Connection, commands, limits, log, record |
| `obis.Mode` | Enumeration: CWP, CWC, Digital, Analog, Mixed, each with its command and reply |
| `obis.Calibration` | Setpoint/power table, interpolation both ways |
| `obis.transport.Transport` | Abstract line transport |
| `obis.transport.SerialTransport` | `serialport`, CR/LF, 115200 baud |
| `obis.transport.SimulatedTransport` | The laser without hardware, with fault injection |
| `obis.gui.LaserApp`, `obis.app` | Control window |
| `obis.config`, `obis.version`, `obis.listDevices` | Defaults (`setpref('obis', ...)`), version, port listing |

## 4. Connection states

```
Disconnected --connect()--> Ready --disconnect()--> Disconnected
                              |
                              +--no answer within TimeoutS--> Faulted --disconnect()--> Disconnected
```

- A failed `connect` closes the port and stays Disconnected, or goes to Faulted after a timeout.
- A refused command (`ERR-<code>`) leaves the object Ready: the laser answered, so its state is
  known.
- A timeout makes it Faulted: what the laser did with the command is unknown, so only `stopAll`
  and `disconnect` are allowed until the user reconnects.

## 5. Error handling

Every error identifier is `obis:<Component>:<reason>`, and the full list is in each class's help.
Every entry in `log()` holds the command, the reply (or the error message), whether it succeeded
and its latency. `record()` copies the log with wall-clock times so it can be saved with data.

## 6. Portability rules for the core

`+obis` and `+obis/+transport` use no `global`, `evalin`, `assignin`, `cd`, figures or `drawnow`,
and print only when `Verbose` is set. They need base MATLAB only. `+obis/+gui` is the only place
for figures and timers.

## 7. Repository layout

```
+obis/                Laser, Mode, Calibration, app, config, listDevices, version
+obis/+transport/     Transport, SerialTransport, SimulatedTransport
+obis/+gui/           LaserApp
examples/             example_basic, example_bpod_softcode, example_calibration
tests/                run_tests and test classes; hardware/ (manual, with permission)
docs/                 this file, scpi, api-reference, gui, bpod-integration, rig-checks
```

## 8. Milestones

| Version | Date | What |
|---|---|---|
| 0.1.0 | 2026-10-05 | M1–M3: package, simulated laser, GUI, examples, docs, 71 tests. Moved out of `LuminoseHF` (`LaserModel`, the setpoint interpolation) |

Next:
- **M4:** `LuminoseHF` uses `obis.Laser` and `obis.Calibration`.
- **M5:** rig verification (`rig-checks.md`).
