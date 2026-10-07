# Source provenance and licensing

This records the provenance of the locally developed prototype. The current
repository update imports documentation, manifests and redacted evidence;
implementation source and scripts remain a separate future import.

Original Windows WDF implementation, control policy, decoder, C# clients,
tests, scripts and project documentation: MIT, copyright Deck EC contributors,
2026. The read-only implementation was developed earlier in this same project
and retained as a compatibility client, with its source-level decoder tests.

No Linux driver source, Valve firmware blob, DSDT dump, Microsoft SDK/WDK
headers, third-party DLLs or compiler payloads are included in the source
archive. This project uses Windows WDF APIs and method contracts inspected in
the target Deck's ACPI table. The WDF initialization/lifecycle patterns use the
documented Windows API; no Microsoft sample source was copied into the driver.

Research references:

- Andrey Smirnov / Valve's 2022 VLV0100 Linux driver proposal, GPL-2.0-or-later:
  https://lists.openwall.net/linux-kernel/2022/02/06/24
  Used to identify expected feature areas and compare method names. Its
  implementation is not incorporated. Several proposed methods are absent
  from the local BIOS.
- 2023 Valve/Collabora charge-level/rate patch, preserved by postmarketOS:
  https://gitlab.com/postmarketOS/pmaports/-/raw/ac668fe0ef86323e2473bb9a1b6836f3263560f7/device/testing/linux-valve-jupiter/0008-hwmon-steamdeck-hwmon-Add-support-for-max-battery-le.patch
  Used to cross-check names. Its generic charge-rate bound conflicts with
  this BIOS's explicit 250–2500 contract; this project follows the inspected
  firmware and labels the physical units unverified. No patch code copied.
- Handheld Companion's SteamDeck.cs, used earlier to identify B030 LCD boards
  06/0A and the board-06 charge-limit uncertainty:
  https://github.com/Valkirie/HandheldCompanion/blob/main/HandheldCompanion/Devices/Valve/SteamDeck.cs
  No raw-memory driver or register-writing implementation incorporated.
- Microsoft UMDF timer and synchronization documentation:
  https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdftimer/ns-wdftimer-_wdf_timer_config
  https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/using-timers
- Valve Steam Deck LCD specifications:
  https://www.steamdeck.com/en/tech/deck
  APU power is a separate 4–15 W specification, not the USB PD contract.

Protocol identifiers and observed hardware contracts are documented facts.
Future contributors must retain the notices and compatible licenses of any
third-party code they actually incorporate. This MIT license does not relicense
GPL code, Valve firmware or Microsoft's external build/runtime components.

The repository is independent of Valve; names identify supported hardware.
