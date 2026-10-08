# Fan and battery hardware: the embedded controller

The embedded controller (EC) is the Deck's small hardware controller for features such as fan speed and battery settings. This project is developing a Windows driver to read those values and carefully test selected controls.

**This folder contains documentation and redacted test records. The driver source, clients, installer, and GitHub build workflow have not been uploaded yet. There is no public EC driver package to install from this repository.**

## What works so far

The local **0.2.0 prototype** read twelve hardware values on one LCD Deck. A brief fan test raised measured speed from **4607 to 6023 RPM**, then returned control to the firmware; later speed fell to **4578 RPM**.

That is a useful first result, but it does not establish reliable fan recovery after crashes, sleep, or longer use. Charging and LED controls have not been physically tested. The prototype's own fully-validated feature flags remain clear until those remaining checks pass.

The control prototype was tested with Test Mode already enabled. It has not been shown to work with Test Mode off. A separate earlier read-only prototype did pass with it off; that result does not transfer to version 0.2.0.

## Choose a page

- [Feature status](docs/features.md): what exists and what is still planned.
- [Hardware results](docs/results.md): measurements from the actual Deck tests.
- [Design](docs/design.md), [firmware methods](docs/firmware.md), and [application protocol](docs/protocol.md): developer references.
- [Build record](docs/build.md), [software tests](docs/validation.md), and [hardware test plan](docs/hardware-test.md): how the local prototype was built and checked. Commands refer to files not yet hosted here.
- [Research sources and licenses](docs/provenance.md).

The detailed record follows. If you are looking for a ready-to-install driver, there is no further installation step here yet.

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

## Experimental controls and limits

The prototype implements manual fan requests of **2500–7300 RPM**, with a short **1–5 second lease** that the requesting application must renew. It attempts to restore automatic control when that request ends. Crash and power-transition recovery still need hardware tests; this is not an independent hardware watchdog.

LED brightness and charge-rate controls exist in the local code but have not been physically validated. Charge-rate values are raw firmware units, not established milliamps or watts. Maximum-charge-level control is restricted to board 0A and is **disabled on the tested board 06**.

Panel commands and display power cycling are not exposed. Some firmware helpers can wait indefinitely, which could interfere with other operations, including fan recovery.

Battery temperature is not processor temperature. Reported USB power-delivery voltage/current describe a negotiated power contract, not actual power consumption.

## What comes next

Import the source and build tools, then complete longer read-only sampling, fan lease-expiry and client-exit checks, recovery-failure tests, and Windows sleep/restart tests. Charging and LED features need separate physical validation. Board 0A, other firmware versions, and OLED support need their own evidence.

The [feature table](docs/features.md) tracks these limits. The [hardware report](docs/results.md) and [redacted evidence](evidence/2026-10-05/index.json) preserve the actual measurements.

Original project work uses the MIT license. Vendor firmware, external dependencies, private signing material, and complete machine logs are not published here. See [sources and licensing](docs/provenance.md).
