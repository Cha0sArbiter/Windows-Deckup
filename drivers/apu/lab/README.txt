Steam Deck LCD Driver Lab
========================

Local experiment prepared on 2026-10-05 for a Valve Jupiter LCD Steam Deck,
GPU PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE, Windows 11 build 26200.

Donor: ASUS ROG Xbox Ally RC73YA, driver 32.0.21043.21001.
ASUS package release: 2026-07-20. INF driver date: 2026-06-29.
Original Deck driver: 32.0.11002.3007, INF date 2024-06-06.

Current configuration-only trial
--------------------------------
Normal-mode boot and basic AMD hardware rendering PASSED on 2026-10-06.
Windows booted at 11:13:53 local time with oem56.inf, driver
32.0.21043.21001, device Code 0, live TestSigningActive=false, and Code
Integrity options 1 (enforcement enabled). The selected kernel SHA-256
matches the unchanged ASUS executable; amdgcf.dat matches the AE candidate.
At 11:21, D3D11 hardware clear/copy/readback passed 1024 pixels for each
of red, green, and blue. DXGI identified the actual rendering adapter as
AMD 1002:163F, subsystem 01231002, revision AE; no software fallback was
used. The probe requested feature levels 11_1/11_0, so its 11_1 result is
not a measurement of the adapter's maximum Direct3D capability.
The user stopped recovery. The SYSTEM watcher recorded Keep at 11:16:19,
removed its task, and exited. No normal-boot recovery guard is active.
Startup queries found no AMD/display errors or AMD Code Integrity
warnings/errors. Separate ACPI/WUDFRd and Defender events were preserved
in the diagnostic record. Two normal-mode S3 sleep/resumes now passed:
11:28:54-11:29:36 CDT (about 42 seconds) and 11:40:52-12:01:17 CDT
(20 minutes 25 seconds), both on AC with recorded power-button wakes.
The user confirmed display restoration after the first cycle and returned
to request verification of the second. After both cycles, GPU Code 0,
Test Mode OFF, exact kernel/configuration hashes and actual AMD hardware
rendering passed. Neither cycle had new System warnings/errors or signing
errors. Informational Kernel-Power event 40 names the Realtek USB GbE
controller before both sleeps, which nevertheless completed. That network
device was verified at Code 0 after the first cycle. These two results do
not explain the earlier black-screen resume or establish broad power-state
reliability. Battery sleep, inactivity recovery and anti-cheat are untested.
Evidence: normal-boot/1a369b9d-06b0-45f0-9a76-f54dca3ca4a7/.
config-trial-state.json now records NormalModeBootAndTwoS3ResumesVerified.
The package manifests remain immutable historical signing/build snapshots.
The working patched prototype and stock-driver backup are retained.

Preparation history
-------------------
On 2026-10-06 the user resumed testing. The preparation helper now verifies
132 staged main-package files for each variant and 56 shared system files,
resolves the exact DriverStore INF, and sets DI_NOFILECOPY for deferred
selection. The read-only checks and 24 protocol/state/integrity/process checks
passed. Selection runs in bounded child processes with native progress
logs. The same preparation launcher uses this correction. The subsequent
normal-mode boot result is recorded above.
The first corrected attempt completed both native selections, then falsely
reported failure while reading detached child exit status. The fallback
left the patched prototype at Code 0 with Test Mode ON. The wrapper now
retains the actual process handle and has explicit success/failure/timeout
checks. A fresh preparation retires that inactive failed guard only after
verifying the unchanged working prototype and next-boot Test Mode ON.

