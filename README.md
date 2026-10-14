# OBISLaser

MATLAB control of a **Coherent OBIS laser** (developed for an OBIS LS/LX at 165 mW) over its
USB or OBIS Remote serial port: a scriptable driver, a control window, a calibration helper and a
simulated laser for testing. It is built to run standalone or inside Bpod protocols and other
closed-loop experiments.

> **Status: not yet run against the laser (2026-10-05).** Everything has been tested on the
> simulated laser (71 tests). The commands are the ones the previous lab code sent to this
> laser, plus the reads and limits added here. They have not yet been checked against the real
> device. Run the first session with the beam blocked, and follow
> [docs/rig-checks.md](docs/rig-checks.md).

## Features

- **Every modulation mode:** CWP, CWC, Digital, Analog and Mixed, plus power, emission, readback
  of setpoint, output, temperature and status, and raw SCPI for anything else.
- **Every command confirmed:** each command waits for the laser's `OK`, and a refusal raises an
  error that carries the laser's own code.
- **Safe by default:** emission is turned off when you connect, disconnect, delete the object or
  close the window. Power above your own limit is refused, never reduced.
- **A control panel:** laid out like Coherent Connection's: **Start**, **Stop** (Esc does the
  same), Operating power in mW (typed, stepped with arrows or dragged) and Operating mode. It
  opens as a window of its own or inside another program's window.
- **Coherent's own DLL:** the port is opened through Coherent Connection's
  `CoherentConnectionLibrary.dll` when it is installed, else through MATLAB's `serialport`.
- **Calibration:** convert between setpoint and power measured at the sample, in either
  direction. Values outside the measured table are refused.
- **A simulated laser:** code that uses the laser can be developed and tested without hardware.
- **A session record:** what was sent and what the laser answered, as a plain struct, can be saved
  with your data.

## Requirements

- Windows 10/11, 64-bit
- MATLAB R2025b (the only release tested), base MATLAB only: `serialport` is built in
- Optional: Coherent Connection 6 installed (its DLL is then used to open the port; close the
  program itself before connecting). With the DLL somewhere else, point to its folder once:
  **Details > DLL folder** in the control panel, or `setpref('obis', 'DllFolder', folder)`
- A Coherent OBIS laser connected by USB (it appears as a COM port) or through an OBIS Remote
- No other program holding the port (close Coherent Connection)

## Installation

1. Place this folder anywhere, e.g. `C:\Users\<you>\MATLAB\OBISLaser`.
2. Add the folder (not its subfolders) to the MATLAB path:
   ```matlab
   addpath('C:\Users\<you>\MATLAB\OBISLaser'); savepath
   ```
3. Optionally, store your laser's port so you never have to type it:
   ```matlab
   obis.listDevices()                  % ports Windows sees; IsObis marks the laser's
                                       % ('Probe', true) also asks each *IDN?
   setpref('obis', 'Port', 'COM15')
   ```
4. Check the installation without touching the hardware:
   ```matlab
   cd(fullfile(fileparts(which('obis.version')), 'tests')); run_tests
   ```

## Quick start

```matlab
laser = obis.Laser('Port', 'COM15');   % nothing is sent yet
laser.connect();                        % reads identity and limits; emission off

laser.MaxPowermW = 50;                  % refuse anything above 50 mW from now on
laser.setMode('CWP');                   % constant power, internal
laser.setPower(10);                     % mW
laser.setEnabled(true);                 % light
laser.powermW()                         % what the laser measures
laser.setEnabled(false);

laser.setMode('Digital');               % a TTL on the modulation input gates the light
laser.setPower(20);
laser.setEnabled(true);                 % emits only while the TTL is high

laser.disconnect();                     % emission off, port closed
```

Converting a power wanted at the sample into the setpoint that gives it:

```matlab
cal = obis.Calibration.fromCsv('power_calibration.csv');   % setpoint vs measured power
laser.setPower(cal.setpointFor(2.5));                       % 2.5 mW at the sample
```

There are longer walk-throughs in [`examples/`](examples):
- `example_basic.m`: every command
- `example_bpod_softcode.m`: a power per trial, set from a soft code
- `example_calibration.m`

They run on the simulated laser as they are; set `useHardware = true` to drive the real one.

## Control window

```matlab
obis.app()                      % opens the window; it owns its own laser connection
obis.app(laser)                 % controls a laser you already connected (left connected on close)
obis.app(laser, 'Parent', tab)  % the same panel inside your own window (a tab, panel or grid)
```

**Start**, **Stop** (or Esc), the power and the mode act at once. Tick **Pulse** to have Start
switch emission on and off at a frequency and duty cycle (software timing, a few ms of jitter;
at most 25 Hz). Give the window a calibration, `obis.app(laser, 'Calibration', cal)`, and it
also shows the power at the sample for the setpoint. With two lasers, open one
window per laser and name it by wavelength, `obis.app('ExpectedWavelengthNm', 488)`: Connect finds
that laser's port (`obis.findPort`) and refuses any other. See [docs/gui.md](docs/gui.md).

## Testing without hardware

```matlab
laser = obis.Laser('Transport', obis.transport.SimulatedTransport());
```

The simulated laser answers the way the real one does and records every line it receives
(`laser.Transport.Calls`). It can also be told to refuse a command (`failNext`), to stay silent
(`hangNext`) or to lose its cable (`unplug`), so you can test your error handling.

## Using it in a Bpod protocol

1. Connect once during protocol setup, in Digital mode, so the state machine's TTL gates the
   light.
2. Set each trial's power from a soft code before the trial's first TTL.
3. Save `laser.record()` with the session.
4. Disconnect in your cleanup.

See [docs/bpod-integration.md](docs/bpod-integration.md).

## Safety

The OBIS is a Class 3B or 4 laser, depending on the model. This package does not replace
interlocks, beam blocks or eyewear.

- **Your limit:**
  - `MaxPowermW` starts at the laser's own maximum (`SOURce:POWer:LIMit:HIGH?`). Set it to what
    your preparation tolerates.
  - It cannot be raised above the laser's maximum.
  - Requests above it are refused, never reduced.
  - Raw commands (`command`) cannot set power, so the limit always applies.
- **Emission off:** emission is turned off on `connect`, `disconnect`, deleting the object,
  closing a window that owns the laser, and `stopAll()`, which works in every state.
- **What the software cannot cover:**
  - If MATLAB is killed or crashes, nothing turns emission off. The laser keeps its last state.
    In Digital mode it still emits whenever the TTL is high.
  - In Analog mode the output follows the voltage on the input up to the laser's maximum, and
    `MaxPowermW` does not apply to that voltage.
  - The package reports what the laser says. It does not see the light itself.

## Documentation

Technical documentation is in [`docs/`](docs):
- `architecture.md`: the design decisions
- `api-reference.md`
- `scpi.md`: the laser's command set
- `gui.md`
- `bpod-integration.md`
- `rig-checks.md`: what has and has not been checked on the hardware
