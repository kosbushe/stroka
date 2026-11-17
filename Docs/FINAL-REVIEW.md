# GitHub beta checkpoint - 17 November 2026

The owner has explicitly requested repository publication. Current source: Mac 0.23.1 (30), TV receiver 0.2.2, experimental Lab 0.3.1. Public source preview retains copyright without an open-source reuse grant. See the root README, LICENSE, ROADMAP and RELEASE-READINESS.txt. Historical publication holds below record earlier decisions, not the current repository request. Store and extended device gates remain open. Scoped height-45 checks passed: 42 compact, 48 desktop-edge, 25 setup assertions. The working installation was left untouched at the owner's request.

---

# Stroka 0.23.0 (29): saved settings and TV preparation

15 November 2026. Local beta; nothing published.

The toolbar now contains only Settings. The Saved settings section contains a visible Save current settings action, a clear empty state and named entries with Load. Deleting a single entry asks for confirmation and leaves the running configuration unchanged. Blank and duplicate names are rejected.

Existing set identifiers, names and settings are preserved in the same local storage. New saves additionally capture source language through an optional Codable field; older sets load without it. Loading preserves interface language, pause and stopped-output state, and persists the restored configuration immediately.

Validation for this change is recorded in the local Saved-settings-v0.22.3 review bundle. It includes isolated save/load/restart/legacy/deletion checks, English/Russian native previews and direct button checks in a separate synthetic profile. Production installation and existing preference preservation are verified separately.

The broader scored final audit belongs to [version 0.22.2](Release-audit-v0.22.2.md). Its live 550-source and animation measurements were not repeated for this settings-only update. Publication/license/support/signing and device-acceptance gates remain open as documented in RELEASE-READINESS.txt.

TV preparation: test connection is available under Settings > Television. Companion 0.2.0 compiles and its APK signature/alignment validate. Mac-side pairing, read-only snapshots, renewed-code sessions and revocation are checked locally. Android address validation runs separately. No physical Philips or Android emulator was available; overlay rendering, TV remote focus, video-app compatibility and lifecycle acceptance remain unverified. Repository publication is on hold at the owner’s request until the TV is tested. See TV-ACCEPTANCE.md.

Current local results: 505 Mac assertions and 19 TV-protocol assertions passed with no failures or skips; 22 Java address/capability checks passed. Mac 0.23.0 (29) was installed and its actual Settings and Television sheets were observed. TV sharing remained off. Every preexisting settings value, custom feed, saved set and interface language matched the preinstallation snapshot. Native button save/load/duplicate-name/cancel behavior was observed in a separate QA app. Physical TV and emulator acceptance remain pending.

TV update, 15 November: physical Philips 65PUS8507/60 installation, pairing and baseline overlay now work. Receiver 0.2.1 rendering changes were installed and the owner confirmed smoother motion. See TV-RENDERING-v0.2.1.md for the bounded measurement and remaining acceptance. Earlier “device unavailable” entries describe the preparation stage, not the current device status. No publication was performed.