The 2026-10-05 normal-mode preparation was canceled after a Windows copy
error for ativvaxy_vcn3.dat. The file was present with identical hashes in
the prepared package and candidate DriverStore. Driver selection did not
complete and TESTSIGNING OFF was not reached. At 18:26 local time, an
administrator cleanup stopped the blocked preparation and removed the
one-time recovery task. Before/after checks verified the same working
patched oem50.inf, Code 0, exact patched kernel hash, live Test Mode ON,
and next-boot TESTSIGNING ON. No restart was requested. The user ended
testing for the day and chose to retain the patched prototype. That failed
attempt motivated the staged-file copying correction described above.
Evidence is in
normal-boot/b0aefb26-c5cd-46aa-82d2-ee29f426b1ea/cancelled-copy-failure.json.

Earlier preparation plan:
The user requested a normal-mode configuration-only boot trial. Its
helper selects the cached candidate for a deferred restart, verifies its
original kernel/configuration hashes, and then sets next-boot TESTSIGNING
OFF. A one-time SYSTEM watchdog restores Test Mode and the patched
prototype if the new boot is not acknowledged within 180 seconds of the
startup guard. NORMAL-MODE-BOOT.txt describes preparation, confirmation,
recovery, and limitations. This new authorized trial supersedes the
earlier decision below to hold normal-mode testing. Its successful boot
and basic rendering result are recorded above and in normal-boot/.

A user-requested guarded live reload completed on 2026-10-05. The candidate
was selected at 17:21 local time and reported Code 43. Its events reported
failure to release hardware during uninitialization and failure to create
the SOC Service Manager. Without a user acknowledgment, the SYSTEM watchdog
began rollback after about 180 seconds and requested restart. After the
17:25 boot, oem50.inf was verified at Code 0 with its expected patched kernel
hash and S3 sleep available. Test Mode remained ON at that time. The user confirms a
successful recovery. Both the watchdog task and minute-check automation
were removed. This was a failed live replacement, not a failed cold boot.
The user clarified that sleep/display-timeout wake failures predate this
candidate, so the earlier black-screen resume does not establish its cause.
GUARDED-RELOAD.txt and guarded-reload/active.json document the retired trial.
Another guarded trial requires preparation of a new one-time watchdog.

On 2026-10-05 at 15:23 local time, the configuration-only candidate was
installed and selected as oem56.inf (extension oem57.inf). The selected
DriverStore kernel matches the unchanged ASUS SHA-256, and amdgcf.dat
matches the AE candidate. Automatic kernel-signature verification passes.
The live switch reported Code 43 and the user reported a black screen.
After the 2026-10-05 15:33 local boot, the candidate reports Code 0 and the
user confirms that the display works. At 15:48, an offscreen hardware-only
D3D11 clear/copy/readback check passed all three colors, without a software
fallback. The unchanged kernel and AE configuration hashes were verified
again, and automatic Microsoft kernel-policy signature verification passed.
The candidate then failed its display-resume test: Windows recorded a
sleep/resume cycle and the GPU still reported Code 0 with a passing
offscreen rendering check, but the user reported a black screen.
Win+Ctrl+Shift+B did not recover it; restarting restored the display.
The cause is not established. The previously working patched prototype
was reselected as oem50.inf with its expected kernel hash. The live switch
reported Code 43. After the 16:40 local restart it reports Code 0, S3 sleep
is available again, and the user confirms the Sleep option returned.
TESTSIGNING remained ON at that time. The normal-mode trial was on hold.
No automatic restart was scheduled. config-trial-state.json then recorded PrototypeRestored.
The older
installation-state.json records the previously verified patched prototype.
The prototype package and its trust certificate are retained as a fallback.
The restored prototype was running at that time. Do not disable Test Mode
if that patched kernel is selected again. The failed candidate evidence
is preserved alongside the subsequent normal-mode boot result.
src/Apply-ConfigTrial.ps1 -Mode Check verifies the first Test Mode boot
without requiring administrator elevation; selection/recovery still do.
Restore-Prototype.cmd reselects the working patched prototype for a Test Mode
restart. Rollback.cmd reselects the backed-up stock display driver; trial
packages/certificate/catalog cleanup is separate from that original helper.

