import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import zipfile

base = Path(__file__).parent.resolve()
repo = base / 'Windows-Deckup'
original = base / 'outputs/steamdeck-driver-lab'
lab = repo / 'drivers/apu/lab'
with zipfile.ZipFile(base / 'outputs/steamdeck-driver-lab-source.zip') as archive:
    for name in archive.namelist():
        relative = Path(name).relative_to('steamdeck-driver-lab')
        target = lab / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(name))
for relative in ['src/Stop-FailedNormalBootPreparation.ps1', 'Stop-Failed-Boot-Preparation.cmd']:
    shutil.copyfile(original / relative, lab / relative)

def write(relative, content):
    target = repo / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content.strip() + '\n', encoding='utf-8')

def clean_text(value):
    value = value.replace(str(base), '[workspace]').replace(str(base).replace('\\', '/'), '[workspace]')
    value = re.sub(r'(?i)C:[\\/]Users[\\/][^\\/\s"<>]+', '[user-profile]', value)
    value = re.sub(r'(?i)(PCI\\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE)\\[^\s"<>]+', r'\1\\[device-instance]', value)
    value = re.sub(r'S-1-5-21-(?:\d+-){2,3}\d+', '[user-sid]', value)
    return value

def sanitize(value):
    if isinstance(value, str):
        return clean_text(value)
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, dict):
        return {key: sanitize(item) for key, item in value.items()}
    return value

