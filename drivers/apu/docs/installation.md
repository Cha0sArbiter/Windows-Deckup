# Install the graphics package

The installer prepares the package and selects it for your **next Windows restart**. You choose when to restart. It does not deliberately reload the running graphics driver, change Test Mode, or install an automatic recovery guard.

This is an experimental package for the **LCD Steam Deck**. The configuration has worked on our test Deck with Test Mode off. The new portable installer has software checks but has **not yet been tested by installing it on hardware**. Live driver replacement has failed in earlier experiments, and the docked black-screen issue is still being investigated. [Read the results](results.md).

## 1. Download the current package

1. Sign in to GitHub and open [Build LCD APU package](https://github.com/Cha0sArbiter/Windows-Deckup/actions/workflows/apu-build.yml).
2. Open a **successful build containing the new restart installer**. Scroll to its **Artifacts** section.
3. Download **`deckup-apu-32.0.21043.21001-config`**.
4. Extract the entire ZIP to a folder you can keep. Do not run helpers from inside the ZIP or move them away from the other files.
5. Open `manifest.json` in Notepad and confirm that it contains **`"InstallerSchema": 2`** and **`"SelectionPolicy": "DeferredRestart"`**. Older artifacts only stage the package; restarting after those does not complete installation.

The extracted folder includes `Stage.cmd`, `Verify.cmd`, `NextBootDriver.cs`, `manifest.json`, `certificate.cer`, `WT6A_INF`, and `original-catalogs`. The repository's source ZIP does not include the built driver. Do not mix files from different builds.

Artifacts expire after 90 days. If no current download remains, a maintainer can run the workflow again, or you can use the [build guide](build.md) to build a copy in your own fork.

## 2. Before you run it

Save your work and keep the original Valve driver available offline. The helper exports your currently selected driver, but a backup is not automatic recovery. If this experiment fails, restoring a driver may require an external display or Windows recovery tools.

Use a working display and an administrator account. The helper may download a pinned Microsoft SDK tool, so it needs internet access and disk space for its cache.

The installer checks the exact supported LCD GPU, verifies the package hashes, and exports your current graphics package. It registers the original vendor signing catalogs and trusts this build's public setup certificate in the local-machine Root and Trusted Publisher stores. These are persistent Windows changes. It then stages the packages and selects the graphics driver with a restart required.

## 3. Prepare and select the driver

1. In the extracted artifact folder, right-click **`Stage.cmd`** and choose **Run as administrator**.
2. Allow the Windows administrator prompt for the helper you chose to run.
3. Wait for **“Ready for restart.”** Read the result before closing the window.
4. Keep the **`local-recovery`** folder beside the package. It contains your exported driver and a dated record of the installation steps.

Success is recorded as **`ReadyForRestart`** in `staging-state.json` inside that recovery folder. The new package is selected for the next boot; do not count it as a working running driver yet.

If the helper reports an error, save the message and logs. Certificate, catalog, file, or selection changes may already have completed. A status of **`SelectionFailedNeedsInspection`** means selection may be partial. Do not restart as though installation succeeded or disable security settings to push past an error. There is no automatic rollback.

## 4. Restart Windows

After the helper reports **Ready for restart**, choose **Start → Power → Restart**. Use Restart rather than shutting down and turning the Deck on again, so Windows performs a full restart instead of a possible Fast Startup boot.

Windows should start the selected driver on that boot. There is no confirmation deadline, recovery timer, or scheduled watchdog. You do not need to run another activation command.

The helper leaves Test Mode as it found it. If Test Mode was already off, it remains off. If it was on, restarting does not turn it off. Do not assume this installer establishes compatibility with every Windows security configuration.

## 5. Verify after restarting

Double-click **`Verify.cmd`** in the same extracted folder. It checks the selected version, GPU problem status, expected kernel/configuration hashes, and whether Test Mode is off. It writes **`verification.json`** beside the helper without changing drivers or boot settings.

A passing report confirms those checks. It does not prove that the physical screen, games, or sleep work. Check the display yourself and report any failures with the verification result. If Test Mode remains enabled, the normal-mode verification fails even if the driver otherwise works; its report shows that setting separately.

Do not run verification before restarting and interpret it as proof of a successful new-driver boot. Windows may already report the new selection while the old driver is still running.

## If something goes wrong

The exported package is under `local-recovery/<trial>/original-driver`; the helper prints the exact location. Retain it and the logs. This release provides no automated recovery installer. Device Manager's **Roll Back Driver** may be available, but it is not guaranteed; recovery can require manually selecting or reinstalling your saved driver.

The older patched prototype requires Test Mode and its local certificate. Do not select that fallback for a boot with Test Mode off. Keep vendor catalog registrations needed by the unchanged kernel.

**Code 43** means the GPU failed to start. A black built-in screen can also occur while Windows reports a healthy GPU; those are different observations. See [known issues and results](results.md), including the dock-related investigation.

Secure Boot, Memory Integrity, and online games' anti-cheat compatibility have not been established. A locally trusted setup certificate is not Microsoft certification of this adapted package.

## Advanced: prepare without selecting

For developers who want the earlier staging-only behavior, run this from the extracted artifact folder in an administrator PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Stage-Package.ps1 -StageOnly
```

Its success status is **`StagedNotSelected`**. Restarting alone does not select that staged package. To use the normal install flow afterward, run `Stage.cmd`.

The optional developer rendering check, after a restart or wake, is:

```powershell
python lab/src/verify_d3d11_hardware.py --output rendering.json
```

It needs Python and requests Direct3D feature levels 11_1 and 11_0, rather than measuring the maximum supported feature level. The [original lab archive](../lab/README.md) remains a historical record, not this installer's instructions.