Configuration-only research on 2026-10-05
---------------------------------------
A separate candidate changes the hardware-list INFs and amdgcf.dat while
preserving every ASUS executable byte-for-byte. Seven emulator checks
passed with the unchanged kernel's checksum and revision-check code.
The original Microsoft-signed catalogs were registered using SignTool;
automatic kernel-policy signature verification now passes for the original
kernel. The subsequent first Test Mode boot and basic hardware rendering
passed, but the candidate subsequently failed display resume. The later
2026-10-06 normal-mode boot and rendering result are recorded above.
During that catalog research, the working driver and boot settings were
unchanged. The candidate has since been selected as described above.
See SIGNING-RESEARCH.txt for the findings, exact limitations, and next trial.
private-config-trial/, private-config-package/, and private-config-install/
are local vendor-derived artifacts and are excluded from the source archive.

Verified local results
----------------------
The patched 32.0.21043.21001 driver successfully started after a fresh
Windows boot on 2026-10-05. Plug and Play reports oem50.inf and problem
code zero. The installed kernel SHA-256 matches the signed patched file.
DxDiag reports no display problems, WDDM 3.2, and enabled hardware Direct3D.
A hardware-only D3D11 check passed GPU clear, copy, and pixel readback for
red, green, and blue textures before and after sleep.
Windows exposes S3 standby. One actual S3 sleep/resume cycle was recorded
by Kernel-Power and Power-Troubleshooter; the user reported normal wake.
After wake, the GPU still reported code zero and no recent graphics errors
were found. These observations establish a working prototype on this Deck,
not comprehensive compatibility across devices, games, or power scenarios.
Game stability, performance, video decoding/encoding, repeated or long
sleep cycles, battery behavior, and anti-cheat compatibility are untested.

What changed
------------
The following describes the patched prototype retained as fallback.
The current configuration-only candidate keeps this kernel byte unchanged
and instead adapts the AE configuration record and its checksum.

One byte in amdkmdag.sys at file offset 0x569B1 (RVA 0x56FB1):
  74 15 (conditional equality branch) -> EB 15 (unconditional branch).
This accepts the configuration record when the GPU device ID matches even
when its revision differs. The main and extension INFs add only the exact
Deck LCD AE hardware ID above. Configuration loading, checksum checking,
device-ID checking, cleanup, and normal function return remain in place.
This is experimental; matching a device ID does not establish complete
hardware compatibility or correct power/display behavior.

The community patch offset 0x56550 is incorrect for this specific driver.
This builder requires exact kernel and INF hashes plus instruction context.
It refuses unrecognized builds. It does not use community script source.

Checks completed before installation
-----------------------------------
- ASUS download SHA-256 matched its official catalogue.
- ASUS installer publisher signature was valid.
- Six patch safety tests passed.
- Six emulator cases executed the actual AMD comparison-loop code:
  original AF passed, original AE failed, adapted AE passed, AF still
  passed, and both lower/higher mismatched device IDs still failed.
- Microsoft Inf2Cat reported no errors or warnings.
- Kernel and six catalogs were signed with a locally generated test cert.
- A hash manifest covers every file in the prepared driver package.
- Private signing key files were removed after signing.
- The existing display driver package was copied and hashed in backups/.

Build checks alone do not prove graphics performance, video acceleration,
sleep/wake, battery use, panel behavior, or anti-cheat compatibility.
The runtime observations above are separate tests on this actual Deck.

First live activation on 2026-10-05 failed with device Code 43. The old
driver logged a failure to release hardware during the live switch; both
old and new drivers then reported "Create SOC Service Manager failed."
Automatic fallback selected the original driver, which also retained
Code 43. A subsequent fresh boot with the new driver already selected
cleared the initialization failure, as recorded above.

Install and restart
-------------------
Install.cmd launches the administrator helper. It verifies the hardware,
package, and backup; backs up BCD; trusts the local test certificate; stages
the driver; and enables Windows TESTSIGNING. It leaves the current display
binding in place until test-signing mode is active after restart.

