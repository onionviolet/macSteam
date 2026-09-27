# SFF Feature and License Audit

This is an engineering compliance review, not legal advice.

## Revisions and licenses inspected

- macSteam: local commit `9b18852`, [repository](https://github.com/onionviolet/macSteam), `LICENSE`. The license file contains GNU AGPL version 3. The older README label saying "AGPLV2" conflicts with the license text and should not be treated as authoritative.
- SteaMidra/SFF: commit [`fa44fc96b609c4cbe553e7e1e6ffd946de55b76f`](https://github.com/Midrags/SFF/tree/fa44fc96b609c4cbe553e7e1e6ffd946de55b76f), `LICENSE`, `docs/Third-party notices.md`, `sff/library_scanner.py`, `sff/backup.py`, and relevant user documentation. SFF's own code is GPL-3.0-or-later. Its bundled tools, data, and assets retain separate licenses and notices.
- Sparkle: resolved Swift package dependency, [repository](https://github.com/sparkle-project/Sparkle), MIT license. macSteam already depended on it before this work.

## Accepted product inspiration

SFF demonstrates that library discovery, backup retention, status reporting, logs, and settings management are useful adjacent jobs in a Steam utility. macSteam adopts those product-level ideas using independent AppKit and Swift implementations designed for macOS. No SFF source, bundled data, assets, or third-party binaries are copied or adapted.

## Rejected scope

SFF also includes depot and manifest acquisition, emulators, unlockers, DRM-removal tooling, bypasses, and other access-control circumvention. Those features, their operational documentation, and code paths are explicitly rejected. They are neither implemented nor used as design references here.

## Attribution decision

The audit records SFF because it informed feature selection. A third-party notice is not added for SFF because this work copies no SFF code or data and adds no SFF dependency. If later work copies or adapts material, bundles data, or introduces a dependency, its copyright and license notices must be preserved in `THIRD_PARTY_NOTICES.md` before merging.
