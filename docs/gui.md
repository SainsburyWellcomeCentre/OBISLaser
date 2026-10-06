# GUI: `obis.gui.LaserApp`

```matlab
obis.app()                          % owns a new obis.Laser (real laser)
obis.app('Port', 'COM15')           % owned, with options for the laser ('Driver', 'DllFolder')
obis.app(laser)                     % attaches to a laser you already have
obis.app(laser, 'Parent', tab)      % the panel inside another GUI's figure, panel, tab or grid
obis.app(..., 'Visible', false, 'AutoRefresh', false, 'ShowLog', false)   % for tests
```

When the panel opens it shows the laser's `Port` if it has one, else the OBIS found. An OBIS
behind an OBIS Remote or a USB-serial adapter is not a Coherent USB device, so Scan cannot
recognise it: choose its port by hand under Details, and Connect then uses it as it is.

A panel that **owns** its laser turns emission off and disconnects when it closes. A panel
**attached** to your laser never disconnects it, and its auto refresh starts unticked
(architecture D6).

## Panel

Laid out like Coherent Connection's laser panel (architecture D8). Always shown:

| Area | Controls | Sends to the laser |
|---|---|---|
| Header | lamp in the laser's wavelength colour (`wavelengthColour(nm)`): bright while emitting, dim while off, grey with no laser known (the expected wavelength's colour, dim, before Connect); model, output power / mode / on-off, state, **Start**, **Stop** | Start and Stop at once; Stop in any state |
| Connect | **Connect**: finds the laser's port (as Scan does, unless a port was picked by hand under Details) and connects; **Disconnect** once connected. Beside it, what is connected (serial number, wavelength, the laser's limits, the connection) or what Scan found | on Connect/Disconnect |
| Operating power | Power (mW) field with down and up arrows (by Step, mW), a slider from 0 to Max power, the power as a share of the laser's maximum | at once (Enter, an arrow, releasing the slider) |
| | Max power (mW): your limit; the field and the slider end there | never (it is a local limit) |
| | Mode: CW:Power, CW:Current, Digital, Analog, Mixed (`obis.Mode` CWP, CWC, Digital, Analog, Mixed) | at once |
| **Details** | a toggle arrow, folded at first; unfolds the rows below (`showDetails(tf)` from code). A window of its own grows to fit them | — |

Under Details:

| Area | Controls | Sends to the laser |
|---|---|---|
| Connection | Wavelength (nm): with several lasers, the one this panel is for (0: any). Connect then finds its port with `obis.findPort` (asks the free Coherent ports `WAVelength?`, within ±5 nm: a 488 nm laser reports 489) and refuses any other laser (`ExpectedWavelengthNm`); the header and window title say *OBIS 488 nm* until connected | never |
| | Port (editable list), **Scan**: lists the ports and selects the OBIS's (`obis.listDevices`, Windows' device list, no traffic; a free one first, and a note when there are several, it is held by another program, or none is found) | never |
| | Driver: Coherent DLL or serialport (owned laser only, while disconnected) | never |
| | DLL folder + **Browse...**: where `CoherentConnectionLibrary.dll` is, with *DLL found* / *no DLL here*. A folder holding the DLL switches the driver to the DLL and is kept for next time (`setpref('obis', 'DllFolder', ...)`) | never |
| Readback | the last `status()`, **Read now**, Auto refresh (every `RefreshS`, 1 s); it keeps updating while folded | queries only |
| Log | the laser's last 30 commands and replies, then the panel's errors (own window only, unless `'ShowLog', true`) | — |

Esc is Stop in a window of its own. Inside another GUI the host owns the keyboard.

## Two lasers

Open one panel per laser, each for its wavelength:

```matlab
obis.app('ExpectedWavelengthNm', 488)
obis.app('ExpectedWavelengthNm', 561)
```

or type the wavelength under **Details** before Connect. Each panel finds its own laser
whatever COM numbers Windows gives them, and its window title names the laser once connected.
Without a wavelength, Connect takes the first free OBIS port, so the second panel gets the other
laser, but which laser lands in which panel is then up to the port order.

## Embedding

With `'Parent', container` the panel is a `uipanel` titled *OBIS laser* inside `container`: a
`figure` (a classic one too), `uipanel`, `uitab` or `uigridlayout`. `Root` is that panel and
`Figure` the host's figure. `close()` deletes only `Root`; the host closes its figure as usual
(call `close()` from the host's own close function so an owned laser is turned off).

## Behaviour

- **Errors** (a refused power, a limit above the laser's own, a mode the laser refuses, a timeout)
  go in the log and, if the panel is visible, in an alert. They are never thrown out of a
  callback. A refused power or mode puts the last accepted one back in its control.
- **Script changes** made to an attached laser (`setPower`, `setEnabled`) redraw the panel
  through the laser's `CommandCompleted` and `StateChanged` events.
- **Stop** warns if the laser did not confirm, telling you to check the beam by eye.
- **Readback** skips a turn while the laser is busy with another command.

## Testing

`tests/GuiTest.m` drives every control on the simulated laser with a hidden window, and embeds
the panel in a `uifigure` grid and in a classic `figure`. It sets a component's `Value` and calls
its callback, the way a click or an edit does. A human pass on the real laser is pending
(`rig-checks.md`).
