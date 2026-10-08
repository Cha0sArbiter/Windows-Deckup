# Download and prepare the graphics package

**This is an experimental LCD Steam Deck package. The current helper prepares it but does not activate it.** A general installer with recovery protection is still being developed. If you want a complete install-and-reboot process, this release is not ready for that yet.

The configuration has worked on our test Deck with Test Mode off. The downloadable bundle includes a newer packaging fix and staging helper that have not yet been used for hardware activation. [Read the test results](results.md) before deciding to experiment.

## 1. Download the built package

1. Sign in to GitHub and open [Build LCD APU package](https://github.com/Cha0sArbiter/Windows-Deckup/actions/workflows/apu-build.yml).
2. Open a **successful** build. Scroll to its **Artifacts** section.
3. Download **`deckup-apu-32.0.21043.21001-config`**.
4. Extract the entire ZIP to a folder you can keep. Do not run the helpers from inside the ZIP or move them away from the other files.

The extracted folder should contain `Stage.cmd`, `Verify.cmd`, `manifest.json`, `certificate.cer`, `WT6A_INF`, and `original-catalogs`. Downloading the repository's source ZIP does not provide this built driver package.

Artifacts expire after 90 days. If no downloadable build remains, a repository maintainer can run the workflow again. To build your own copy in a fork, see the [build guide](build.md).

## 2. Understand what preparation changes

Right-clicking **`Stage.cmd` → Run as administrator** will:

- Check that your GPU matches the supported LCD Deck and that the package files match their recorded hashes.
- Export your currently selected graphics driver as an offline recovery copy.
- Verify and register the original vendor catalogs, which Windows uses to check the unchanged driver files.
- Trust this build's public setup certificate in Windows's local-machine Root and Trusted Publisher stores.
- Add the adapted packages to Windows's Driver Store, ready for later selection.

This makes persistent certificate and catalog changes. It leaves your currently selected graphics driver in place. It does not restart the GPU, reboot Windows, change Test Mode, or create a recovery timer.

The helper may download a pinned Microsoft SDK tool, so allow internet access and space for its cache. Keep a working display and your original driver available throughout any future activation test.

## 3. Run the preparation helper

1. In the extracted artifact folder, right-click **`Stage.cmd`** and choose **Run as administrator**.
2. Allow the Windows administrator prompt for the helper you chose to run.
3. Let it finish and read the result before closing the window.
4. Keep the new **`local-recovery`** folder. It contains your exported driver and a dated record of the preparation steps.

Success is recorded as **`StagedNotSelected`** in `staging-state.json` under that recovery folder. That means preparation succeeded and your previous driver is still selected.

If it stops with an error, save the message and the recovery log. Some earlier steps may already have completed; the helper does not automatically undo every certificate or catalog change. Do not disable security settings or delete Windows driver files to push past the error.

## 4. Activation is a separate step

**There is no general activation helper in this release.** Stop after staging unless you have a device-specific test and recovery plan.

Our successful installation used a carefully checked, restart-based procedure on the original test Deck. Live replacement of the running graphics driver had hung or failed with Code 43. The archived procedure depends on that machine's driver names, files, and fallback package; it is not a set of commands to copy onto another Deck.

Developer details are in the [lab archive](../lab/README.md) and `NORMAL-MODE-BOOT.txt` inside it. The no-copy options used in that trial were valid only after checking that all required files were already present and correct.

## Checking an activated driver

After a separately planned activation, double-click **`Verify.cmd`**. It checks the selected driver version, GPU status, exact kernel/configuration hashes, and whether Test Mode is off. It saves **`verification.json`** beside the helper without changing the driver or boot settings.

If you run it immediately after staging while your previous driver is still selected, a candidate-verification failure is expected. It does not mean staging failed.

A passing report does not confirm that the physical screen works or that sleep is reliable. Those need separate observation. The optional developer rendering probe is:

```powershell
python lab/src/verify_d3d11_hardware.py --output rendering.json
```

Run it from the extracted artifact folder with Python installed. It requests Direct3D feature levels 11_1 and 11_0; it does not measure the GPU's maximum supported feature level.

## Recovery and known problems

Keep the exported original driver offline. An export is a backup, not an automatic recovery service, and this helper does not install a watchdog. A future activation test needs a separate recovery plan before changing the active driver.

The historical patched fallback requires Test Mode and its local certificate. Do not select that fallback for a boot with Test Mode off. Keep the vendor catalog registrations needed by the unchanged kernel.

If Windows reports **Code 43**, the GPU failed to start. A black built-in screen can also occur while Windows reports the GPU as healthy; those are different observations. See [results and known issues](results.md), including the dock-related display investigation.

Operation with Secure Boot, Memory Integrity, or online games' anti-cheat systems has not been established. A locally trusted setup certificate is not Microsoft certification of this adapted package.
