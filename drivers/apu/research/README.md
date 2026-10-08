# Early graphics-driver research

For contributors studying how the adaptation was developed. These are exploratory tools, not user installation steps. Start with the [current installation guide](../docs/installation.md) or [repeatable build guide](../docs/build.md).

These original scripts preserve the ad hoc work used before the cleaned-up lab suite. They are research sources, not the supported package build entry point. Some assume the old task workspace paths or fixed disassembly locations. `download-assets.ps1` queried ASUS for its newest package at the time; the CI build instead pins an exact package/hash.

Original generated trace and signing-inspection records are in `../evidence/2026-10-05-06/research/`. Local vendor downloads, support-page caches and third-party community scripts are excluded; their referenced upstream URLs are recorded in the lab README. No community script is executed by the package workflow.
