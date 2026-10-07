# Observed results

Device: Valve Jupiter LCD Steam Deck, `PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE`, Windows 11 build 26200. Times below are America/Chicago (CDT).

Donor: ROG Xbox Ally RC73YA 32.0.21043.21001, ASUS release 2026-07-20, INF date 2026-06-29. Original Valve driver: 32.0.11002.3007, INF date 2024-06-06.

| Date/time | Variant/test | Result |
| --- | --- | --- |
| Oct 5, initial live installation | One-byte patched kernel | Code 43; SOC-service/hardware-cleanup errors |
| Oct 5, fresh boot | Patched prototype in Test Mode | Code 0, hardware rendering passed |
| Oct 5, short S3 cycle | Patched prototype | User-confirmed working wake; rendering passed |
| Oct 5, 15:33 fresh boot | Original kernel + AE configuration, Test Mode | Code 0 and offscreen rendering passed |
| Oct 5, 15:50–16:19 | Configuration-only S3 resume | User-observed black panel; GPU stayed Code 0, offscreen render passed; restart restored display |
| Oct 5, 17:21 | Guarded live config replacement | Code 43; watchdog restored patched prototype via restart at 17:25 |
| Oct 5, normal-mode preparation | Configuration-only | File-copy prompt stalled; canceled before TESTSIGNING OFF |
| Oct 6, corrected preparation | Configuration-only | Verified staged/shared files, resolved DriverStore INF, suppressed redundant copy; wrapper exit-code bug corrected |
| Oct 6, 11:13:53 fresh boot | Configuration-only, normal mode | Code 0, Test Mode OFF, Code Integrity enabled; unchanged ASUS kernel hash |
| Oct 6, 11:21 | Actual AMD hardware D3D11 | Three 1024-pixel clear/copy/readback cases passed; DXGI 1002:163F, REV_AE |
| Oct 6, 11:28:54–11:29:36 | Normal-mode S3, AC | 42 seconds; power-button wake; user-confirmed display return; hardware render passed |
| Oct 6, 11:40:52–12:01:17 | Normal-mode S3, AC | 20m25s; power-button wake; user returned to request checks; Code 0 and hardware render passed |

No new System warnings/errors or Code Integrity errors were found during the two normal-mode sleep cycles. An information-level Realtek USB Ethernet power-transition message appeared before both; sleep nevertheless completed. Separate ACPI/WUDFRd and Defender startup events are preserved in evidence and were not attributed to the GPU.

The successful normal-mode kernel SHA-256 is `AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152`; the AE configuration SHA-256 is `7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717`. Live Code Integrity options were `1`; selected INF was `oem56.inf` (a machine-local name).

## What remains unknown

Two successful cycles on one Deck do not establish all power scenarios. Battery sleep, idle display restoration, longer/repeated cycles, game stability, performance, video acceleration, Secure Boot/Memory Integrity variants and anti-cheat compatibility remain untested. The older black-screen resume is unexplained; normal-mode success does not isolate Test Mode as its cause. Historical offscreen probes did not identify the actual DXGI adapter; the later normal-mode probes do.

The altered package is locally signed for installation, not Microsoft-certified as a Steam Deck package. The executable kernel's original Microsoft signature coverage is separate from the changed setup catalogs. Build manifests with `NormalBootVerified=false` are immutable pre-boot snapshots; observed runtime results are in the current evidence state, not rewritten into frozen build records.
