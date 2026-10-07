# Building and signing record

These instructions describe the existing local 0.2.0 prototype layout.
Its source and scripts have not yet been imported into this repository, so
these commands cannot be run from the current `drivers/ec/` documentation tree.
The pinned inputs are preserved in [toolchain-lock.json](../manifests/toolchain-lock.json).

The build targets x64 Windows 11 build 26100 or newer, using UMDF 2.33. It
contains no custom kernel-mode .sys and uses Microsoft's inbox WUDFRd.
The firmware guard limits hardware support to LCD EC B030, boards 06/0A.

## Dependencies

`toolchain-lock.json` pins the official downloads, byte counts and SHA256s:

- LLVM 20.1.8 Windows MSVC toolchain.
- Microsoft Windows SDK CPP / CPP x64 and WDK x64 10.0.26100.6584.
- VC 14.44 headers and x64 static CRT library payloads from Microsoft's
  Visual Studio channel. Internal VC folder version: 14.44.35207.
- Python 3.11 or newer for preparation and decoder tests; Windows
  PowerShell 5.1 or PowerShell 7 for build/client scripts.

The dependencies are downloaded into a directory you choose, not installed
system-wide. The LLVM archive is about 940 MB; preparation also needs space
for verified archives and extracted headers/libraries. Licenses supplied with
those dependencies remain their respective licenses.

```powershell
python .\tools\prepare_toolchain.py --toolchain-root C:\BuildTools\DeckEc
.\Build.ps1 -ToolchainRoot C:\BuildTools\DeckEc
python .\tests\test_decoder.py .\build\DecoderTests.dll
.\Get-DeckEc.ps1 -SelfTest
```

The preparation helper hashes each input before extraction, validates archive
paths and supports `--offline` when the archives directory is populated. Its
download/extraction workflow has not been rerun from a completely empty
machine; the build itself was validated using the retained pinned inputs.

`Build.ps1` compiles the DLL, runs Microsoft INF verification and runs policy
tests against a fake EC backend. It builds a decoder test DLL using actual SDK
layout fixtures. All these tests avoid firmware access. Driver binaries land
in `package`; intermediate objects and test binaries land in `build` or the
explicit `-BuildDirectory`. Nothing is installed or trusted by a build.

The DLL enables GS, ASLR, DEP, high-entropy addressing and CFG. The PDB reference
uses a relative filename. Hardened compilation is not hardware validation.

## Local development signing

Create your own test signing key outside the source/release directory. The
existing signing helper expects encrypted `local-test.pfx` and `password.txt`
in the explicitly supplied directory. It verifies Microsoft's SignTool,
signs the DLL, runs Inf2Cat and signs the resulting catalog.

```powershell
.\Sign-Package.ps1 -ToolchainRoot C:\BuildTools\DeckEc `
    -PrivateSigningDirectory C:\Private\DeckEcSigning
```

This signs files only. It does not import certificates, alter boot policy or
install the device. A local test certificate and trust workflow are for local
development; distribute production binaries only through an appropriate
Windows driver-signing/release process. Do not distribute PFX files, passwords
or another developer's signing key.

`tools\Make-Release.ps1` creates an explicitly selected source archive and a
separate local test archive. It rejects private/signing/crash-dump files from
publication. Source archives do not contain third-party build dependencies.
