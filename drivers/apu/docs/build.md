# Build the graphics package

This guide is for people who want to generate a package, rather than install one. Building does not change the Deck's active graphics driver. For downloading and preparing an existing package, use the [installation guide](installation.md).

## Build with GitHub Actions

1. If you maintain this repository, open **Actions → Build LCD APU package → Run workflow** and choose `main`.
2. If you do not have permission to run it here, fork the repository into your GitHub account, enable Actions in your fork, and run the same workflow there.
3. Wait for a successful run. Download **`deckup-apu-32.0.21043.21001-config`** from its **Artifacts** section and extract the entire ZIP.

The workflow also runs when the relevant APU build, installer, lab-source, manifest, or shared-tool paths change on `main`. Documentation-only edits do not trigger it. Artifacts remain available for 90 days.

## Build locally on Windows

You need Git, Python with pip, Windows PowerShell, internet access for the pinned downloads, and disk space for the driver and build tools. The workflow uses Python 3.12. Run these commands from the **repository root** in PowerShell:

```powershell
python -m pip install -r drivers/apu/lab/requirements.txt
powershell -NoProfile -ExecutionPolicy Bypass -File drivers/apu/build.ps1
```

The defaults cache APU inputs under `.cache/apu/` and shared tools under their own cache. The finished package is in **`build/apu/bundle/`**. The build refuses to overwrite an existing output directory. To keep a previous build, choose a new one:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File drivers/apu/build.ps1 -OutputDirectory build/apu-next
```

That build's package will be in `build/apu-next/bundle/`. The local build does not install a driver or, by default, add certificates or vendor catalogs to the build machine.

## What the build checks

The Windows workflow downloads the exact ASUS donor, verifies its SHA-256 fingerprint and ASUS publisher signature, and extracts the display package. It runs the original checksum/revision routines in an emulator, changes the configuration record for revision AE, and adapts the supported-device lists.

It regenerates and locally signs only the two changed installation catalogs. It keeps all original vendor catalogs and checks again that every executable matches the donor. Private signing keys and password files are removed before packaging. The artifact contains the public setup certificate and file hashes.

The bundle also corrects the main INF's `CopyINF` reference from `amduw23e.inf` to the renamed `decklcd-config-extension.inf`. The older hardware-tested package could find the original extension already on the test Deck. This fix makes the new bundle self-contained; it and the new staging helper have build checks but have not yet been activated on that Deck.

Source validation checks publication rules, Python safety tests, and Windows PowerShell protocol tests without changing hardware. The APU build adds seven donor-emulator cases. Passing these checks does not prove installation, boot, physical display output, or sleep on another machine.

## Advanced build options

`-SourceDirectory`, `-SignToolPath`, `-Inf2CatPath`, and `-SevenZipPath` let you supply existing inputs. The exact source kernel, INF, and configuration hashes are still checked. Supplying an extracted source directory skips the outer donor archive and publisher check.

Local builds check the kernel against its explicit original vendor catalog. CI additionally uses `-RegisterVendorCatalogs` to test Windows's automatic kernel-signature lookup. That option requires administrator rights and changes the build host's catalog database; CI uses an ephemeral runner.

A new donor version needs a new manifest and fresh analysis. The build does not silently download a different version or apply known offsets to an unknown file. Fresh signing certificates make the catalogs differ between builds; the adapted configuration and unchanged executable hashes remain reproducible.
