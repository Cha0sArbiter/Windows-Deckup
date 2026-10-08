# Windows driver terms, in plain English

| Term | What it means here |
| --- | --- |
| APU | The AMD chip containing the Deck's processor and graphics hardware. This project's APU work concerns its graphics driver. |
| EC / embedded controller | The small hardware controller that manages things such as fan and battery settings. It is separate from the graphics driver. |
| Artifact | A downloadable ZIP produced by a GitHub Actions build. It contains the built package, rather than just source code. |
| Donor driver | The ASUS package used as the starting point for our adaptation. |
| Configuration-only | Device lists and a configuration record are changed; executable driver files stay unchanged. |
| INF | A text file telling Windows which devices a driver supports and how to install it. |
| Catalog / CAT | A signed record of file hashes that Windows uses to check a driver package. |
| Driver Store | Windows's managed collection of driver packages. A package can be stored there without being selected for a device. |
| Staging | Adding a package to the Driver Store for later use. It does not necessarily change the active driver. |
| Activation / binding | Selecting a package for a device. Starting its driver is a further check; selection alone does not prove it works. |
| Test Mode | A Windows boot setting used for test-signed driver development. The older patched APU prototype needed it; the newer configuration worked on our test Deck with it off. |
| Code Integrity | Windows's checks on code and driver signatures. |
| Code 0 / Code 43 | No reported device problem / Windows stopped the device because it reported a problem. Code 0 does not prove that a physical screen is displaying an image. |
| Hash / SHA-256 | A file fingerprint used to confirm that a file matches the expected version exactly. |
| Readback | Reading a setting after writing it. This confirms the reported value, but may not prove the hardware's physical behavior. |
| S3 sleep | The traditional sleep mode used in the recorded Deck tests. |
| UMDF | Microsoft's framework for drivers that run in user mode. The local EC prototype uses it. |

Return to the [project overview](../README.md), [graphics instructions](../drivers/apu/docs/installation.md), or [EC project](../drivers/ec/README.md).
