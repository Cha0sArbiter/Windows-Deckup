# What to keep when cleaning up

Git stores our source, build records, documentation, and redacted test evidence. Private signing keys, passwords, complete machine logs, vendor downloads, and original recovery records stay local.

## Keep recovery available offline

Keep your working driver backup and any fallback package, public certificate, and recovery records needed for your installation. The APU staging helper places its export and operation log in `local-recovery` beside the extracted package. Do not delete that folder just because preparation succeeded.

On the original test Deck, the frozen lab files also refer to specific local paths. Those files and their required packages must stay where the recovery procedure expects them.

GitHub artifacts expire after **90 days**. The source can rebuild a package, but an offline backup is more useful when the screen is black and you need recovery now.

## What can be removed

After verifying that the source and built artifact are hosted correctly, redundant donor downloads, extracted research copies, and build-tool download archives can be removed from the task workspace. They can be recreated from the pinned inputs.

Record what was removed and which hosted commit/build was verified first. The [October 6 cleanup record](maintenance/2026-10-06/README.md) documents our original cleanup; its scripts are not general cleanup tools.

Do not treat Windows's Driver Store, certificate stores, or catalog database as leftover download folders. Removing their contents can break the installed driver. Filesystem cleanup and driver removal are separate jobs.
