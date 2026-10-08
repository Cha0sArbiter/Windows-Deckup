# EC application protocol reference

For developers writing a client for the local prototype. This describes binary messages exchanged with the driver, not end-user commands. The driver and client source have not yet been imported. See the [EC overview](../README.md) and [design](design.md) first.

An IOCTL is a request sent to a Windows device driver. A handle is the client's open connection to that device. “Arming” explicitly permits a control on that connection; it does not change hardware by itself.

Device interface GUID: `7de31c3c-bbc9-478f-86ed-3659f7e28e01`.
The client enumerates this interface using SetupAPI and refuses paths that do
not identify `ACPI#VLV0100#`. Device ACL: administrators and SYSTEM only.
Use one read/write handle for arm, control, renewal and explicit recovery.
Arm state and fan ownership are associated with that handle, not a process ID.

All IOCTLs use METHOD_BUFFERED / FILE_DEVICE_UNKNOWN, little endian. Read
IOCTLs require FILE_READ_ACCESS; arm/control require both read and write.
Unknown IOCTLs, arbitrary method strings and arbitrary register addresses are
not accepted. Structures are defined in the local prototype's `src/protocol.h`; its implementation has not yet been imported into this repository.

| IOCTL | Hex | Input | Output |
| --- | --- | --- | --- |
| Snapshot V1 | 0x00226000 | None | 184 bytes; 10 readings |
| Capabilities | 0x00226004 | None | 64 bytes |
| Snapshot V2 | 0x00226008 | None | 216 bytes; 12 readings |
| Arm session | 0x0022E00C | 16-byte DECKEC_ARM | None |
| Control | 0x0022E010 | 24-byte DECKEC_CONTROL | None |

Each snapshot has Size/Version/Count/Reserved DWORDs, a 64-bit UTC FILETIME,
then 16-byte readings: field DWORD, signed NTSTATUS, uint64 value. A failed
field has value zero in the wire response; clients expose it as unavailable.
Snapshots are sequential, not atomic; the timestamp marks their start.
V1 version is 1, V2 version is 2. All reserved words must be zero.

Capabilities report implemented, hardware-validated and session-armed masks.
Firmware, board, fan ownership mode, requested RPM, remaining lease, last fan
restore status and allowed RPM/lease limits follow. Fan mode Unowned means
this driver does not own an override; inspect FSSR to establish the firmware
target. The query reads cached driver state and does not itself evaluate ACPI.

Arm structure: Size=16, Version=2, Features, Reserved=0. Feature bits are Fan=1,
ChargeLED=2, ChargeRate=4, ChargeLevel=8. An arm request replaces this handle's
mask. Removing Fan while this handle owns an override attempts automatic-mode
recovery. Unsupported bits/boards are denied before setters. Armed permission
ends with handle cleanup. Merely arming a feature does not invoke its setter.

Control structure: Size=24, Version=2, Operation, Value, LeaseMs, Reserved=0.

| Operation | Number | Value | LeaseMs |
| --- | --- | --- | --- |
| Restore owned fan / automatic | 1 | 0 | 0 |
| Manual fan | 2 | 2500–7300 RPM | 1000–5000 |
| Charge LED | 3 | 0–100 percent | 0 |
| Charge rate | 4 | Raw 250–2500 | 0 |
| Charge level, board 0A only | 5 | 50–100 percent | 0 |

Ordinary controls are rate-limited across the device to one attempt per 500 ms;
automatic fan recovery bypasses this limit. Snapshots are limited to one per
second after the previous completed sample. Clients should pace calls and
treat STATUS_DEVICE_BUSY as a failure requiring a later retry, not evidence
of a successful command. Control buffer lengths must match exactly.

The fan health timer checks FANC, target ownership/readback and nonzero RPM
after a two-second startup interval. It runs only while an override/recovery
is tracked, is not restarted by lease renewals, and stops acting in exit from D0 (leaving the working power state).
All callbacks use one passive WDF wait lock. A timer cannot bypass an ongoing
ACPI call, so recovery timing remains best effort.
