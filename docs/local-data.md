# Local data and cleanup

Git hosts original source, build manifests, documentation and redacted structured evidence. The evidence index lists original hashes and redactions. Private keys, signing passwords, BCD exports, full machine inventories, vendor binaries and raw transcripts are not published in this public repository.

After the hosted build and repository contents are verified, downloaded donor installers, extracted donor trees, redundant research packages and build-tool download archives can be removed from the local task workspace. They are reproducible from pinned inputs.

The working Deck's original lab directory remains local where its immutable trial files refer to it. Preserve the selected candidate package/public certificate, patched fallback package/public certificate, original Valve backup, original vendor catalog registration records and raw recovery trial records. Do not remove installed DriverStore packages, Windows catalog-database files or certificate-store entries as filesystem cleanup.

Keep a local cleanup receipt with exact paths, hashes/size totals and the hosted verification commit/run. Cleanup is conditional on successful hosting, not on merely having prepared a workflow. GitHub Actions artifacts expire after 90 days; the source can rebuild them, while emergency recovery stays available offline.
