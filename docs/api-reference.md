# API reference

Every public class and function of the `obis` package. The help text of each file (`help
obis.Laser`) says the same, and this page collects it. The design reasons are in
[`architecture.md`](architecture.md).

## `obis.Laser` (handle)

### Construction

```matlab
laser = obis.Laser('Port', 'COM15')
laser = obis.Laser('Transport', obis.transport.SimulatedTransport())
laser = obis.Laser(..., 'MaxPowermW', 50, 'TimeoutS', 2, 'Verbose', true)
```

The constructor never touches the hardware. With no `Transport`, `connect` opens `Port` with the
`Driver`: `'coherent'` builds a `CoherentTransport` (Coherent Connection's DLL), `'serial'` a
`SerialTransport` at `BaudRate`; the DLL is looked for in `DllFolder`. All default from `obis.config` (`setpref('obis', 'Port',
...)`); `Driver` defaults to `'coherent'` when Coherent Connection 6 is installed.

### Properties

| Property | Access | Meaning |
|---|---|---|
| `State` | read | `'Disconnected'`, `'Ready'` or `'Faulted'` |
| `FaultReason` | read | why it is Faulted |
| `Transport` | read | the transport in use |
| `Identity` | read | struct `Idn`, `Model`, `SerialNumber`, `WavelengthNm` (after connect) |
| `DeviceMaxPowermW`, `DeviceMinPowermW` | read | the laser's own setpoint limits |
| `Mode` | read | `obis.Mode` read at connect or last set |
| `CommandedPowermW` | read | setpoint read at connect or last accepted |
| `IsEnabled` | read | emission state last accepted (off after connect) |
| `IsBusy` | read | a command waits for its answer |
| `ExpectedWavelengthNm` | read/write | the laser meant when there are several (`[]`: any). `connect` reads the wavelength and refuses another laser (`obis:Laser:wrongLaser`) before sending it any command; settable only while Disconnected |
| `Port`, `BaudRate`, `Driver`, `DllFolder` | read/write | settable only while Disconnected (`obis:Laser:portLocked`); `Driver` is `'coherent'` or `'serial'`; `DllFolder` is where `CoherentConnectionLibrary.dll` is, for `'coherent'` |
| `MaxPowermW` | read/write | your limit; defaults to `DeviceMaxPowermW` at connect |
| `TimeoutS` | read/write | wait for each answer (default 2) |
| `Verbose` | read/write | print each command and reply |
| `LogCapacity` | read/write | entries kept by `log()` (default 1000) |

### Methods

| Method | Does |
|---|---|
| `connect()` | open; handshake on; read identity, limits, mode and setpoint; emission off |
| `disconnect()` | emission off, close; idempotent, never throws |
| `setMode(mode)` | `obis.Mode` or a name (`'Digital'`, `'cwp'`, ...) |
| `setPower(mW)` | setpoint; refused above `MaxPowermW` or for a value that is not one finite number >= 0 |
| `setEnabled(tf)` | emission on/off |
| `ok = stopAll()` | emission off in any state; `ok` false if not confirmed; never throws |
| `mW = powermW()` | output power the laser measures |
| `mW = setpointmW()` | setpoint read back |
| `s = status()` | `IsEnabled`, `Mode`, `SetpointmW`, `OutputmW`, `BaseplateC`, `StatusCode`, `FaultCode` |
| `reply = query(line)` | any query, returns its value |
| `command(line)` | any command; power commands refused (`obis:Laser:useSetPower`) |
| `s = record()` | plain struct: package, version, identity, limits, commanded state, log with times |
| `t = log()` | table `Time` (s), `Command`, `Reply`, `Ok`, `LatencyMs` |

### Events

`StateChanged` and `CommandCompleted`. They carry no data, so listeners read the properties.

### Errors

| Identifier | When |
|---|---|
| `obis:Laser:notReady` | a command while not Ready |
| `obis:Laser:noPort` | `connect` with no Port and no Transport |
| `obis:Laser:timeout` | no answer within `TimeoutS`; the object becomes Faulted |
| `obis:Laser:deviceError` | the laser answered `ERR-<code>` (in the message) |
| `obis:Laser:aboveLimit` | `setPower` above `MaxPowermW` |
| `obis:Laser:badValue` | a power or limit that is not one finite number >= 0 |
| `obis:Laser:limitAboveDevice` | `MaxPowermW` above the laser's own limit |
| `obis:Laser:limitBelowCommanded` | `MaxPowermW` below the setpoint already commanded |
| `obis:Laser:useSetPower` | `command()` given a power command |
| `obis:Laser:busy` | a command while another waits for its answer |
| `obis:Laser:portLocked` | `Port`/`BaudRate`/`Driver`/`DllFolder`/`ExpectedWavelengthNm` changed while connected |
| `obis:Laser:wrongLaser` | the laser on the port is not `ExpectedWavelengthNm` (nothing but queries was sent) |
| `obis:Laser:invalidOption` | unknown constructor option |

## `obis.Mode` (enumeration)

`CWP`, `CWC`, `Digital`, `Analog`, `Mixed`. Each value has these properties:
- `Command`: the line that selects it
- `Reply`: what `SOURce:AM:SOURce?` answers
- `IsExternal`

`obis.Mode.fromText(text)` accepts names, replies and short forms in any case, and errors with
`obis:Mode:unknown` for anything else.

## `obis.Calibration` (value)

```matlab
cal = obis.Calibration(setpointmW, powermW)
cal = obis.Calibration.fromCsv(file, 'SetpointColumn', 'power_setting_mW', ...
                                     'PowerColumn', 'power_at_sample_mW')
```

| Member | Meaning |
|---|---|
| `SetpointmW`, `PowermW` | the table, rising, with rows of no measured power dropped |
| `Range` | `[lowest highest]` power |
| `Source` | file read, or `''` |
| `setpointFor(power)` | setpoint giving each power |
| `powerFor(setpoint)` | power at each setpoint |
| `scaled(k)` | the same table with power times `k` (e.g. irradiance) |

Errors:
- `obis:Calibration:badTable`: fewer than two usable rows, sizes that differ, or a missing column
- `obis:Calibration:notMonotonic`
- `obis:Calibration:outOfRange`: nothing is ever extrapolated

## Functions

| Function | Does |
|---|---|
| `[port, found] = obis.findPort('WavelengthNm', nm)` | the free Coherent USB port whose laser reports `nm` to `SYSTem:INFormation:WAVelength?` (within `obis.Laser.WavelengthToleranceNm`, 5 nm) (only Coherent ports that no program holds are asked); without a wavelength, the first free one and no traffic. `found`: the ports asked, their `Idn` and `WavelengthNm`. Errors `obis:findPort:notFound` naming the lasers it did find. Options `Driver`, `DllFolder`, `TimeoutS` |
| `obis.app(...)` | opens `obis.gui.LaserApp` (see [`gui.md`](gui.md)) |
| `obis.config(...)` | `RootDir`, `Port`, `BaudRate`, `Driver`, `DllFolder`, `Version`; preferences `setpref('obis', ...)`. `Driver` defaults to `'coherent'` when the DLL is in `DllFolder` |
| `obis.listDevices()` | table `Port`, `Available`, `IsObis`, `Description`, `Idn`. `IsObis` marks Coherent USB devices (vendor `0D4D`, "Coherent OBIS Device" in Device Manager), read from the Windows registry with no traffic; `('Probe', true)` also sends `*IDN?` to each free port |
| `obis.version()` | package version |

## `obis.transport.Transport` (abstract handle)

`open()`, `close()` (never throws), `isOpen()`, `writeLine(text)`, `readLine(timeoutS)` (`[]` on
timeout), `flush()`, and `Description` for records.

### `obis.transport.SerialTransport`

`SerialTransport(port, 'BaudRate', 115200)` uses MATLAB's `serialport` with a CR/LF terminator.
It errors with `obis:SerialTransport:openFailed` and `obis:SerialTransport:notOpen`.

### `obis.transport.CoherentTransport`

`CoherentTransport(port, 'DllFolder', folder)` opens the port through Coherent Connection's own
serial layer (`CoherentConnectionLibrary.dll`, `ConnectionLibrary.SerialCommunicator`, loaded with
`NET.addAssembly`; Windows only). Lines pass through unchanged, so `obis.Laser` and its limits
behave as with `SerialTransport`. `DllFolder` defaults to `defaultDllFolder()`, the Coherent
Connection 6 install folder; `isAvailable()` says whether the DLL is there. It errors with
`obis:CoherentTransport:noDll`, `obis:CoherentTransport:openFailed` and
`obis:CoherentTransport:notOpen`.

### `obis.transport.SimulatedTransport`

| Members | What they are |
|---|---|
| `MaxPowermW`, `MinPowermW`, `WavelengthNm`, `Model`, `SerialNumber`, `BaseplateC` | what the simulated laser reports |
| `ModulationInput` | the external input level, 0–1 |
| `Calls`, `Handshake`, `Enabled`, `Mode`, `SetpointW` | state, read-only |
| `failNext(prefix, reply)`, `hangNext(prefix)`, `unplug()` | faults |
| `clearCalls()`, `callsOf(prefix)` | the calls log |

It matches the long command forms `obis.Laser` sends, in any case. Short forms get `ERR-100`, except
handshaking, which, as on the rig's OBIS Remote, is only `SYST:COMM:HAND` (the long form gets
`ERR-100`).
