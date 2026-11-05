# Reporting implementation and acceptance tracker

Current scope: shot information and script-supervisor reporting. The November 5, 2026 product decision supersedes the older Revision 6 plan's asset-processing features.

| Area | Current implementation | Remaining acceptance / work |
| --- | --- | --- |
| Platforms | SwiftUI iPhone/iPad/Mac and Kotlin/Compose Android/Windows | Physical devices, lower Android APIs, Windows 10/11 and arm64 |
| Complete report | Project/crew, camera/media metadata, recording, lens, measurement and take fields | Original school-form parity and conditional requirement rules |
| Fast logging | Per-camera next take, string slates, defaults, unique load IDs and flags | Typed measurement/rate validation and real field-day testing |
| Script supervision | Circle takes and separate continuity/editorial/camera/DP notes | Attributed corrections, richer continuity tags and attachments |
| Preferences | Profiles, detail level, positions and appearance | Custom field schemas and richer requirement policies |
| Durability | SQLite WAL/FULL snapshots, prior snapshot, active selection, stale-save protection | Physical power-loss, low-storage and 12-hour offline tests |
| Handoffs | Schema-1 packages, CRC/SHA-256, additions/conflict preview, cross-reader fixtures | Full three-way conflict resolution, scoped/encrypted handoffs |
| Outputs | Landscape multipage PDF, CSV and HTML with long-note continuation | Exact supplied form parity and output template versioning |
| History | Per-entry snapshots, change history and recoverable deleted takes | Richer before/after provenance and recovery UI |
| Scale | 1,000-entry round-trip fixtures | End-to-end entry/search latency on physical devices |
| Branding/demo | Original SP mark and independent shared The Last Light sample | Final visual checks across supported platforms |
| Distribution | Existing alpha channels and signed-update verification | Exact new build acceptance, signed native upgrade/relaunch and authorized publication |

Past release validation is recorded in [VALIDATION.md](VALIDATION.md). It is not evidence that a new build or every physical platform has passed.
