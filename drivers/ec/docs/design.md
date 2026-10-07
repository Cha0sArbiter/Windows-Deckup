# Prototype design and ownership

The local 0.2.0 prototype is a UMDF 2.33 x64 function driver for
`ACPI\VLV0100`. It uses Microsoft's inbox WUDFRd and evaluates a fixed
allowlist of methods on the device's ACPI stack. It contains no custom
kernel-mode `.sys`, raw-memory driver or application-supplied register addresses.

## Components already developed locally

| Component | Responsibility |
| --- | --- |
| WDF driver | Device lifecycle, ACPI transport, interface, IOCTL validation, queue and timer |
| Control-policy core | Limits, arming, fan ownership/lease, health checks, recovery and charging readback |
| ACPI decoder | Validate bounded Windows ACPI result buffers and integer layouts |
| C# clients | Enumerate the intended interface; validate snapshots/capabilities; own a session handle |
| PowerShell tools | Inspection, explicit experimental controls, parser tests and journaled fan test |
| Build/release tools | Pinned inputs, compilation, INF checks, local signing, hashing and publication separation |

These components exist in the local prototype. This documentation update
does not import their implementation or add a hosted EC build workflow.

## Access and serialization

Only administrators and SYSTEM can open the interface. Reads require read
access; controls require read/write access plus explicit feature arming on
the same handle. New sessions begin unarmed. Unknown IOCTLs, malformed buffers
and unsupported board/firmware combinations are rejected.

A sequential, power-managed WDF queue and one passive wait lock serialize
IOCTLs, file cleanup, timer and power callbacks. The firmware identity guard
checks B030 and board 06/0A on D0 entry. Normal startup/open/read paths issue
no setters. Previously tracked recovery can be retried on re-entry.

ACPI transport uses a 750 ms timeout with best-effort cancellation. This
does not guarantee Windows or firmware can abort an operation.
Snapshots are sequential measurements, not one atomic EC transaction.

## Fan control

Manual requests carry a 1–5 second lease and request 2500–7300 RPM.
Ownership is exclusive within this driver and associated with the client
handle. An existing nonzero FSSR prevents starting an override.
This does not coordinate every third-party utility.

The driver validates fan health and target readback, and tracks ownership
before writing because failed transport may still have changed hardware.
Its nonperiodic one-second timer reschedules while ownership or recovery is
active. Renewal does not restart an already pending timer, avoiding
health-check starvation.

Automatic-mode recovery is attempted on explicit release, lease expiry,
owner-handle cleanup, failed health/readback, target interference, zero RPM
after the startup allowance and D0 exit. Failed recovery remains tracked
and is retried while the device is available.

These mechanisms are best effort. Firmware stalls, abrupt UMDF-host failure
or device removal can prevent recovery. They are not an independent hardware
watchdog. Only the brief boost and explicit recovery have passed on hardware;
lease, cleanup, host-failure and power-lifecycle behavior still need tests.

## Charging, LED and panel boundaries

Charging setters validate an existing baseline and verify register readback.
On failure, they attempt to restore the recorded baseline. This does not
prove physical charging enforcement. Charge-level writes are gated to board
0A; the tested board 06 is excluded. Charge-LED brightness has no getter,
so its physical effect and restoration remain untested.

Panel commands are deferred because helper loops can wait indefinitely while
holding a shared firmware mutex. A stalled transaction could interfere with
other EC methods, including fan recovery. Validated argument/restoration
contracts and coordination with Windows display ownership are also missing.
`SCBP` semantics remain unresolved. Raw transport and ACPI lifecycle methods
stay internal.

## Capability and release reporting

Implemented features, hardware-validated features and per-session arming
are separate masks. The current binary reports zero hardware-validation
bits because complete recovery/lifecycle criteria have not passed.

A hardware result applies to the exact signed DLL hash in
[the manifest](../manifests/prototype-0.2.0.json). Rebuilding or signing a
different DLL does not inherit that result. The ten-field V1 interface remains
compatible while V2 adds charge-rate configuration and panel identification.

See [the protocol](protocol.md), [firmware contract](firmware.md),
[validation](validation.md) and [recorded results](results.md).
