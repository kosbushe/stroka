## 0.23.1 - 2026-11-15

- Strip height can be set to 45-180 pt for any number of rows. Removed the hidden 56 pt minimum for two rows. Compact presets remain available.
- Small-row text adapts to the selected total height. TV receiver 0.2.2 uses the same limits.

# Changelog

## TV companion 0.2.1 - 15 November 2026

- Installed on the owner’s Philips Android TV 11. Replaced long animated TextViews with bounded raster tiles and one vsync clock.
- Preserved text position and removed repeated clock/window layout updates. Explicit service-window hardware acceleration.
- Owner confirmed noticeably smoother motion. Short active sample: 993 frames, zero janky frames, p95 5 ms; workload/long-session limits are documented in Docs/TV-RENDERING-v0.2.1.md.

## 0.23.0 (29) - 15 November 2026

- Resumed the optional TV prototype under Settings > Television at the owner's request; physical Philips acceptance and repository publication remain pending.
- Hardened TV listener replacement, connection cleanup and revocation; expired capabilities cannot read a new session.
- Removed internal offline collection credits from exported TV text. Native TV clock follows Mac time; TV receiver reports waiting for connection and stops on overlay attachment failure.
- Built Android TV companion 0.2.0 with the existing external local test key. Android runtime/overlay acceptance has not been performed.
- Saved settings confirmation messages now follow interface-language changes.

## 0.22.3 (28) - 15 November 2026

- Moved saved setups from the toolbar to Settings > Saved settings; only Settings remains in the toolbar.
- Added explicit Save current settings, per-entry Load, a guided empty state and individual deletion with confirmation. Empty/duplicate names cannot create ambiguous saves.
- Preserved older sets and added optional source-language snapshots for new saves. Loading preserves interface language and playback state.
- Added isolated persistence/compatibility checks and native UI coverage for saving and loading.

## 0.22.2 (27) - 2026-11-14

- Finish the desktop release audit: simplify current documentation and verification scripts, hide deferred TV setup and keep four current ticker styles in the benchmark runner.
- Bind the optional phone remote to private IPv4, bound active connections/action bodies, close connections on disable and prevent stale instances applying commands after reenabling.
- Handle malformed repeated market-data columns without a dictionary trap. Harden diagnostic parser input errors.
- Repair stale catalog-count/visibility checks, add native translation and remote-revocation acceptance, a diagnostic-bundle guard and an explicit reproducible live-source checker.
- Replace one repeatedly unavailable catalog feed; saved user sources remain untouched.


## 0.22.1 (26) - 2026-11-14

- Show original offline collection text directly in all four ticker styles, without repeating the internal Stroka Collection label before each item.
- Apply the same behavior to stationary phrases and independent rows. Keep real-news source attribution, personal station branding and chosen separators.


## 0.22.0 (25) - 2026-11-14

- Expand discovery to 550 unique checked RSS/Atom/public Telegram feed URLs, 50 for each of 11 news topics. Distinguish AI from Technology within Content. Exclude duplicate feed bodies and stale/inapplicable candidates during curation.
- Show all 50 source cards when choosing a topic. Index catalog lookup by URL to avoid repeated linear searches as the catalog grows.
- Add a visible single-field Telegram flow to onboarding and row/content selection: @handle -> bounded public-preview lookup -> automatic name/language -> selected source. Handle network errors, unavailable/private previews, duplicates and cancellation. No credentials or bot token.
- Support bare t.me links and established short handles. Keep RSS names optional. Preserve row speeds and news expiry policy.


## 0.21.0 (24) - 2026-11-14

- Restored shared speed control on the main setup. Row speeds increase gently from top to bottom, including quotes, with position-preserving tempo changes.
- Added optional private-LAN read-only TV pairing and an installable Android TV companion prototype. Physical Philips acceptance remains open.
- Documented the Threads @bushe.life authorization dependency; no live Threads connection is claimed.


## 0.20.0 (23) - 2026-11-14

