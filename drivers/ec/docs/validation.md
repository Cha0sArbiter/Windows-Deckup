# Software validation: 0.2.0, 2026-10-05

| Check | Result |
| --- | --- |
| x64 UMDF 2.33 DLL compile/link | PASS |
| Microsoft InfVerif /w | PASS |
| Inf2Cat Windows 11 signability | PASS; no errors or warnings |
| Policy tests against fake EC | PASS; 36,919 assertions |
| ACPI decoder tests | PASS; 10,553 cases including guard-page truncation |
| Legacy C# parser | PASS; 202 cases |
| New capabilities/snapshot C# parsers | PASS; 311 cases |
| C# parser tests under PowerShell 7 and Windows PowerShell 5.1 | PASS |
| GS/ASLR/DEP/high-entropy/CFG PE metadata | Checked in the built DLL |
| Local DLL/catalog signing and membership | Checked before creating local-test archive |

The policy tests exercise fan boundaries, unarmed denial before hardware
access, malformed payloads, board gating, exclusive ownership, renewal,
expiry, client cleanup, health/stall/interference recovery, partial-write
failure, failed recovery/retry, charge baseline validation and register rollback.
They run a fake backend; none executes firmware methods.

The decoder uses actual Windows SDK structure fixtures and checks truncated,
malformed, null and oversized buffers without changing output on failure.
The clients reject malformed headers, sizes, feature masks, field order and
failed readings. Synthetic fixtures are not displayed as hardware samples.

Manual source review corrected a potential timer starvation issue: renewing
the lease must not restart an already pending health timer. Power/file/timer
callbacks and IOCTLs share one explicit passive lock. D0 exit stops the timer
without waiting on a callback that could be waiting for that lock.

Not covered by these software tests: kernel/UMDF access checks,
firmware enforcement of charging limits, LED behavior,
timer behavior under Windows power transitions, suspend/resume, UMDF-host
crash recovery, continuous load or broad firmware/hardware compatibility.
The cold-machine dependency bootstrap also remains untested end to end.
These gaps are recorded explicitly in capability and release metadata.

Separate hardware testing installed 0.2.0, verified its exact signed DLL,
read all twelve fields, and demonstrated a brief measured fan response followed
by explicit automatic recovery. See [the hardware report](results.md).
At the end of the recorded test, 0.2.0 remained installed with the read-only predecessor retained.
Hardware capability bits remain zero until the full feature criteria pass.

This documentation update did not rebuild a driver or rerun these tests. The results above are historical prototype validation, not hosted EC CI results.
