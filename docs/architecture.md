# How the project is organized

Each device gets its own project under `drivers/`. That keeps a graphics-driver workaround from quietly becoming an assumption in a fan, sensor, or controller driver.

| Folder | Purpose |
| --- | --- |
| `drivers/apu/` | Graphics package adaptation, build scripts, helpers, and test history. |
| `drivers/ec/` | Embedded controller documentation and prototype evidence; source import is still pending. |
| `drivers/light-sensor/` | Planned light-sensor and brightness work. |
| `drivers/controller/` | Planned native Windows input work. |
| `tools/` | Shared downloads, hashing, build tools, and publication checks. |
| `docs/` | Project-wide explanations and records. |
| `.github/workflows/` | Automated builds and source checks. |

## Adding a driver project

Start with a README explaining the goal, supported hardware, current status, and what a user can actually do. Add device-discovery evidence, a versioned manifest describing exact inputs, read-only probes, and a design document before adding hardware controls.

Keep device IDs, firmware assumptions, installation policy, tests, and evidence with that project. Add a separate build workflow once its source and build process are ready. Shared tools should handle common tasks such as verified downloads, rather than device-specific offsets or firmware commands.

For EC controls, establish who owns each hardware setting and how it returns to normal. For sensors, investigate Windows's sensor integration. For controllers, identify the input reports and intended Windows APIs before choosing a driver design. LCD and OLED support need separate evidence.

## Writing useful results

Say exactly what was tested and what happened. Separate a successful build from successful installation, a selected package from a running driver, and a rendered image in memory from a working physical display.

Record the hardware, firmware, Windows version, exact file hashes, and remaining limits. Use UTC in machine records and label the timezone in human timelines. A single passing test does not establish general sleep, performance, battery, or anti-cheat compatibility.

Pin download versions and hashes. Reject unknown file layouts. Keep proprietary executables, private signing keys, personal paths, and per-machine identifiers out of Git. Publish redacted summaries and keep originals locally when needed for recovery.

## Keeping the history usable

The [APU lab archive](../drivers/apu/lab/README.md) contains original machine-specific scripts. Keep those records intact; place new reusable helpers outside the archive. Do not reorganize a live recovery worker or its frozen dependencies.

User guides should lead with the goal and expected result, explain required terms, and say clearly when a command is historical or unavailable. Readers should not need to reconstruct a lab session to know what to click.
