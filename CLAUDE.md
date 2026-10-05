# OBISLaser — Agent Instructions

MATLAB package `obis` to control a **Coherent OBIS laser** over its serial (USB virtual COM or
OBIS Remote) port with SCPI commands. It must work **standalone** (scripts and GUI) and be **easily
embedded in any MATLAB package doing closed-loop hardware control**, Bpod protocols included
(first user: `LuminoseHF`, `C:\Users\harrislab\MATLAB\LuminoseHF`).

`agent.md` points here.

## Start here (fresh session)

1. Read this file first.
2. Then read the docs in this order:
   - `docs/architecture.md`: decisions D1–D8 and the milestones
   - `docs/scpi.md`: everything known about the laser's command set
   - `docs/api-reference.md`
   - `docs/gui.md`
   - `docs/rig-checks.md`
3. Check **Status** below. What is left needs the laser, so ask for permission for each specific
   run (see *Hardware*), and write the results into `docs/rig-checks.md`.
4. Keep **Status** and the docs current as work lands (see *Docs rule*).

## Status

| Milestone | State |
|---|---|
| M1: `Laser`, `Mode`, `Calibration`, transports, simulated laser, tests | **Done** (2026-10-05). Moved out of `LuminoseHF` (`laser/LaserModel.m`, the setpoint interpolation of `laser/irradianceToSetpoint_mW.m`) |
| M2: GUI (`obis.app`) | **Done** on the simulated laser (2026-10-05); no human pass yet |
| M3: examples, integration guide, README | **Done** |
| M4: `LuminoseHF` uses the package | Pending |
| M5: rig verification | Pending (`docs/rig-checks.md`) |

The suite has 71 tests, all passing headless on R2025b in about 5 s, and the Code Analyzer reports
zero messages.

The command set has not yet been checked on the laser. The old lab code sent only
`SOURce:AM:INTernal CWP`, `SOURce:AM:EXTernal DIGital`, `SOURce:AM:STATe ON|OFF`,
`SOURce:POWer:LEVel:IMMediate:AMPLitude` and `SOURce:POWer:LEVel?`, and it never read the `OK`
replies. Everything else in `docs/scpi.md` is marked *verify*.

## Environment

| Thing | Path / value |
|---|---|
| Project (edit here, from WSL) | `/mnt/c/Users/harrislab/MATLAB/OBISLaser` |
| Same path from Windows | `C:\Users\harrislab\MATLAB\OBISLaser` |
| MATLAB | R2025b (`/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe`), base MATLAB only |
| Laser on Windows | `COM15` at 115200 baud on this rig (`LuminoseHF/luminose_config.yaml`, `laser:`) |
| Vendor software | Coherent Connection 6 (`C:\Program Files (x86)\Coherent`): holds the port while open |
| Bpod reference (read-only) | `../Bpod_Gen2` |
| Sibling packages (idioms, read-only) | `../DoricLED`, `../SpinCam`, `../DMDController`, `../LuminoseFM` |

Agents run in WSL; MATLAB and the laser are on Windows.

```bash
# headless MATLAB from WSL: the whole suite (no hardware, about 30 s including startup)
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "cd('C:\Users\harrislab\MATLAB\OBISLaser\tests'); r = run_tests; exit(any([r.Failed]))"

# one class only
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "cd('C:\Users\harrislab\MATLAB\OBISLaser\tests'); run_tests('Filter', 'GuiTest')"
```

If that fails with `Exec format error`, WSL's Windows interop is not registered. Re-registering it
needs sudo in a real terminal, so ask the operator to run
`sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'`.

The saved MATLAB path on this rig prints *Name is nonexistent* warnings for folders that have
moved. They are harmless, and the path is the operator's to fix.

## Rules

### Workspace boundary
- **Create, edit or delete files only inside this project folder.** Reading elsewhere is fine.
  Never modify the MATLAB path or startup files, Bpod settings, or other repositories. If
  something outside must change, tell the operator exactly what and where.
- Resolve paths from the package location (`mfilename('fullpath')`). Never hard-code the absolute
  paths above in code.

### Git
- **The operator handles git manually.** Do not run any git command unless the operator asks in
  that message, and do not create `.gitignore` or other git files unless asked.

### Hardware
- **Never touch the real laser without the operator's explicit permission for that specific run.**
  That covers `connect` on a SerialTransport, `obis.listDevices('Probe', true)`, the GUI on a real
  port, and `tests/hardware/`. Someone may be in the beam path or an animal may be under the
  objective. Permission covers that request only.
- The tests and the examples on `SimulatedTransport` need no permission.
- Before a permitted run:
  - confirm Coherent Connection is closed and no other MATLAB holds the port
  - start with emission off and the beam blocked
  - always end with emission off and the port closed
- Record every hardware run in `docs/rig-checks.md` (date, what ran, results). Things that need a
  person at the rig (a power meter, watching the beam, a TTL source) go in its *Pending* list.
