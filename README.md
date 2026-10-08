# Windows Deckup

This project is working on better Windows support for the **LCD Steam Deck**: newer graphics drivers, access to its fan and battery hardware, automatic brightness, and controller support.

It is an independent community project. Some parts work on our test Deck; others are still research. This is not a finished driver pack or a Valve-supported installer.

## Where to start

| What you want | Where to go | What is available today |
| --- | --- | --- |
| Newer AMD graphics drivers | [APU installation guide](drivers/apu/docs/installation.md) | A downloadable experimental package and a helper that prepares it for installation. General activation instructions are still being developed. |
| Fan and battery features | [Embedded controller project](drivers/ec/README.md) | Prototype results and developer documentation. No public driver download or source yet. |
| Automatic screen brightness | [Light sensor project](drivers/light-sensor/README.md) | Planned; no driver yet. |
| Controller support in Windows | [Controller project](drivers/controller/README.md) | Planned; no driver yet. |

These projects target the LCD model. OLED support has not been established.

## What works so far

The graphics project adapts ASUS driver **32.0.21043.21001**, released July 20, 2026, for the LCD Deck. It changes the supported-device information and one configuration file while keeping ASUS's executable driver files unchanged.

On one Windows 11 Deck, that configuration ran with **Test Mode off**, rendered through the AMD GPU, and passed two sleep-and-wake tests. Live driver replacement has also failed, and a separate black-screen issue is being investigated. Successful tests are useful evidence, not a promise that every Deck will behave the same way. [Read the results and known issues](drivers/apu/docs/results.md).

The embedded controller prototype read twelve hardware values and briefly raised the fan speed, then returned it to automatic control. Longer tests and recovery checks are still needed. Its implementation has not been uploaded here.

## Downloading or building

For graphics, start with the [installation guide](drivers/apu/docs/installation.md). It explains how to download a GitHub Actions artifact, what the included helpers do, and where the current installation process stops.

Want to build the package yourself? Use the [APU build guide](drivers/apu/docs/build.md). Artifacts expire after **90 days**, but the source and pinned download records let you build another copy.

Building a package does not install a driver. Preparing a package does not activate it. Windows has given us several steps here; the guides explain each one.

## For contributors

Each device project has its own folder under `drivers/`. Shared tools live in `tools/`, and GitHub workflows live in `.github/workflows/`. See [how the repository is organized](docs/architecture.md), [common terms](docs/glossary.md), and [what to keep when cleaning up](docs/local-data.md).

The original test scripts are preserved as a [lab archive](drivers/apu/lab/README.md). They contain settings specific to our test machine and are not general installation instructions.

## License

Our original tools and documentation use the [MIT license](LICENSE). Vendor driver files and external build tools keep their own licenses. This repository does not turn the ASUS driver into open-source code; it publishes the tools and research used to adapt it. See [third-party materials](docs/third-party.md).
