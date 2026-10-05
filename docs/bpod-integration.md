# Integrating with Bpod protocols and other closed-loop hosts

## 1. Choosing a control strategy

| Need | Strategy |
|---|---|
| Light only when the state machine says, at a power fixed for the session | **Digital** mode, set the power once in setup, gate with a TTL (BNC, or a device such as a DMD) |
| A different power per trial | Digital mode, plus a soft code in the trial's first state that sets that trial's power before any TTL |
| Light under MATLAB's control, not the state machine's | CWP mode and `setEnabled` (timing is MATLAB's, not microsecond-precise) |
| An analog waveform | **Analog** mode from an analog output (e.g. a Bpod analog output module). `MaxPowermW` does not apply to the voltage |

## 2. Lifecycle in a Bpod protocol

```matlab
% Setup, once, before the first trial
laser = obis.Laser('Port', 'COM15');
laser.connect();                         % emission off
laser.MaxPowermW = 60;                   % what this preparation tolerates
laser.setMode('Digital');
laser.setPower(0);
laser.setEnabled(true);                  % from now on the TTL decides
BpodSystem.PluginObjects.Laser = laser;
cleanupLaser = onCleanup(@() laser.disconnect());   % emission off however the protocol ends

% Per trial: the power for the trial being prepared is queued, then set from the soft code
% its first state sends (OutputActions {'SoftCode', 13}), before any TTL state.

% End of session
BpodSystem.Data.Laser = laser.record();
SaveBpodSessionData;
```

The record holds the identity, the limits, the mode and the log: every power set, with its time
and latency.

## 3. Soft-code driven control

The soft-code handler runs in MATLAB while the state machine runs. It must be short and must
never throw, or Bpod stops the session:

```matlab
function SoftCodeHandler(code)
    global BpodSystem
    if code == 13
        try
            BpodSystem.PluginObjects.Laser.setPower(nextPowerFromYourQueue());
        catch err
            % log it to a file; do not rethrow
        end
    end
end
```

Points to know:
- **Latency.** `setPower` returns when the laser has answered `OK`, typically a few ms over USB
  serial (see `log()` `LatencyMs`, and measure on your rig: `rig-checks.md`). Give the state that
  sends the soft code enough time before the first TTL.
- **One command at a time** (architecture D6). Nothing else may talk to the laser while the
  session runs, including an attached control window with auto refresh ticked.
- **Refusals are errors.** A power above `MaxPowermW` raises, and nothing is sent. Check the
  trial's power when you prepare the trial, not in the handler.
- `examples/example_bpod_softcode.m` shows the whole pattern, with a loop standing in for Bpod.

## 4. Other hosts

Any MATLAB host follows the same pattern: connect once, `stopAll()` or `disconnect()` in every
exit path, `record()` into the data. For an emulator or dry run, pass
`'Transport', obis.transport.SimulatedTransport()`, and the rest of the code stays the same.
