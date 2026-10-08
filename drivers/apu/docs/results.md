# Graphics driver results and known issues

The configuration-only driver booted normally and passed two sleep-and-wake tests on one LCD Deck. Live driver replacement has failed, and an internal-screen problem is still being investigated. These are separate observations; neither a successful build nor a healthy GPU status proves that the screen is working.

For user steps, see the [installation guide](installation.md). The details below preserve the test history, including failures.

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

## Internal screen and dock investigation — October 8

The user reported a black built-in screen after starting with a **Dell WD19 dock** attached. A restart showed the boot logo on the external monitor, while the built-in screen stayed black. Windows reported both display paths as active and the GPU as healthy (Code 0). Unplugging the dock after the failure did not immediately restore the internal screen.

A later sequence worked: boot with the dock disconnected, enter the firmware menu, continue into Windows, then connect the dock. Both screens worked. This establishes that the driver can run both displays; it does not yet prove which part of that sequence restored the panel. The user was unsure whether the backlight was lit during failure.

The failed and working Windows states had the same selected kernel/configuration hashes and active display-path settings. A startup ACPI/WUDFRd warning appeared in both, so that warning alone does not explain the difference. Windows also recorded a failed Fast Startup attempt before the working full boot; its role is unknown.

Black-screen wake behavior was reported before the driver change. Panel initialization or restoration is therefore being investigated separately from the live-reload Code 43 failure. Dock attachment, retained panel state, firmware-menu initialization, and boot type still need controlled comparisons. Plain undocked boot without entering the firmware menu has not yet been confirmed as a workaround.

Do not read the two successful sleep tests as a fix for all black-screen cases.

## What remains unknown

Two successful cycles on one Deck do not establish all power scenarios. Battery sleep, idle display restoration, longer/repeated cycles, game stability, performance, video acceleration, Secure Boot/Memory Integrity variants and anti-cheat compatibility remain untested. The older black-screen resume is unexplained; normal-mode success does not isolate Test Mode as its cause. Historical offscreen probes did not identify the actual DXGI adapter; the later normal-mode probes do.

The altered package is locally signed for installation, not Microsoft-certified as a Steam Deck package. The executable kernel's original Microsoft signature coverage is separate from the changed setup catalogs. Build manifests with `NormalBootVerified=false` are immutable pre-boot snapshots; observed runtime results are in the current evidence state, not rewritten into frozen build records.

## Portable restart installer

Installer schema 2 adds portable selection after staging: it discovers the exact GPU instance and published INF, resolves and checks the stored main package, then requests a deferred installation with normal file copying enabled. It leaves Test Mode unchanged and adds no recovery task. `Stage.cmd` reports `ReadyForRestart`; the user restarts Windows manually.

Software tests cover native ABI/flags, device-ID rejection, staged-file tampering, ambiguous or missing published INFs, and bounded child-process handling. This helper and its fresh-install file-copy path have not been hardware-tested. The earlier successful machine-specific no-copy trial remains the hardware evidence; it does not establish that the new installer succeeds on a fresh Deck.
