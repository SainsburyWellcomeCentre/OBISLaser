# Rig checks

Every run against the real laser is recorded here: date, who approved it, what was run and what
was seen. Each run needs the operator's explicit permission **for that run** (`CLAUDE.md`).

The test suite and the examples on the simulated laser need no permission and are not recorded
here.

## Pending

None of these have been run. Do them in order, with the beam blocked (a power meter head in the
path is ideal) and Coherent Connection closed. `tests/hardware/checkLaser.m` runs steps 1–5 and
prints what to record.

### 1. Connection and replies

`connect()` on `COM15`. Record:
- whether every command got `OK`
- the `*IDN?` text, model, serial number and wavelength
- `LIMit:HIGH` and `LIMit:LOW`
- the mode and setpoint read back

Then compare the `log()` latencies with `docs/scpi.md`. Turn each *verify* there that this
confirms into **rig** with the date.

### 2. Every mode and the readback

`setMode` to each of CWP, CWC, Digital, Analog and Mixed, first with emission off and then with
emission on. Record any `ERR-<code>`: whether the laser refuses a mode change with emission on
is an open question (`scpi.md` §4).

### 3. Power: setpoint, output and limits

- In CWP with emission on, set 1, 5, 10 and 50 mW. Compare `powermW()` with a power meter.
- Set a value below `LIMit:LOW`, and record whether it is accepted.
- Confirm that `setPower` above `MaxPowermW` sends nothing (check the log).

### 4. Digital gating from the DMD

In Digital mode at a known setpoint, project a DMD sequence. Confirm that light appears only
during the pin 8 synch pulses and at the setpoint power (`LuminoseHF` memory *Laser pin 8
gating*).

### 5. Emission off on every path

Check, by eye or meter, that emission goes off for each of:
- `disconnect()`
- `delete(laser)`
- closing an owning `obis.app()` window
- EMISSION OFF
- Esc
- a protocol error inside `LuminoseHF` (its cleanup)

Also confirm what the laser does when MATLAB is **killed** with emission on. The expected answer is
that it keeps emitting: write that into the README's *Safety* section once seen.

### 6. Latency of `setPower` from a soft code

During a `LuminoseHF` session, read `LatencyMs` from the saved `record()` for every soft-code-13
`setPower`. It must fit in the `SetLaserPower` state's time budget.

### 7. GUI details that need a human

- Esc reaches the window from every control.
- The Port list and Scan.
- An alert on a refused power.
- The Set buttons going bold and back.

## Log

### 2026-10-05: read-only probe after `connect` failed (operator approved)

A `luminose_hf_powercal` session stopped in `connect` with `ERR-100` on
`SYSTem:COMMunicate:HANDshake ON`. Raw `serialport` on `COM15` (115200, CR/LF) sent only queries,
plus the handshake command. No emission or power commands were sent.

- Nothing was waiting on the port after open.
- `SYSTem:COMMunicate:HANDshake ON` and `SYSTem:COMMunicate:HANDshake?` gave `ERR-100` (twice).
  `SYST:COMM:HAND?` gave `ON`, `OK`. **Fix:** `connect` now sends `SYST:COMM:HAND ON`.
- `*IDN?` gave `Coherent, Inc. - OBIS MINI-CONTROLLER - v2.0.2 - 20120416`. The port is the OBIS
  Remote, and `MODel?` names the controller (`OBIS MINI-CONTROLLER`), not the laser head.
  `SNUMber?` gave `M161017003` and `WAVelength?` gave `489`.
- `LIMit:HIGH?` gave `0.16500` (165 mW) and `LIMit:LOW?` gave `0.00000`.
- State as found: mode `DIGITAL`, `AM:STATe ON` (emission left enabled, gated by pin 8), setpoint
  `0.06937` W, output `0.00000` W, baseplate `24.5C`, `SYSTem:STATus?` `C8001486`,
  `SYSTem:FAULt?` `80000000`.
- Every query listed in `scpi.md` §3 answered with its value then `OK`.

Still open from step 1: `connect()` itself has not yet been run end to end through `obis.Laser`.
