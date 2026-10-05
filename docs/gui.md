# GUI: `obis.gui.LaserApp`

```matlab
obis.app()                          % owns a new obis.Laser (real laser)
obis.app('Port', 'COM15')           % owned, with options for the laser
obis.app(laser)                     % attaches to a laser you already have
obis.app(..., 'Visible', false, 'AutoRefresh', false)   % for tests
```

A window that **owns** its laser turns emission off and disconnects when it closes. A window
**attached** to your laser never disconnects it, and its auto refresh starts unticked
(architecture D6).

## Window

| Area | Controls | Sends to the laser |
|---|---|---|
| Connection | Port (editable list), Scan, Connect/Disconnect, state | on Connect/Disconnect |
| Identity | model, serial number, wavelength, limits | — |
| Settings | Mode + **Set mode** | on Set mode only |
| | Max power (mW): your limit | never (it is a local limit) |
| | Power (mW) spinner, limited to Max power, + **Set power** | on Set power only |
| | Emission switch + lamp | at once |
| Readback | the last `status()`, **Read now**, Auto refresh (every `RefreshS`, 1 s) | queries only |
| Log | the laser's last 30 commands and replies, then the window's errors | — |
| **EMISSION OFF (Esc)** | `stopAll()` | at once, in any state |

## Behaviour

- **A Set button shows bold** while its control has a change that has not been sent.
- **Errors** (a refused power, a limit above the laser's own, a timeout) go in the log and, if
  the window is visible, in an alert. They are never thrown out of a callback.
- **Script changes** made to an attached laser (`setPower`, `setEnabled`) redraw the window
  through the laser's `CommandCompleted` and `StateChanged` events.
- **EMISSION OFF** warns if the laser did not confirm, telling you to check the beam by eye.
- **Readback** skips a turn while the laser is busy with another command.

## Testing

`tests/GuiTest.m` drives every control on the simulated laser with a hidden window. It sets a
component's `Value` and calls its callback, the way a click or an edit does. A human pass on the
real laser is pending (`rig-checks.md`).