- Never assume a mode, setpoint or emission state this process did not send or read back.

### Scope
- **No protocol-specific code:** nothing tied to an experiment. Irradiance at a particular sample,
  DMD field areas and soft-code numbers belong to the client (`LuminoseHF/+lhf/+laser`).
- **The user has full control:**
  - Every mode and readback is in the API and the GUI, and `query`/`command` reach anything else.
  - Never choose a mode for the user, and never clamp silently: limits are set by the user, and a
    refusal is an explicit error.
  - The exceptions are hardware facts, not preferences:
    - `MaxPowermW` cannot exceed the laser's own `LIMit:HIGH`.
    - `command()` refuses power commands, so that the limit cannot be bypassed.

## Architecture in brief

- `obis.Laser` is a synchronous request/reply driver. Each command is one line, and the call
  waits for `OK` (or `ERR-<code>`, which raises `obis:Laser:deviceError`) because handshaking is
  turned on at connect (D1).
- Transports only move lines (D2):
  - `SerialTransport`: MATLAB `serialport`
  - `SimulatedTransport`: the laser's answers and state, plus fault injection
- `obis.Mode` maps each mode to its command and its `AM:SOURce?` reply.
- `obis.Calibration` is a pure value class that interpolates setpoint and power both ways and
  refuses extrapolation (D7).
- `obis.gui.LaserApp` is a programmatic uifigure (D8). It owns a laser, or attaches to one
  without ever disconnecting it.

## Conventions

- **Layout:**
  - `+obis/`: `Laser`, `Mode`, `Calibration`, `app`, `config`, `listDevices`, `version`
  - `+obis/+transport/`: `Transport`, `SerialTransport`, `SimulatedTransport`
  - `+obis/+gui/LaserApp.m`
  - `examples/`, `tests/` (`run_tests.m`, test classes, `hardware/`), `docs/`
- **Help text** follows LuminoseFM's `docs/code-style.md`, and `HelpTextTest` checks it:
  - every file starts with an H1 line giving its full name (`obis.Laser ...`) as one sentence
    ending in a full stop, then a blank help line
  - every file outside `tests/` has a `See also` line (no colon)
  - lines are at most 100 characters, and comments are ASCII only
- **Style:**
  - 4-space indent
  - `camelCase` locals and methods, `PascalCase` classes and properties
  - no variables named after builtins (`path`, `axis`, `all`)
  - comments explain *why*
- **Units in names:** `PowermW`, `TimeoutS`, `WavelengthNm`, `BaseplateC`. The API is in mW; the
  laser speaks W, and only `Laser` converts.
- **Errors:** `error('obis:<Component>:<reason>', ...)` with a message that says what to do.
  `delete` and `stopAll` never throw.
- **Portability of the core:** no `global`, `evalin`, `assignin`, `cd`, figures or `drawnow`
  outside `+gui`. Base MATLAB only. Nothing is printed unless `Verbose` is set.
- **Lint:** zero Code Analyzer messages. A suppression carries its reason.
- **Traps:**
  - The OBIS answers **every** command with `OK` while handshaking is on. Code that writes without
    reading (as `LuminoseHF`'s old `LaserModel` did) leaves those lines queued, so the next
    query reads a stale `OK` and would return NaN. Every exchange must read to its `OK`.
  - `Laser` is not re-entrant (`IsBusy`, `obis:Laser:busy`). A timer or GUI readback that fires
    between a write and its reply would steal the reply. For that reason the GUI's auto refresh
    starts off when it attaches to someone else's laser.
  - Killing MATLAB leaves the laser emitting as it was. There is no helper process to notice,
    unlike DoricLED's bridge.

## Tests

- `matlab.unittest` class-based tests in `tests/`, run with `tests/run_tests.m` headless. No test
  may touch hardware.
- The current suite has 71 tests:
  - `LaserTest` (30)
  - `CalibrationTest` (8)
  - `SimulatedTransportTest` (9)
  - `GuiTest` (11)
  - `ExamplesTest` (3)
  - `ModeTest` (2)
  - `HelpTextTest` (5)
  - `SerialTransportTest` (3, against a port that does not exist)
- New behaviour needs a test in the matching class.
- `tests/hardware/checkLaser.m` is the rig check script. It is run only with permission, and its
  results go in `docs/rig-checks.md`.

## Docs rule

- `README.md` is **end-user only**. No developer notes, milestones or agent rules.
- `docs/` holds the technical material: `architecture.md`, `scpi.md`, `api-reference.md`,
  `gui.md`, `bpod-integration.md`, `rig-checks.md`.
- A change to a public signature, a decision or the milestone status updates the matching doc
  (and **Status** above) in the same piece of work.
- Anything learned about the laser goes in `docs/scpi.md`, replacing a *verify* mark with the
  fact and the date.