- Replace four compulsory onboarding steps with two screens: choose publisher cards, then preview and start. The previous four-step UI is excluded from production.
- Show six varied suggestions, discovery topics/search/language, Selected only, explicit Choose for me and progressive More sources. Discovery filters retain selected URLs.
- Build one personal feed from exactly the selected publishers. Markets, logo, translation and detailed appearance are optional; extra rows remain available after setup.
- Support optional custom-source names. Classify AI feeds under Technology so all catalog URLs remain discoverable.
- Complete visible four-row motion and pause checks after desktop unlock; short animation measurements are recorded separately.

## 0.19.0 (22) - 2026-11-14

- Introduce first-launch onboarding: Interests, Sources, Rows, Appearance. Multiple topics form an explicit personal publisher selection.
- Mix selected interests in one row or distribute every topic across up to four rows with optional markets. Explain missing-language/source selections instead of silently losing topics.
- Add Telegram/RSS input, source-language/translation choice, instruments, branding/logo, position and four-look preview before launching.
- Offer setup again when the first launch was interrupted; remember completion; offer Build my feed for an isolated, cancellable reconfiguration. Existing profiles are retained on upgrade.
- Persist topic names with each row and retain authored text. No network requests are started by a new profile before setup confirmation.
- Read About version from bundle metadata.

## 0.18.0 (21) - 2026-11-14

- Choose one to four rows with independent topics, publishers, public Telegram previews or authored messages. Any row can show the selected market instruments.
- Replace the second-row switch with a four-position row selector and a simple editor for each row. Keep common branding and clock across the entire strip.
- Share RSS downloads across rows by URL, retain row-specific language and topic filters, bound per-source caches, and keep original publication-time expiry.
- Adapt the minimum height to 84 pt for three rows and 112 pt for four, within the existing 180 pt maximum. Preserve legacy compact one/two-row settings.
- Label the custom source control Add Telegram or RSS.

## 0.17.1 (20) - 2026-11-14

- Define Stroka as a personal top/bottom desktop ticker in a project constitution, product description and brief.
- Put Top/Bottom on the setup screen. Remove full-screen/frame and other placement choices from public controls and menus.
- Confine legacy output requests to one horizontal edge strip, disable idle-start profiles, normalize saved placements and prevent free dragging.
- Preserve authored content, publishers, presets, languages and instruments.

## 0.17.0 (19) - 2026-11-14

- Replace the sidebar/gallery/inspector landing view with a single compact setup screen and live ticker preview.
- Keep four deliberate looks: News, Night, Minimal and Glass. Map saved legacy broadcast looks to the current set; preserve authored content and instrument selection.
- Choose content through a compact searchable Topics/Publishers sheet; own messages, source status, translation and optional filters remain available.
- Toggle a second market row and common currency pairs directly. Manage all saved crypto pairs alongside shares/indices/reference rates.
- Keep time, weekday and date in the right block, and station branding in the left. Glass uses rounded ends and a cached static gradient.
- Keep only Presets and Settings in the toolbar. Move display controls to More settings. Double-click returns to the simple setup without pausing.

## 0.16.0 (18) - 2026-11-14

- Limit feed downloads to four concurrent requests and 5 MB per received body; cancel obsolete collection/language requests.
- Refresh newly selected source languages immediately. Stop parsing large feeds after forty usable headlines and reject oversized individual fields.
- Use original publication dates. Atom `updated` alone is not a fresh publication; Dublin Core dates are supported.
- Show selected sources first, with load failures, eligible-headline counts and reasons for an empty ticker. Add search within the headline preview.
- Replace two broken catalog URLs with verified official Moscow news/economy feeds. Preserve saved user sources.
- Add feed reliability acceptance checks, clean source packaging, release documentation and a proposed CI workflow.

## 0.15.1 (17)

Double-click a live strip to reopen display settings without changing playback. Defer single-click pause until the double-click deadline. Preserve drag behaviour.

## 0.15.0 (16)

Keep six distinct broadcast looks, migrate legacy looks, narrow asymmetric station/clock blocks and clip moving text exactly at their seams.