records = []
for source in sorted(original.rglob('*.json')):
    relative = source.relative_to(original)
    if 'WT6A_INF' in relative.parts or 'backups' in relative.parts or any(part.startswith('protocol-test-') for part in relative.parts):
        continue
    value = json.loads(source.read_text(encoding='utf-8-sig'))
    target = Path('drivers/apu/evidence/2026-10-05-06') / relative
    write(target, json.dumps(sanitize(value), indent=2))
    records.append({'source': relative.as_posix(), 'published': target.as_posix(), 'original_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
for name in ['emulation-results.json', 'package-verification.json', 'kernel-analysis.json', 'signed-route-inspection.json', 'reload-path-trace.json', *[f'reload-path-trace-{i}.json' for i in range(2, 10)]]:
    source = base / 'work/driver-audit' / name
    if source.exists():
        target = Path('drivers/apu/evidence/2026-10-05-06/research') / name
        write(target, json.dumps(sanitize(json.loads(source.read_text(encoding='utf-8-sig'))), indent=2))
        records.append({'source': 'work/driver-audit/' + name, 'published': target.as_posix(), 'original_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
write('drivers/apu/evidence/2026-10-05-06/index.json', json.dumps({'schema':1, 'redactions':['local workspace/user-profile paths', 'GPU per-machine device instance suffix', 'user SID'], 'excluded':['driver binaries', 'private keys/passwords', 'BCD binary/text exports', 'DxDiag machine inventory', 'transcripts', 'synthetic protocol-test output'], 'records':records}, indent=2))
shutil.copyfile(original / 'LICENSE', repo / 'LICENSE')
write('.gitignore', '''
/.cache/
/build/
/local-recovery/
**/__pycache__/
**/protocol-test-*/
*.pyc
*.pfx
*.password
*.sys
*.dll
*.cat
*.exe
*.nupkg
*.zip
*.bin
drivers/apu/lab/private-*/
drivers/apu/lab/backups/
drivers/apu/lab/logs/
drivers/apu/lab/normal-boot/
drivers/apu/lab/guarded-reload/
''')
write('.gitattributes', '* text=auto\n*.py text eol=lf\n*.ps1 text eol=crlf\n*.cmd text eol=crlf\n*.cs text eol=crlf\n*.yml text eol=lf')
write('README.md', '''
# Windows Deckup

Windows driver work for the **LCD Steam Deck (Valve Jupiter)**. This repository keeps each driver project separate, with shared build tooling and a record of what actually worked on hardware.

| Project | Status | Scope |
| --- | --- | --- |
| [APU](drivers/apu/README.md) | Configuration-only ASUS adaptation verified on one Deck | Modern AMD graphics, normal Windows boot, sleep/resume |
| [Embedded controller](drivers/ec/README.md) | Planned | Investigate the Deck EC and Windows integration |
| [Ambient light sensor](drivers/light-sensor/README.md) | Planned | Identify the sensor/ACPI interface and expose Windows sensor functionality |
| [Native controller](drivers/controller/README.md) | Planned | Research a native Windows controller driver and input integration |

## APU result

ASUS **32.0.21043.21001** (ROG Xbox Ally RC73YA, released 2026-07-20) runs on LCD GPU `PCI\\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE` with its **original executable files unchanged**. Two hardware-list INFs and the `amdgcf.dat` revision/checksum record are adapted; only the two affected installation catalogs are regenerated and locally signed.

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

[Architecture and contribution conventions](docs/architecture.md) describe how new driver work fits into the repository. No EC, sensor or controller driver is implemented yet.

## Licensing

Original project tools are [MIT licensed](LICENSE). AMD/ASUS/Valve/Microsoft binaries and third-party build tools retain their own licenses. Donor binaries are fetched during builds, not committed as open-source code. Generated artifacts contain vendor-derived files; MIT does not grant rights to those files. See [third-party materials](docs/third-party.md).
''')
write('docs/architecture.md', '''
# Project structure

Each `drivers/<project>/` owns its device IDs, build inputs, source, installation policy, documentation, tests and evidence. APU-specific offsets or revision/checksum logic must not become shared assumptions for EC, sensors or input. Use shared `tools/` only for downloads, hashing, package validation and publication hygiene.

New projects should begin with `README.md`, device discovery evidence, a versioned manifest, reproducible read-only probes and a design document. Add implementation and a separate build workflow after the device interface and requirements are understood. Do not infer LCD and OLED equivalence.

For EC work, document the actual ACPI/HID/firmware interfaces and ownership before writing controls. For ambient light, discover how Windows exposes the existing sensor and how it should integrate with the sensor stack. For native controller work, determine the actual Deck input reports and intended Windows APIs before choosing a driver model. These are research tasks, not completed designs.

Record build checks separately from hardware results. A build cannot verify sleep, input latency, battery use or anti-cheat. Evidence must distinguish the selected package from a running kernel, and offscreen rendering from working panel output. Use UTC in machine records and state the timezone in human timelines.

Version-pin donors and tools. Refuse unknown hashes or layouts. Keep proprietary executables and signing private keys out of Git; strip local user paths and per-machine identifiers from published logs. Preserve original hardware reports locally where recovery needs them.

The initial APU `lab/` import preserves the tools actually used, including hard-coded instance/INF values and frozen trial manifests. Modern reusable tooling lives outside that historical directory. Never rewrite a live recovery worker or its frozen dependencies merely to reorganize the repository.
''')
write('docs/third-party.md', '''
# Third-party materials

The MIT license applies to original tools and documentation, not donor drivers, catalogs, configurations or Microsoft/7-Zip tools. The APU build downloads the ASUS donor from its official CDN and Microsoft SDK/WDK NuGet packages from NuGet. Downloaded tools are not included in the driver artifact; a staging helper fetches the pinned SDK tool when needed.

Sources and terms:
- [ASUS RC73YA support](https://www.asus.com/us/supportonly/rc73ya/helpdesk_download/)
- [AMD software terms](https://www.amd.com/en/legal/eula/amd-software-eula.html)
- [Windows SDK build tools](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools/10.0.26100.9169)
- [Windows WDK package](https://www.nuget.org/packages/Microsoft.Windows.WDK.x64/10.0.28000.2526)
- [7-Zip licensing](https://www.7-zip.org/license.txt)

Generated driver artifacts are vendor-derived experimental packages. Publishing project tools does not relicense vendor files or establish a supported Windows/Steam Deck product.
''')
write('docs/local-data.md', '''
# Local data and cleanup

Git hosts original source, build manifests, documentation and redacted structured evidence. The evidence index lists original hashes and redactions. Private keys, signing passwords, BCD exports, full machine inventories, vendor binaries and raw transcripts are not published in this public repository.

After the hosted build and repository contents are verified, downloaded donor installers, extracted donor trees, redundant research packages and build-tool download archives can be removed from the local task workspace. They are reproducible from pinned inputs.

The working Deck's original lab directory remains local where its immutable trial files refer to it. Preserve the selected candidate package/public certificate, patched fallback package/public certificate, original Valve backup, original vendor catalog registration records and raw recovery trial records. Do not remove installed DriverStore packages, Windows catalog-database files or certificate-store entries as filesystem cleanup.

Keep a local cleanup receipt with exact paths, hashes/size totals and the hosted verification commit/run. Cleanup is conditional on successful hosting, not on merely having prepared a workflow. GitHub Actions artifacts expire after 90 days; the source can rebuild them, while emergency recovery stays available offline.
''')
for project, title, scope in [('ec','Embedded controller','Discover the LCD Deck EC interfaces and investigate Windows integration.'), ('light-sensor','Ambient light sensor','Identify the actual sensor/ACPI interface and investigate integration with the Windows sensor stack.'), ('controller','Native Windows controller','Investigate the Deck input device/report format and design native Windows controller integration.')]:
    write(f'drivers/{project}/README.md', f'# {title}\n\nStatus: **planned; no driver implemented**.\n\n{scope}\n\nFuture source, manifests, documentation, tests and hardware evidence belong in this project directory. Shared build infrastructure belongs in `tools/`. Follow [repository conventions](../../docs/architecture.md).')
write('drivers/apu/README.md', '''
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
''')
write('drivers/apu/docs/results.md', '''
# Observed results

Device: Valve Jupiter LCD Steam Deck, `PCI\\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE`, Windows 11 build 26200. Times below are America/Chicago (CDT).

Donor: ROG Xbox Ally RC73YA 32.0.21043.21001, ASUS release 2026-07-20, INF date 2026-06-29. Original Valve driver: 32.0.11002.3007, INF date 2024-06-06.

| Date/time | Variant/test | Result |
| --- | --- | --- |
| Oct 5, initial live installation | One-byte patched kernel | Code 43; SOC-service/hardware-cleanup errors |
| Oct 5, fresh boot | Patched prototype in Test Mode | Code 0, hardware rendering passed |
| Oct 5, short S3 cycle | Patched prototype | User-confirmed working wake; rendering passed |
| Oct 5, 15:33 fresh boot | Original kernel + AE configuration, Test Mode | Code 0 and offscreen rendering passed |
| Oct 5, 15:50–16:19 | Configuration-only S3 resume | User-observed black panel; GPU stayed Code 0, offscreen render passed; restart restored display |
| Oct 5, 17:21 | Guarded live config replacement | Code 43; watchdog restored patched prototype via restart at 17:25 |
| Oct 5, normal-mode preparation | Configuration-only | File-copy prompt stalled; canceled before TESTSIGNING OFF |
| Oct 6, corrected preparation | Configuration-only | Verified staged/shared files, resolved DriverStore INF, suppressed redundant copy; wrapper exit-code bug corrected |
| Oct 6, 11:13:53 fresh boot | Configuration-only, normal mode | Code 0, Test Mode OFF, Code Integrity enabled; unchanged ASUS kernel hash |
| Oct 6, 11:21 | Actual AMD hardware D3D11 | Three 1024-pixel clear/copy/readback cases passed; DXGI 1002:163F, REV_AE |
| Oct 6, 11:28:54–11:29:36 | Normal-mode S3, AC | 42 seconds; power-button wake; user-confirmed display return; hardware render passed |
| Oct 6, 11:40:52–12:01:17 | Normal-mode S3, AC | 20m25s; power-button wake; user returned to request checks; Code 0 and hardware render passed |

No new System warnings/errors or Code Integrity errors were found during the two normal-mode sleep cycles. An information-level Realtek USB Ethernet power-transition message appeared before both; sleep nevertheless completed. Separate ACPI/WUDFRd and Defender startup events are preserved in evidence and were not attributed to the GPU.

The successful normal-mode kernel SHA-256 is `AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152`; the AE configuration SHA-256 is `7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717`. Live Code Integrity options were `1`; selected INF was `oem56.inf` (a machine-local name).

## What remains unknown

Two successful cycles on one Deck do not establish all power scenarios. Battery sleep, idle display restoration, longer/repeated cycles, game stability, performance, video acceleration, Secure Boot/Memory Integrity variants and anti-cheat compatibility remain untested. The older black-screen resume is unexplained; normal-mode success does not isolate Test Mode as its cause. Historical offscreen probes did not identify the actual DXGI adapter; the later normal-mode probes do.

The altered package is locally signed for installation, not Microsoft-certified as a Steam Deck package. The executable kernel's original Microsoft signature coverage is separate from the changed setup catalogs. Build manifests with `NormalBootVerified=false` are immutable pre-boot snapshots; observed runtime results are in the current evidence state, not rewritten into frozen build records.
''')
write('drivers/apu/docs/build.md', '''
# Build the configuration-only artifact

The GitHub workflow runs on a Windows runner. It downloads the exact donor, validates SHA-256 and the ASUS publisher signature, extracts only the display package, and runs the existing Unicorn checksum/revision emulator. It adapts the AE record and hardware-list INFs, renames the two changed package identities, regenerates the catalogs with Microsoft Inf2Cat, and signs only those two catalogs with a new build-local setup certificate.

All original vendor catalogs are retained. Every executable is compared with the donor again after signing. Private signing keys/password files are removed before artifact packaging. The public certificate and a complete file manifest are included. The runner's local trust/catalog registrations are ephemeral and do not change the Deck.

```powershell
python -m pip install -r drivers/apu/lab/requirements.txt
powershell -NoProfile -ExecutionPolicy Bypass -File drivers/apu/build.ps1
```

Local builds require a Windows administrator shell for build-host catalog registration. `-SourceDirectory`, `-SignToolPath`, `-Inf2CatPath` and `-SevenZipPath` can use already-downloaded, verified inputs. Their original source hashes remain checked. Defaults download pinned inputs under `.cache/`; output is `build/apu/bundle/`. A build refuses to overwrite an existing output directory.

The source-validation workflow runs Python safety tests, Windows PowerShell protocol tests and publication checks without hardware mutations. The APU build runs those checks and the seven donor emulator cases. A successful build does not validate installation, boot or sleep on another Deck.

Future donor versions require a new manifest and fresh kernel/configuration analysis. The pipeline does not silently substitute ASUS's newest package or reuse fixed offsets with an unknown hash. Signing certificate randomness means catalogs/certificates are not byte-reproducible across runs; the adapted configuration and unchanged executable hashes are reproducible.
''')
write('drivers/apu/docs/installation.md', '''
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
''')

toolchain = {
    'schema':1,
    'sdk':{'url':'https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/10.0.26100.9169/microsoft.windows.sdk.buildtools.10.0.26100.9169.nupkg','sha256':'6000c971fc9155052a8359779b30b6682c39e091664d83b3852c4702ab6d238e','prefix':'bin/10.0.26100.0/x64/','executable':'signtool.exe'},
    'wdk':{'url':'https://api.nuget.org/v3-flatcontainer/microsoft.windows.wdk.x64/10.0.28000.2526/microsoft.windows.wdk.x64.10.0.28000.2526.nupkg','sha256':'63c939fb5a79295bf40e941db592681272219b04edff095fe2f3d123e5579a90','prefix':'c/bin/10.0.28000.0/x86/','executable':'Inf2Cat.exe'},
    'sevenzip':{'url':'https://github.com/ip7z/7zip/releases/download/26.03/7z2603-extra.7z','sha256':'191894e6acb3647ffb69ce630479ff318523b2e2b9890aa7f05c1127c2e59b8f'},
    'sevenzr':{'url':'https://github.com/ip7z/7zip/releases/download/26.03/7zr.exe','sha256':'ad4c82fadcbdf93c03b4fc440f300509c7d60c5c2f4d183e35d9d70d6957037d'}
}
write('tools/toolchain.json', json.dumps(toolchain, indent=2))
manifest = json.loads((original/'manifests/asus-32.0.21043.21001.json').read_text())
manifest.update({'donor_url':'https://dlcdnets.asus.com/pub/ASUS/IOTHMD/Image/Driver/Graphics/50567/AMD_Graphic_DriverOnly_ROG_AMD_B_V32.0.21043.21001_50567.exe?model=RC73YA','donor_release':'2026-07-20','inf_driver_date':'2026-06-29','source_subdirectory':'Packages/Drivers/Display/WT6A_INF','configuration_sha256':'7ee54354831bbf267c590636ffffd95fca91ff5455578151fa657bd5f9162717','variant':'configuration-only'})
manifest.pop('patch')
write('drivers/apu/manifests/asus-32.0.21043.21001-config.json', json.dumps(manifest,indent=2))
print(json.dumps({'lab_files':len([p for p in lab.rglob('*') if p.is_file()]),'published_evidence_records':len(records),'repo':str(repo)},indent=2))
