# Windows Deckup

Windows driver work for the **LCD Steam Deck (Valve Jupiter)**. This repository keeps each driver project separate, with shared build tooling and a record of what actually worked on hardware.

| Project | Status | Scope |
| --- | --- | --- |
| [APU](drivers/apu/README.md) | Configuration-only ASUS adaptation verified on one Deck | Modern AMD graphics, normal Windows boot, sleep/resume |
| [Embedded controller](drivers/ec/README.md) | 0.2.0 prototype; telemetry and brief fan test passed | Twelve-field EC telemetry and experimental controls; documentation and redacted evidence |
| [Ambient light sensor](drivers/light-sensor/README.md) | Planned | Identify the sensor/ACPI interface and expose Windows sensor functionality |
| [Native controller](drivers/controller/README.md) | Planned | Research a native Windows controller driver and input integration |

## APU result

ASUS **32.0.21043.21001** (ROG Xbox Ally RC73YA, released 2026-07-20) runs on LCD GPU `PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE` with its **original executable files unchanged**. Two hardware-list INFs and the `amdgcf.dat` revision/checksum record are adapted; only the two affected installation catalogs are regenerated and locally signed.

On the tested Windows 11 build 26200 installation, a fresh boot with **Test Mode OFF and Code Integrity enabled** produced GPU Code 0 and working hardware rendering. Two S3 cycles passed on AC: **42 seconds** and **20 minutes 25 seconds**, each followed by another successful hardware rendering check. Earlier live driver reloads failed and an earlier Test Mode resume produced a black display. Those failures remain documented; these results do not prove the cause or universal compatibility. See [results and chronology](drivers/apu/docs/results.md).

## Build an APU artifact

Open **Actions → Build LCD APU package → Run workflow**. The workflow also runs when APU/build tooling changes on `main`. It downloads the exact ASUS donor from ASUS, verifies its SHA-256 and publisher, emulates the original checksum/revision routines, generates the AE configuration, regenerates/signs the two adapted catalogs, and uploads **`deckup-apu-32.0.21043.21001-config`**. No driver is installed on the runner or your Deck by a build.

Download and extract the artifact to obtain the driver package, original vendor catalogs, public setup certificate, hashes, staging/verification helpers, and the historical lab suite. **`Stage.cmd` stages only; it does not activate or reload the GPU.** Read [installation and recovery](drivers/apu/docs/installation.md) before using the helpers. The original guarded lab installer is retained with its original machine assumptions; it is not a general installer for every Deck.

Artifacts are retained for **90 days**. Source, manifests, documentation and redacted evidence are permanent Git history; rebuild an artifact when needed. An artifact's fresh local setup certificate is not a Microsoft production signature for the adapted package. The ASUS executable signatures remain original. Secure Boot/Memory Integrity variants and anti-cheat compatibility are not established by this experiment.

## Repository layout

- `drivers/<project>/`: implementation, manifests, installation tools, docs and evidence for that device family.
- `tools/`: shared pinned-download/build infrastructure and publication checks.
- `docs/`: architecture, research conventions and local data retention.
- `.github/workflows/`: separate workflows per driver project and source validation.

[Architecture and contribution conventions](docs/architecture.md) describe how new driver work fits into the repository. The EC project's locally built prototype and partial hardware validation are documented under `drivers/ec/`; its implementation and build workflow have not yet been imported. Sensor and controller projects remain planned.

## Licensing

Original project tools are [MIT licensed](LICENSE). AMD/ASUS/Valve/Microsoft binaries and third-party build tools retain their own licenses. Donor binaries are fetched during builds, not committed as open-source code. Generated artifacts contain vendor-derived files; MIT does not grant rights to those files. See [third-party materials](docs/third-party.md).
