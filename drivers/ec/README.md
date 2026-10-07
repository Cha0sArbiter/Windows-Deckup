# Embedded controller

Status: **0.2.0 development prototype built and partially tested on hardware**.
Documentation updated 2026-10-06; hardware results are from 2026-10-05.

An independent Windows UMDF 2 driver has been developed locally for the LCD
Steam Deck's `ACPI\VLV0100` interface. It reads twelve EC fields and implements
restricted, experimental fan, charge-LED and charging controls. A brief fan
boost demonstrated physical response and successful explicit automatic recovery.
It is not a fully validated production driver or a Valve-supported driver.

This update publishes documentation, pinned build-input records and redacted
hardware evidence. The driver source, clients, installation helpers and a
dedicated EC build workflow have **not yet been imported into this repository**.

## Hardware and firmware scope

| Item | Recorded target |
| --- | --- |
| Device | Valve Jupiter / Steam Deck LCD |
| ACPI device / namespace | `ACPI\VLV0100` / `\_SB.PCI0.LPC0.EC0.VFCD` |
| Tested BIOS / EC firmware / board | F7A0133 / B030 / 06 |
| Tested Windows | Windows 11 x64, build 26200 |
| Driver | UMDF 2.33 DLL, version 0.2.0.0; inbox WUDFRd |
| Prototype minimum Windows build | 26100 |
| Firmware guard | B030, board 06 or 0A; **only board 06 tested** |

OLED support and other firmware combinations have not been established.
[The prototype manifest](manifests/prototype-0.2.0.json) identifies the tested
binary, implemented limits and validation scope.

## What has been made

- Twelve-field telemetry with individual success/error status: EC firmware,
  board ID, actual fan RPM, requested fan RPM, raw fan health, battery
  temperature, raw charge limit, raw PD connection state, reported PD voltage,
  reported PD current, raw charge-rate configuration and raw panel ID.
- A versioned capability query and backward-compatible ten-field snapshot.
- Experimental manual fan targets of 2500–7300 RPM with 1–5 second leases,
  ownership per client handle, health checks and automatic-mode recovery
  attempts.
- Experimental charge-LED brightness of 0–100.
- Experimental charge-rate configuration of raw 250–2500 with baseline
  validation and register readback; physical units and behavior are unverified.
- Experimental maximum charge level of 50–100 on board 0A.
  **Charge-level writes are disabled on this Deck's board 06.**
- Administrator/SYSTEM access control, explicit control arming, fixed typed
  commands and C#/PowerShell clients.
- Build/signing helpers, pinned toolchain inputs, policy/decoder/parser tests,
  and an active fan test with a local recovery journal.

Capability validation bits remain zero. The successful brief test does not
complete the feature's remaining recovery and power-lifecycle criteria.

## What worked on hardware

All twelve fields returned successful readings. A brief request for 6000 RPM
raised measured fan speed from **4607 to 6023 RPM**. Explicit automatic recovery
returned the requested target to zero; later speed fell to **4578 RPM**.
Firmware fan health stayed at 1, and no new problem devices appeared.

The 0.2.0 test ran with Test Mode already enabled. Monitored boot/security
state was unchanged by the test. This result does not establish normal-boot,
Secure Boot or Memory Integrity compatibility for 0.2.0. The earlier read-only
0.1.1 result is recorded separately.

See [results and chronology](docs/results.md), [software validation](docs/validation.md)
and [redacted evidence](evidence/2026-10-05/index.json).

## Coverage and remaining work

[The capability map](docs/features.md) separates implemented controls, actual
hardware tests, deferred panel commands and functions outside this interface.
[The firmware contract](docs/firmware.md) records the inspected method behavior.
Panel setters, display power cycling, `SCBP` and raw transaction helpers are
not exposed. Several panel helpers have no firmware-loop timeout; method
names alone do not establish safe arguments, restoration or Windows ownership.

Remaining hardware work includes longer telemetry stability, lease expiry,
client cleanup/termination, recovery failures, multiple clients, sleep/resume,
reboot, disable/enable and operation under load. Charging and LED controls
have not been physically validated. A Windows ACPI-notification bridge is
also future work.

The ambient-light devices, AMD APU/TDP interface, GPU/display driver and game
controls are separate projects. EC battery temperature is not APU temperature,
and PD voltage/current describe a contract rather than measured APU power.

## Documentation

- [Design and ownership](docs/design.md)
- [Capabilities](docs/features.md)
- [Firmware methods](docs/firmware.md)
- [Application protocol](docs/protocol.md)
- [Build and signing record](docs/build.md)
- [Software validation](docs/validation.md)
- [Hardware results](docs/results.md)
- [Staged hardware testing and rollback](docs/hardware-test.md)
- [Provenance and licensing](docs/provenance.md)

Original prototype code and documentation are MIT licensed. Linux driver work
informed method research but was not copied into this implementation.
Valve firmware, raw ACPI tables, Microsoft/LLVM dependencies, signed binaries,
private signing material and complete machine logs are not included here.
