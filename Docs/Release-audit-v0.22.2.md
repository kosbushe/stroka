# Final local review: Stroka 0.22.2 (27)

14 November 2026. Scope: the personal macOS desktop ticker and preparation of a clean repository candidate. No external publication was performed. Scores are an engineering/product assessment, not App Review approval.

## Ten-point assessment

| # | Criterion | Score / 10 | Evidence and remaining limitation |
|---|---|---|---|
| 1 | Product focus | 9 | Top/Bottom desktop ticker, four styles, one to four rows. Deferred TV removed from normal settings; resizing other applications is not implemented. |
| 2 | First launch and setup | 9 | Publisher selection, preview, confirmation and selected queues verified. Settings, custom sources and presets survive reopening. Wider first-user research remains useful. |
| 3 | Design and readability | 8 | English/Russian, narrow layout, four distinct styles, asymmetric side blocks, seams, separators and clock reviewed. Full live dark-material/accessibility and external-display approval remain open. |
| 4 | Content and freshness | 9 | 550 distinct feed URLs, 50 per topic; 96 original bilingual offline items; original-date 24-hour expiry and explicitly starred 48-hour ceiling tested. Only 349 feeds currently had eligible daily items. |
| 5 | Source and Telegram setup | 9 | Single public @handle flow, title/language discovery, duplicates, failures and cancellation verified. Closed channels and social-network personal subscriptions are not supported. |
| 6 | Market data | 8 | Values observed from Coinbase, MOEX, CBR and ECB; malformed duplicate-column responses no longer trap. Provider cadence/delays differ and commercial display permissions remain an owner review. |
| 7 | Animation and resource use | 8 | Eight bounded animation scenarios; active CPU 1.30-3.92% of one core. No long display-link intervals in the samples. Long-session, energy, 120 Hz and physical Intel runs remain open. |
| 8 | Privacy and resilience | 9 | Sandbox, local preferences, optional private-LAN phone remote, bounded connections and old-key revocation verified. No credential-pattern matches in distributable text. This is not a penetration test or physical-phone acceptance. |
| 9 | Build and regression checks | 9 | 26 check invocations, 507 passing assertions, zero failures/skips, from the clean source build; live markets reported separately. Universal compilation does not replace Intel runtime coverage. GitHub-hosted CI has not run. |
| 10 | Public repository readiness | 7 | Clean sources, English/Russian README, constitution, changelog, privacy/security notes, build/check scripts and proposed CI supplied. Owner license and support decisions remain open; no open-source license was selected on the owner's behalf. |

**Overall: 8.5/10 for the local repository candidate.** App Store release is a separate gate, still open.

## Fixes made during this pass

- Hardened the optional phone remote: private IPv4 interface only; eight active connections, eight-second lifetime and bounded action bodies; pending connections canceled on stop; old server instances cannot apply delayed commands after reenabling.
- Made provider table decoding tolerate duplicate columns instead of terminating the process.
- Corrected stale diagnostic assumptions about the enlarged movie catalog and visible/reduced-motion window testing. Invalid parser-check input now reports usage instead of crashing.
- Added executable native translation and phone remote regression checks, diagnostic-bundle guards and correctly formed RSS/Atom fixture input in the verification script.
- Updated performance scenarios to the four current product styles, and added a reproducible public-source checker with compressed-response support and the app's native parser.
- Replaced one repeatedly unavailable catalog endpoint with Steve Blank's entrepreneurship feed. Saved custom feeds are not replaced.
- Hid deferred television setup from the normal settings flow. No TV installation or physical-device testing was performed.
- Corrected version, eighteen-choice content counts, current row-speed behavior and translation evidence in the project and store drafts. Network user-agent version now comes from bundle metadata.

## Current test evidence

The initial diagnostic pass comprised 23 suites and 503 individual assertions. The final clean-build verification script executed 26 checks, including native RSS/Atom fixtures, live Telegram and market checks, with 507 passing assertions and zero failures or skips. It covers first-launch publisher selection, the simple setup screen, persistence, source limits, date-based eligibility, offline collections, 1-4 rows, top/bottom geometry, exact seam clipping, separators, row speeds, pause/resume, reduced motion, preview visibility and double-click setup access. A test assertion is not a distinct end-user journey.

The source report [Source-health-v0.22.2.json](Source-health-v0.22.2.json) records all 550 catalog URLs, public names, read counts and check times, without headline bodies or user caches. After transient failures were retried and one endpoint replaced, all 550 were readable. 349 had news eligible within 24 hours. Empty/stale feeds remain empty; original publication dates are never changed to make content appear fresh. These checks establish current availability, not continuous uptime, accuracy or permission to redistribute publisher content.

A synthetic English headline passed through actual Apple Translation into Russian on this Mac, retaining original text and publication date and reaching the selected ticker queue. Models were already available; no download was initiated. A human still needs to review translation quality on real editorial content.

The local phone-server check exercised anonymous/invalid requests, request bounds, a valid playback command, shutdown, connection cleanup and rejection of the old capability after reenabling. The link itself is never included in evidence. Phone Remote remains off by default, trusted-LAN HTTP only; a physical phone has not been accepted.

## Bounded animation measurements

Six measured seconds per scenario after warmup, Apple Silicon Mac, 1710 x 1107 logical screen, Retina scale 2, 60 Hz. CPU is process user + system time divided by wall time; 100% means one core. Fixture data; no live network in the measured process.

| Scenario | CPU, one core | Display-link p95 | Long intervals |
|---|---:|---:|---:|
| Four information rows | 1.76% | 16.67 ms | 0 |
| Three information rows + prices | 3.92% | 16.67 ms | 0 |
| News desktop strip | 3.44% | 16.67 ms | 0 |
| Glass desktop strip | 2.42% | 16.67 ms | 0 |
| Minimal desktop strip | 1.30% | 16.67 ms | 0 |
| Night desktop strip | 1.38% | 16.67 ms | 0 |
| Paused visible fixture | 0.72% | 16.67 ms | 0 |
| Hidden fixture | 0.51% | No callbacks | 0 |

These are callback-pacing measurements, not compositor-FPS, whole-system GPU/energy or battery-life guarantees. Paused/hidden fixtures and desktop strips have different window geometry. No claim of all-day, 120 Hz, external-monitor or physical Intel acceptance is made.

## Publication decision

A source review candidate is prepared locally. Select source-distribution terms and add a monitored support/security contact before public publication. Do not call the candidate open source while LICENSE-DECISION.txt is the only license-related file. Review publisher/market permissions for actual personal versus public/commercial display and translation use.

Public binaries and the App Store additionally need real support/privacy URLs, developer team, proper distribution signing, archive validation and the remaining device/accessibility/energy acceptance. Publication.json deliberately retains uncompleted fields. There is no repository URL, uploaded release, notarization ticket or App Review result to report.

The clean source built successfully as native diagnostics and as a Universal production app. Version 0.22.2 (27) was installed and visibly reopened from /Applications/Stroka.app. Both the prior installation and the new version closed normally without force termination. Every preexisting saved setting, added source, preset and interface-language value matched the preinstallation snapshot after restarting. The actual installed Russian light-mode control window was visually inspected; private settings and this capture are excluded from the repository candidate. Production signature, sandbox, hardened runtime, both binary architectures and absence of diagnostic entry points were verified. The verification script correctly rejects production bundles. The source archive and local validation bundle carry separate build/installation evidence; no actual user preference contents are distributed. Historical audit documents retain their original dates and are superseded by this review.
