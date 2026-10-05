# OBIS command set (SCPI over serial)

Everything this package relies on about how the laser talks. Each fact is marked with where it
comes from:
- **rig** — seen on this rig's laser, with the date
- **lab code** — sent by `LuminoseHF`'s `LaserModel`, which ran sessions on this laser, though
  it never read the replies
- **verify** — from the Coherent OBIS operator's manual (remote-control chapter), not yet seen
  here

When something is checked on the laser, replace *verify* with **rig** and the date.

## 1. Link

| Fact | Value | Source |
|---|---|---|
| Port | USB virtual COM port (OBIS LX/LS USB), or the OBIS Remote's port | lab code (`COM15`) |
| Settings | 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control | lab code (baud); verify (rest) |
| Line ending | commands end with CR/LF; replies end with CR/LF | lab code (sent CR/LF) |
| Case | keywords are case-insensitive; upper-case letters mark the short form (`SOURce` = `SOUR`) | verify |
| Holding the port | Coherent Connection keeps the port open while running: close it first | verify |

## 2. Handshaking and replies

- With handshaking on, each command gets an `OK` line once it is processed.
- A query gets its value line, then `OK`.
- A refused command or query gets `ERR-<code>` instead of `OK`.
- With handshaking off, commands get no reply, and queries get the value only.

`obis.Laser.connect` sends `SYST:COMM:HAND ON` first and then always reads to `OK`
or `ERR` (architecture D1).

Source: **rig** 2026-10-05 (the probe in `rig-checks.md`): with handshaking on, every query gave
its value then `OK`, and unknown commands gave `ERR-100`. The behaviour with handshaking off is
still *verify*. The first rig check confirms them (`rig-checks.md` §1).

Error codes:

| Reply | Meaning (manual) | Source |
|---|---|---|
| `ERR-100` | unrecognised command | verify |
| `ERR-101` | invalid command | verify |
| `ERR-102` | invalid parameter / value out of range | verify |
| `ERR-350` | queue overflow | verify |
| others | see the manual's error table; record any seen here | — |

The simulated laser uses `ERR-100` for an unknown command and `ERR-102` for a bad value.

## 3. Commands used by `obis.Laser`

Powers are in **watts** on the wire; `obis.Laser` converts to and from mW.

| Command | Reply | Used by | Source |
|---|---|---|---|
| `SYST:COMM:HAND ON` | `OK` | `connect` | **rig** 2026-10-05: the OBIS Remote (v2.0.2) answers `ERR-100` to the long form `SYSTem:COMMunicate:HANDshake ON` and to `SYSTem:COMMunicate:HANDshake?`; `SYST:COMM:HAND?` gives `ON` |
| `*IDN?` | `Coherent, Inc - OBIS <nm> <type> <mW> Laser - <serial> - <firmware> - <date>` | `connect` | **rig** 2026-10-05: through the OBIS Remote it is the controller's: `Coherent, Inc. - OBIS MINI-CONTROLLER - v2.0.2 - 20120416` |
| `SYSTem:INFormation:MODel?` | model text | `connect` | **rig** 2026-10-05: `OBIS MINI-CONTROLLER` |
| `SYSTem:INFormation:SNUMber?` | serial number | `connect` | **rig** 2026-10-05 |
| `SYSTem:INFormation:WAVelength?` | nm | `connect` | **rig** 2026-10-05: `489` |
| `SOURce:POWer:LIMit:HIGH?` | W (laser's maximum setpoint) | `connect` | **rig** 2026-10-05: `0.16500` |
| `SOURce:POWer:LIMit:LOW?` | W (lowest setpoint) | `connect` | **rig** 2026-10-05: `0.00000` |
| `SOURce:AM:STATe ON` / `OFF` | `OK` | `setEnabled`, `stopAll`, `connect` | lab code |
| `SOURce:AM:STATe?` | `ON` / `OFF` | `status` | **rig** 2026-10-05 |
| `SOURce:AM:INTernal CWP` / `CWC` | `OK` | `setMode` | lab code (CWP); verify (CWC) |
| `SOURce:AM:EXTernal DIGital` / `ANALog` / `MIXed` | `OK` | `setMode` | lab code (DIGital); verify (rest) |
| `SOURce:AM:SOURce?` | `CWP`, `CWC`, `DIGITAL`, `ANALOG`, `MIXED` (also `DIGSO`, `MIXSO` on some models: not in `obis.Mode`) | `connect`, `status` | **rig** 2026-10-05: `DIGITAL` |
| `SOURce:POWer:LEVel:IMMediate:AMPLitude <W>` | `OK` | `setPower` | lab code |
| `SOURce:POWer:LEVel:IMMediate:AMPLitude?` | W (setpoint) | `connect`, `setpointmW`, `status` | **rig** 2026-10-05 |
| `SOURce:POWer:LEVel?` | W (output the laser measures) | `powermW`, `status` | lab code (its reply was read after unread `OK` lines, so never reliably) |
| `SOURce:TEMPerature:BASeplate?` | e.g. `28.5C` | `status` | **rig** 2026-10-05: `24.5C` |
| `SYSTem:STATus?` | 8 hex digits, status bits | `status` | **rig** 2026-10-05 |
| `SYSTem:FAULt?` | 8 hex digits, fault bits (`00000000` = none) | `status` | **rig** 2026-10-05: `80000000` with no laser fault seen; meaning not yet looked up |

Other commands reach the laser through `laser.query(line)` and `laser.command(line)`. Examples
include `SYSTem:CDRH ON|OFF` (the 5 s emission delay), `SYSTem:AUTostart`, `SYSTem:HOURs?` and
`SYSTem:LOCK?` (interlock state). `command()` refuses anything that sets power (architecture D4).

## 4. Modes and the modulation input

The OBIS's SMB input (or the OBIS Remote's) is the modulation input. On this rig it carries
**DMD pin 8**, the ALP frame-synch output (`LuminoseHF` memory *Laser pin 8 gating*).

| Mode | Output | Source |
|---|---|---|
| CWP | setpoint whenever emission is on; power loop active | lab code |
| CWC | constant current; output drifts with temperature | verify |
| Digital | setpoint while the input is high, off while low | lab code (the rig runs in it) |
| Analog | 0–5 V input scales output from 0 to the laser's maximum; the setpoint does not cap it | verify |
| Mixed | digital and analog together | verify |

Open questions for the rig (`rig-checks.md`):
- Does the laser accept a mode change with emission on?
- What does it do with a setpoint below `LIMit:LOW`?
