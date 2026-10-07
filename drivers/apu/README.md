# LCD Steam Deck APU

The default build is the **configuration-only** ASUS 32.0.21043.21001 candidate. The vendor kernel and every executable remain unchanged. This project is pinned to LCD `1002:163F / SUBSYS_01231002 / REV_AE`; OLED and other GPUs are unsupported by these manifests.

- [Build instructions](docs/build.md)
- [Installation and recovery](docs/installation.md)
- [Results and chronology](docs/results.md)
- [Signing/revision research](lab/SIGNING-RESEARCH.txt)
- [Reload/resume error analysis](lab/ERROR-INVESTIGATION.txt)
- [Redacted structured evidence](evidence/2026-10-05-06/index.json)

`lab/` preserves the original setup, rollback, guarded live-reload and normal-boot suite and its tests. Its original paths, published INF numbers and device-instance suffix are historical machine assumptions, not portable defaults. Do not run those mutation helpers from a repository clone on another machine. One-off stopped-preparation cleanup scripts are historical and remain deliberately restricted to their old trial.

`build.ps1` automates reproducible package production; `installer/` contains staging and read-only verification helpers for its artifact. A CI build success proves package checks, not another Deck's hardware compatibility.