A one-time task runs as the same signed-in user with administrator rights,
20 seconds after the next Windows sign-in. It removes itself before
attempting activation. It verifies the package again, binds the new driver,
and checks the reported GPU version and device error code. A failed start
attempts to restore the original driver. Windows may request another
restart. No restart is initiated automatically.

installation-state.json and logs/ record the actual result. Status
QueuedForRestart means the new driver is staged, not active. Activated
means Windows reports the new version with device error code zero; this
does not replace real game, video, and display tests.

If a failed live switch leaves hardware initialization broken, the local
operator may use src/Launch-Driver.ps1 -Mode SelectForRestart. This verifies
the package and backup again, selects the trial driver for the next boot,
and records TrialNeedsRestart. It accepts only a recorded ActivationFailed
state and device codes 0 or 43. It does not call the result a successful
activation, register another automatic retry, or restart Windows.
After a fresh boot, verify the actual device status and hardware rendering.
Fresh-Boot-Trial.cmd launches this mode with the normal Windows
administrator prompt. Wait for TrialNeedsRestart in installation-state.json
before restarting. A canceled Windows prompt does not select the trial.
Driver version, INF, and problem code are read from Plug and Play device
properties, because the immediate CIM driver snapshot can lag a live bind.

Rollback
--------
Run Rollback.cmd and approve the normal Windows administrator prompt.
It cancels pending activation, verifies and rebinds the original driver,
restores the prior test-signing setting, and removes the project certificate
from trust stores if the project added it. Restart Windows afterward.
Keep this directory in place until testing and rollback are finished.

If the original driver is selected but cannot start during live recovery,
Rollback.cmd records RollbackNeedsRestart and preserves test mode and the
certificate. Restart Windows, then run Rollback.cmd again to finish cleanup.

TESTSIGNING produces a Windows Test Mode watermark and may prevent games
with anti-cheat from running. Memory Integrity, Secure Boot, BitLocker,
and nointegritychecks are not changed automatically.

Project and licensing
---------------------
The original tools are MIT-licensed. AMD/ASUS binaries remain proprietary.
backups/, private-driver/, logs/, Windows tools, and private keys are not
part of the source-only project archive and must not be published as MIT.
Review applicable vendor terms and permissions before public distribution.
AMD restrictions are not removed by publishing a separate patch tool.

Source references
-----------------
https://www.asus.com/us/supportonly/rc73ya/helpdesk_download/
https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=us&model=RC73YA&cpu=&osid=52
https://github.com/otti83/apu_driver_test/blob/main/AMD_Driver_Analysis_Guide_EN.md
https://github.com/SuperSkypper/ally2deckV2
https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option
https://www.amd.com/en/legal/eula/amd-software-eula.html

Development
-----------
ERROR-INVESTIGATION.txt records the 2026-10-05 reload and resume analysis.
The same live-install error pair occurred with both ASUS variants; the
configuration-only black-screen wake occurred with Code 0 and no captured
graphics errors. The patched prototype's successful S3 wake remains a
positive result. The observed sleep intervals were not matched.
src/investigate_reload_errors.py traces the exact-build failure conditions.
src/compare_reload_variants.py compares package bytes, installation settings,
and emulated acceptance results without changing Windows.

Python build/test tools require Python 3.9 or newer. Install requirements.txt
for certificate generation, optional PE inspection, and instruction emulation.
Signing uses Microsoft SDK SignTool and WDK Inf2Cat.
All download/extraction/signing tools were staged locally in this workspace.
No globally installed SDK or AMD setup program was required.

Run safety tests: python -m unittest discover -s tests -v
Run hardware probe: python src/verify_d3d11_hardware.py --output result.json
Build with src/build_package.py using the exact manifest in manifests/.
Future donor drivers require fresh code analysis and a new manifest.
