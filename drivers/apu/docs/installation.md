# Installation and recovery

The hosted APU artifact contains `WT6A_INF/`, `original-catalogs/`, `certificate.cer`, `manifest.json`, `Stage.cmd`, `Verify.cmd`, source helpers and the historical lab suite.

## Staging

Extract the whole artifact, then right-click `Stage.cmd` and choose **Run as administrator**. The helper verifies the exact LCD hardware and all package hashes, exports the currently selected display package for offline recovery, verifies/registers the unchanged Microsoft vendor catalogs, trusts the artifact's public setup certificate and stages the adapted INFs using `pnputil /add-driver` without `/install`. It records every operation in `local-recovery/`. It does not bind, reload, reboot, toggle Test Mode or create a recovery timer.

This staging helper is new portable tooling. Its code/package checks are automated; it has not been used to replace the working driver on the original Deck. Staging is not activation. The artifact must not advertise successful hardware installation merely because a CI build passes.

## Activation and validation

The **tested activation path** is the original deferred-selection lab protocol in `lab/NORMAL-MODE-BOOT.txt`, including its known working patched fallback and one-time SYSTEM guard. That original suite assumes the recorded package paths, OEM INF numbers and GPU instance from the experiment. A fresh Deck needs its own detected device/INF values, verified staged/shared files and recovery plan; do not run the historical mutation scripts unmodified.

The lab showed that live display replacement could hang/produce Code 43. Its corrected helper selected a cached DriverStore INF for a restart, after verifying 132 staged files and 56 shared system files, using `DI_NOFILECOPY`, `DI_DONOTCALLCONFIGMG` and `DI_NEEDREBOOT`. Suppressing copies is valid only when those files already match; it is not a safe shortcut for an arbitrary fresh installation. A general fresh-machine guarded activation helper is future work.

`Verify.cmd` is read-only. It checks the GPU, live Code Integrity and exact selected kernel/configuration hashes. For actual rendering, run `python lab/src/verify_d3d11_hardware.py --output rendering.json` after a boot or wake. The Python probe requests D3D feature levels 11_1/11_0; it does not report the adapter's maximum capability.

## Recovery

Keep the exported original display package offline. Keep the original Deck's private candidate/fallback packages, public certificates, stock backup and frozen trial files where their recorded paths expect them. The patched prototype requires Test Mode and its local certificate; do not select it for a Test Mode OFF boot. Catalog database entries used by the unchanged normal-mode kernel must remain registered.

The old SYSTEM watchdog is retired after the successful boot. No recurring monitor runs. A future guarded trial needs a new explicit preparation; the guard's 180-second window starts when its startup process runs and can begin before login. It cannot recover a complete kernel hang. No installation helper here claims anti-cheat compatibility or a Microsoft production signature for the adapted INFs/configuration.
