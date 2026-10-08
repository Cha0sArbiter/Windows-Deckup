# Newer graphics drivers for the LCD Steam Deck

The Deck's APU combines its processor and AMD graphics hardware. This project adapts an ASUS graphics package so the LCD Deck can use a newer Windows driver.

The current candidate is **32.0.21043.21001**. Its executable files are unchanged; the build adjusts the device lists and configuration needed for the LCD Deck's GPU revision. We call this the **configuration-only** package.

## Start here

- [Install and restart](docs/installation.md): the user guide, including recovery limits.
- [Results and known issues](docs/results.md): what worked, what failed, and what still needs testing.
- [Build your own package](docs/build.md): GitHub Actions and local developer builds.
- [Common terms](../../docs/glossary.md): explanations of staging, Test Mode, signing, and other Windows terminology.

The package targets **LCD/Jupiter**, GPU `1002:163F`, subsystem `01231002`, revision `AE`. The build and staging helper check this identity. OLED and other GPUs are not supported by these manifests.

## Current limits

The configuration ran on our test Deck with Test Mode off, and two sleep-and-wake tests passed. Live replacement of the running driver has failed. We are also investigating a black internal screen around docked boot and display restoration.

The downloadable bundle has build and signing checks. Its newest packaging fix and staging helper have not yet been used to activate it on the test Deck. A successful GitHub build is not a hardware installation test.

`Stage.cmd` prepares the downloaded package and selects it for the next manual Windows restart. It leaves Test Mode unchanged and installs no recovery task. This portable restart installer has software tests; hardware installation testing is still pending. Older artifacts contain the staging-only helper, so follow the current guide's version check.

## Research and evidence

- [Original lab scripts and their limits](lab/README.md)
- [Signing and revision research](lab/SIGNING-RESEARCH.txt)
- [Earlier reload and resume errors](lab/ERROR-INVESTIGATION.txt)
- [Redacted test records](evidence/2026-10-05-06/index.json)

The lab archive keeps the original experiments intact. Reusable build tooling is in `build.ps1`; the artifact helpers are maintained in `installer/`.
