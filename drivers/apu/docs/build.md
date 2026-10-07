# Build the configuration-only artifact

The GitHub workflow runs on a Windows runner. It downloads the exact donor, validates SHA-256 and the ASUS publisher signature, extracts only the display package, and runs the existing Unicorn checksum/revision emulator. It adapts the AE record and hardware-list INFs, renames the two changed package identities, regenerates the catalogs with Microsoft Inf2Cat, and signs only those two catalogs with a new build-local setup certificate.

All original vendor catalogs are retained. Every executable is compared with the donor again after signing. Private signing keys/password files are removed before artifact packaging. The public certificate and a complete file manifest are included. The runner's local trust/catalog registrations are ephemeral and do not change the Deck.

The published bundle also changes the main INF's `CopyINF=amduw23e.inf` reference to its renamed `decklcd-config-extension.inf`. The historical lab package left the old reference and already had that original extension available from the prototype; a self-contained artifact needs the correct new filename. This packaging correction and its new setup certificate have build/signing checks, but have not been activated on the original Deck. Its running package remains untouched.

```powershell
python -m pip install -r drivers/apu/lab/requirements.txt
powershell -NoProfile -ExecutionPolicy Bypass -File drivers/apu/build.ps1
```

Local builds default to no build-host trust/catalog changes and verify the kernel against its explicit original vendor catalog. The CI runner uses `-RegisterVendorCatalogs` to additionally check automatic kernel-policy lookup; that option needs a Windows administrator runner. `-SourceDirectory`, `-SignToolPath`, `-Inf2CatPath` and `-SevenZipPath` can use already-downloaded, verified inputs. The exact kernel/INF/configuration source hashes remain checked; supplying an extracted source skips the outer donor archive/publisher check. Defaults download pinned inputs under `.cache/`; output is `build/apu/bundle/`. A build refuses to overwrite an existing output directory.

The source-validation workflow runs Python safety tests, Windows PowerShell protocol tests and publication checks without hardware mutations. The APU build runs those checks and the seven donor emulator cases. A successful build does not validate installation, boot or sleep on another Deck.

Future donor versions require a new manifest and fresh kernel/configuration analysis. The pipeline does not silently substitute ASUS's newest package or reuse fixed offsets with an unknown hash. Signing certificate randomness means catalogs/certificates are not byte-reproducible across runs; the adapted configuration and unchanged executable hashes are reproducible.
