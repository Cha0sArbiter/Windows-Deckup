# Firmware contract: LCD Jupiter, BIOS F7A0133

Evidence: read-only extraction and offline disassembly of the local DSDT.
The firmware table itself is not redistributed. Device path:
`\_SB.PCI0.LPC0.EC0.VFCD`, hardware ID `VLV0100`.
The driver checks PDFW `0xB030` and BOID `0x06` or `0x0A` on every D0 entry.
Board 06 has twelve-field telemetry and brief fan-test evidence; board 0A remains untested.
This describes the known VLV0100 interface; undocumented firmware functions may exist.

| Method | Arguments | Observed contract | Project handling |
| --- | --- | --- | --- |
| PDFW | none | EC firmware value | Telemetry / identity guard |
| BOID | none | Board value | Telemetry / identity guard |
| FANR | none | Measured fan RPM | Telemetry / health check |
| FSSR | none | Requested fan RPM registers | Telemetry / setter readback |
| FANC | none | 0: fan check failed; 1: normal; 2: fan check passed but CTMP > 95 | Raw telemetry / only value 1 permits manual fan |
| FANS | integer | 0: firmware automatic; 1–7300: target RPM; higher values clamp | Typed setter; project permits manual 2500–7300 only |
| BATT | none | (raw temperature - 2732) / 10 | Battery C; unsigned negative-temperature behavior unvalidated |
| PDCS | none | Raw USB PD connection state | Raw telemetry; bit decoding not advertised |
| PDVL | none | PD voltage register * 50 | Reported mV |
| PDAM | none | PD current register * 10 | Reported mA |
| GCHR | none | Current charge-rate configuration registers | Extended telemetry, raw units |
| CHGR | integer | Accepts 250–2500; other values do not change registers | Typed experimental setter / GCHR readback |
| GFBL / SFBL | none | Same charge-limit register | GFBL telemetry/readback; duplicate SFBL not separately exposed |
| FCBL | integer | Accepts 0–100, returns charge-limit register | Project permits 50–100, board 0A only |
| CHBV | integer | Accepts 0–100, writes charge-LED PWM register | Typed experimental setter; no getter |
| PANR | none | Panel identification register | Extended telemetry, raw |
| RDDI | integer | Panel register read via EC handshake | Not exposed; helper loop may stall |
| CABC / GAMA / WDBV / WCDV / WCMB / MDAC | integer | Panel command byte payloads via EC handshake | Not exposed; semantics/Windows interaction unvalidated |
| NORO / INOF / INON / WRNE | none | Panel command via EC handshake | Not exposed; semantics/recovery unvalidated |
| DPCY | none | EC command for display power cycle | Not exposed; recovery/Windows interaction unvalidated |
| SCBP | integer | Accepts 0/1 and inversely sets CBPW | Not exposed; behavioral meaning unvalidated |
| ANR1 / ANR4 / ANW1 / ANW4 | 2/3 arguments | Internal raw-access handshake helpers; while loop has no timeout | Never exposed as a public API |
| _INI / _STA | none | ACPI lifecycle/status methods | Windows owns lifecycle; not application commands |
| EC query _Q9C / Notify(VFCD, 0x80) | firmware event | Status-change notification gated by VPME | Windows notification bridge not implemented |

STCT, SGAN, SFRR, SHTS and SCHG appear in the 2022 Linux driver proposal but
are not present in this device's VFCD scope. Porting the proposal verbatim
would expose controls that cannot work through this BIOS's ACPI interface.

`FANS`, `CHGR`, `CHBV` and other methods can return success despite skipping
their body if the firmware mutex cannot be acquired. Fan/charging readback is
therefore essential; an NTSTATUS alone does not prove the setting took effect.
The charge LED has no getter, so software cannot confirm its physical output.

Several panel methods call helpers that wait for an EC bit to clear without a
firmware timeout. A host-side WDF cancellation request does not establish that
those loops or underlying hardware operations have stopped.
