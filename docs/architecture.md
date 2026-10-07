# Project structure

Each `drivers/<project>/` owns its device IDs, build inputs, source, installation policy, documentation, tests and evidence. APU-specific offsets or revision/checksum logic must not become shared assumptions for EC, sensors or input. Use shared `tools/` only for downloads, hashing, package validation and publication hygiene.

New projects should begin with `README.md`, device discovery evidence, a versioned manifest, reproducible read-only probes and a design document. Add implementation and a separate build workflow after the device interface and requirements are understood. Do not infer LCD and OLED equivalence.

For EC work, document the actual ACPI/HID/firmware interfaces and ownership before writing controls. For ambient light, discover how Windows exposes the existing sensor and how it should integrate with the sensor stack. For native controller work, determine the actual Deck input reports and intended Windows APIs before choosing a driver model. These are research tasks, not completed designs.

Record build checks separately from hardware results. A build cannot verify sleep, input latency, battery use or anti-cheat. Evidence must distinguish the selected package from a running kernel, and offscreen rendering from working panel output. Use UTC in machine records and state the timezone in human timelines.

Version-pin donors and tools. Refuse unknown hashes or layouts. Keep proprietary executables and signing private keys out of Git; strip local user paths and per-machine identifiers from published logs. Preserve original hardware reports locally where recovery needs them.

The initial APU `lab/` import preserves the tools actually used, including hard-coded instance/INF values and frozen trial manifests. Modern reusable tooling lives outside that historical directory. Never rewrite a live recovery worker or its frozen dependencies merely to reorganize the repository.
