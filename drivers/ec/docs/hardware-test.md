# EC hardware test plan and recovery checks

This is an engineering test plan for the local prototype, not a public installation guide. Its scripts and packages are not included in this repository. The installation and rollback commands require the exact locally verified packages and recorded driver names. Do not substitute guessed names. See the [EC overview](../README.md) for availability.

**Initial installation, twelve-field telemetry, brief fan boost and explicit
automatic recovery passed on 2026-10-05.** At the end of that run, 0.2.0 remained installed;
the read-only predecessor remained staged for rollback. The user explicitly
approved the fan-speed test. [Actual results](results.md) identify the
tested binary and distinguish completed checks from the remaining stages.

The script names below refer to the existing local prototype package. They
are not included in this documentation-only repository import.

## Recommended sequence and acceptance criteria

| Stage | Test | Pass condition |
| --- | --- | --- |
| 1. Install / inspect | Verify exact binding, signature, firmware identity and four slow snapshots of all twelve fields | Correct DLL bound; required readings valid; no new device errors or host crashes |
| 2. Read-only stability | About ten minutes of ordinary use with samples every ten seconds | No failed/hung calls, unexpected setter effects or new device errors |
| 3. Brief fan boost | Five-second request above measured baseline, then explicit automatic recovery | Target matches; RPM rises at least 200; two healthy recovery samples show FSSR zero and recovery complete |
| 4. Recovery | Lease expiry with handle open; normal close; terminate only the client | Each scenario releases this driver's override and returns the target to zero; record elapsed recovery time |
| 5. Lifecycle | Sleep/resume, reboot, disable/enable with fan in automatic mode first | Identity rechecked; telemetry resumes; no persisted driver-owned override or startup error |
| 6. Longer operation | Ordinary game/load session after recovery tests, with independent APU-temperature monitoring | Stable reads/controls and thermal behavior; no host crashes, failed recovery or unexpected clock/temperature behavior |
| 7. Other controls | LED separately; charge rate only after units/baseline are established | Physical effect observed and original behavior restored; register-only success does not count |

These are staged engineering tests, not a guarantee from a particular duration
or number of samples. Record firmware, board, Windows build, bound binary hash,
test actions, actual readings, errors and recovery outcomes. Keep device IDs
and personal logs local; publish an anonymized result matrix with the source.
Any failed recovery, hang or firmware-health error stops progression to the
next stage. Preserve the working read-only package for rollback throughout.

For a longer read-only sample set after installing the new driver:
`Get-DeckEc.ps1 -Samples 60 -IntervalMs 10000 -Json`.
This is roughly ten minutes, depending on firmware response time.

The project's BATT field is battery temperature, not APU temperature. PDVL/PDAM
report a negotiated contract, not measured battery charging power or APU draw.
They cannot substitute for the independent measurements needed in later tests.

Before a public binary release, include per-driver UMDF Verifier testing and
Windows device/power lifecycle checks. Microsoft documents the appropriate
UMDF verification workflow:
[Microsoft UMDF Verifier guide](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/using-umdf-verifier)
Do host-debugging/fault-injection work in automatic fan mode first. An abrupt
UMDF-host failure can bypass this project's software recovery mechanisms;
client termination and driver-host termination are different test cases.

## Detailed installation checks

1. Record the connected VLV0100 device's current INF and version. Retain the
   original 0.1.1 package for rollback; do not remove it from Driver Store.
2. Verify the release manifest, DLL/catalog Authenticode signer and catalog
   membership of both DLL and INF. The local test uses the already trusted
   prototype public certificate. No new trust or boot changes are required.
   If Windows refuses the package, inspect the actual failure instead of
   changing security settings.
3. From an administrator terminal, stage/install this exact new INF:
   `pnputil /add-driver .\package\DeckEc.inf /install`
4. Record its actual published `oemNN.inf`, confirm the exact device started
   with the new DLL, then run `Get-DeckEc.ps1 -Capabilities` and four slow
   telemetry samples. Confirm all twelve statuses individually. A GCHR/PANR
   failure must be reported; do not replace it with a made-up value.
5. Confirm ordinary reads have not issued setters, no new problem devices
   appeared, and boot/code-integrity state matches the baseline. Check a
   non-administrator client is denied. A read-only handle must not be able to
   arm controls, and an unarmed read/write handle must not issue setters.

## First active test: a brief fan boost

`tools\Test-FanBoost.ps1 -RunHardwareTest` opens one armed fan session and
requests a target above the measured baseline for five seconds. It reads
actual RPM/target/firmware state, explicitly restores automatic mode, then
checks that FSSR is zero. It does not alter charging, LED, display or TDP.

Passing also requires measured RPM to rise by at least 200 above baseline
within the short test, normal fan health throughout, and two healthy samples
after restoration with FSSR zero and no pending recovery. The RPM criterion
distinguishes physical response from a setter merely updating its register;
failure to reach it is an inconclusive/failed short response test, not proof
that the fan is faulty. Detailed baseline/boost/recovery snapshots and errors
are saved in a local JSON journal under `logs` or an explicit `-LogDirectory`.
Local journals are excluded from publication archives.

Preconditions: verified B030 identity, normal firmware fan state, FSSR zero,
valid nonzero measured fan RPM below 7000, no other fan utility or active
manual target. The driver blocks unsupported identities and board-06 charge
level control. Run the test only after approving that active hardware scope.

Later validation should separately cover lease expiry while the handle stays
open, client cleanup, multiple-client ownership, recovery retries, ordinary
load, suspend/resume and UMDF-host restart. The fake-backend tests cover those
policy decisions but cannot prove real firmware or Windows recovery behavior.
Keep the feature validation bit clear until the remaining recovery/lifecycle
criteria are completed; the successful brief boost is only one stage.

## Charging, LED and display validation

Validate charge-rate units and physical behavior against battery telemetry
before testing CHGR. Record and verify the original value and rollback.
Register readback alone does not prove current limiting works.
Charge level stays disabled on board 06; board 0A requires its own hardware
test, including actual stop/resume charging behavior. LED testing requires
observing the indicator and determining how to restore its original policy.
Display and SCBP operations are not exposed in this revision.

## Rollback

Use the new package's **actual recorded** published name, after confirming
that it identifies DeckEc.inf. Do not guess it or select a wildcard:

```powershell
pnputil /delete-driver <new-recorded-oemNN.inf> /uninstall
pnputil /add-driver <retained-prototype-folder>\package\DeckEcReadOnly.inf /install
```

If the new driver is still responding and owns a manual fan target, restore
automatic mode before removing it. If recovery fails or firmware stalls, a
driver rollback cannot be assumed to restore the fan policy: stop the test
and establish firmware automatic operation before resuming load.
Keep the existing public certificate trusted while the old prototype uses it.
Do not delete unrelated packages/certificates or change boot settings.
