# What we published and cleaned up on October 6, 2026

This is a record of our original workspace cleanup. It is not a cleanup procedure for your Deck. For practical advice about backups and removable downloads, read [what to keep when cleaning up](../../local-data.md).

This directory archives the one-off workspace publication and cleanup code for transparency. It is historical task code, **not a portable installer or a general cleanup command**. Do not run it from a repository checkout. The original script required exact local proof files, an explicit workspace allowlist and an exact verified commit; those machine-local inputs are intentionally not published.

The repository and fresh GitHub artifact were verified before deletion. Artifact digest and all 151 driver-file hashes, six original catalogs, public-certificate hash and ZIP CRC passed. The final source tree had 195 hosted files before this maintenance appendix. The cleanup verified 432 retained driver/recovery files and both original public certificates, then removed 1,364 reproducible/cache files totaling **7.966 GiB**.

The selected configuration driver, patched fallback, original Valve backup, immutable runtime workers/trial records, public certificates, registered vendor catalogs and original SDK SignTool were retained. Windows DriverStore, catalog database, certificate stores and boot settings were not changed. Post-cleanup identity, normal-mode Code Integrity, exact kernel/configuration hashes, automatic kernel signing policy and actual AMD hardware rendering passed.

`archive-scaffold.py` records the initial import/scaffolding code; later build/workflow corrections are in Git history. `cleanup.ps1` records the narrowly scoped deletion code. `cleanup-receipt.json` uses workspace-relative paths; original unredacted receipts and private recovery records remain local.
