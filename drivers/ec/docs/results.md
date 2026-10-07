# EC hardware results and chronology

**PASS for installation, short telemetry inspection, brief fan boost and
explicit automatic recovery on one device.** This is partial validation,
not completion of the feature or production-release criteria.

Tested on a Valve Jupiter LCD Deck, BIOS F7A0133, EC firmware B030, board 06,
Windows build 26200. The active test ran on 2026-10-05 from 20:09:08 to
20:09:16 UTC (15:09:08–15:09:16 America/Chicago, CDT). The bound package was
DeckEc.inf, version 0.2.0.0.

Tested signed DLL SHA-256:
`9A2F6E4F7F8E6CBE0CCC03CDFB5DF9AC3B92F07004DA9D3381E263E9D3AE1EE5`.

## Observed fan response

| Phase | Measured RPM | Requested target RPM | Firmware health FANC |
| --- | ---: | ---: | ---: |
| Baseline | 4607 | 0 (automatic) | 1 |
| Boost sample 1 | 4802 | 6000 | 1 |
| Boost sample 2 | 5233 | 6000 | 1 |
| Boost sample 3 | 5629 | 6000 | 1 |
| Boost sample 4 | 6023 | 6000 | 1 |
| Boost sample 5 | 6023 | 6000 | 1 |
| Explicit recovery sample 1 | 5875 | 0 (automatic) | 1 |
| Explicit recovery sample 2 | 5543 | 0 (automatic) | 1 |
| Later inspection 1 | 4867 | 0 (automatic) | 1 |
| Later inspection 2 | 4578 | 0 (automatic) | 1 |

The peak rose 1416 RPM above baseline, exceeding the 200 RPM acceptance
criterion. FSSR consistently reported the 6000 request during the boost.
After FANS(0), the two recovery snapshots reported FSSR zero and healthy
FANC; capability state was Unowned with last recovery status 0x00000000.
The subsequent samples showed continued slowing toward the prior speed.
This demonstrates physical response and explicit return to firmware policy
for this short test; it does not measure cooling performance under game load.

## Installation and telemetry

Package DLL/catalog signatures, catalog membership, release hashes, published
INF hash and installed DLL hash were checked. The exact new package bound
successfully with device status OK and problem code 0.
Four slow pre-test snapshots and later snapshots returned all twelve fields
successfully. Extended fields reported GCHR raw 0 and PANR raw 1.
The raw zero charge-rate baseline is not evidence of established units or a
usable charging limit; the charge setter rejects an invalid baseline.
Battery temperature was 30 C; this is not APU temperature. Reported PD values
were 15000 mV / 3000 mA and describe a contract, not actual consumption.

No new problem devices appeared. The two pre-existing ambient-light devices
remain separate work. No matching events were found in the queried System,
UMDF Operational or Code Integrity Operational logs during this run;
absence of logged events does not prove broader crash/lifecycle stability.
Monitored boot/security state was identical before and after this test:
Test Mode was already enabled, reported code-integrity flags were 0x00280203,
Secure Boot registry state was 0, the Memory Integrity configured value was
absent and the vulnerable-driver blocklist was enabled. These registry records
do not establish every runtime security property. The test did not change
these settings and does not prove 0.2.0 operation with Test Mode off.
Existing certificate trust was reused. No charging, LED, display, TDP or
boot/security setting was changed by the test.

## Initial attempt and correction

The first attempt installed and read the new driver, then stopped before
arming or changing the fan. Its first test snapshot hit the global one-second
snapshot limiter because it followed the preceding inspection too quickly
(Win32 170, busy). The wrapper was corrected to wait 1200 ms before starting
the active test. The first attempt verified automatic mode and removed only
the new package, restoring the retained predecessor. PnPUtil reported that
the predecessor was already present/up to date (exit 259); the next run
verified its binding and successful read before installing the new package.
Both attempts' full local journals are retained outside publication archives.

## Remaining validation

Not exercised: ten-minute read-only stability, lease expiry with a live handle,
cleanup/client termination, competing clients, recovery retry failures,
sleep/resume, reboot, disable/enable, UMDF-host failure or long operation/load.
Charging and LED controls remain untested. Board 0A and other firmware/model
combinations were not tested. Full fan-feature capability validation remains
zero until the staged recovery and lifecycle criteria are completed.

The read-only predecessor remains in Driver Store for rollback. At the end of the recorded run, the new
experimental driver remained installed in automatic fan mode.

## Earlier read-only prototype

The 0.1.1 prototype (Windows DriverVer 0.1.0.1) passed installation and four
ten-field snapshots around 11:51 America/Chicago on 2026-10-05. RPM was
4578, 4578, 4578 and 4549; battery temperature was 32 C, FSSR zero and FANC 1.
Its dedicated signer was trusted locally. The recorded test had Test Mode
disabled with code-integrity flags 0x00000001. A non-elevated client was denied
with Win32 error 5. These results apply to that predecessor.

Read-only signed DLL SHA-256:
`59D98A9EB9144AF063938DE1525199CFDA410210F9FB34F93F56D5975735A5D8`.

An initial startup attempt terminated its UMDF host at
`CWudfDeviceStack::Forward`. The corrected INF permits null file objects on
the driver's own ACPI queries; kernel-mode clients remain rejected. Another
attempt read correctly but the helper misclassified missing Process.ExitCode
as failure. Retaining the process handle before waiting corrected that helper.
The working read-only package was preserved for the later control-driver trial.

## Evidence handling

[The evidence index](../evidence/2026-10-05/index.json) records SHA-256 hashes of
the retained original journals and what the published summary excludes.
Only redacted, selected results are published. Per-machine instance suffixes,
published INF numbers, local profile/DriverStore paths, full inventories,
raw transcripts, certificates/keys and ACPI table dumps are not imported.
The public summary is not a byte-for-byte replacement for local originals.

This documentation update performs no new hardware test and does not transfer
the APU project's later normal-boot or sleep results to the EC driver.
