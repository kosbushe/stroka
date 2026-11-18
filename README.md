# Stroka

### Your desktop. On air.

**Your sources. Your name. Your news channel.**

[Download the Mac beta](https://github.com/kosbushe/stroka/releases/tag/v0.24.2-beta.1) · [Русский](README.ru.md) · [Roadmap](ROADMAP.md)

![Stroka illustrated preview](assets/stroka-preview.svg)

Built for the hundred-open-tabs era. Stroka turns the edge of your Mac into a personal news channel: favourite publishers, public Telegram channels, market prices and messages of your own.

Put your name on it. Pick a look. Set the pace. Your world scrolls by while you get on with your day.

| Choose the signal | Make it yours | Find your rhythm |
|---|---|---|
| RSS, public Telegram, your watchlist and your own words | Your name or logo, four looks, a compact clock | One to four rows, top or bottom, with adjustable speed |

**Native macOS beta · Apple Silicon + Intel · Local settings · No account required**

## New in 0.24.2

- Smoother transitions on large feeds, with cached text and source records.
- A larger source picker with at least ten checkbox rows at the tested desktop size.
- Six neutral separators: three bars, two bars, a horizontal bar, dots, stars or a large circle.
- Optional **Keep windows clear of ticker** in Settings. The separately permissioned Stroka Windows helper fits ordinary windows above/below the strip; use desktop Fill/Zoom. Native Full Screen and fixed-size windows are excluded. [Details and limits](Docs/WINDOW-FITTING.md).

## What goes on your channel?

- **Your morning briefing.** Technology, AI, business, science, cinema, sport. Choose the publishers you actually want to read.
- **Your market glance.** Keep your watchlist nearby, with the source and update cadence attached.
- **Your next session.** Put a welcome message, a workshop prompt or your own announcements on your Mac.

A shared speed control sets the tempo; lower rows are a little faster by default. Height runs from **45 to 180 pt**. Name/logo on the left, time/date/weekday on the right, your selected feed between them.

## Pick. Personalize. Press play.

1. Choose feeds from the catalog or add an HTTPS RSS/Atom URL. For a public Telegram preview, type **@channel**.
2. Add your name and choose **News**, **Night**, **Minimal** or **Glass**.
3. Press **Start ticker**. Double-click the strip to reopen setup. Click or Space to pause.

Save a setup in **Settings → Saved settings** and come back to it later.

## Small strip. Plenty to choose from.

**550 feed URLs · 11 topics · 96 original bilingual offline messages · 4 looks · Up to 4 rows**

The catalog includes Russian and English feeds. These are feed endpoints, not 550 distinct publishers; availability changes. The last full recorded catalog check is from 14 November 2026.

News stays fresh: original publication time under 24 hours, or under 48 hours for highlights you explicitly star. Downloading, editing or translating a story never resets its age. Market data comes from Coinbase, MOEX and official CBR/ECB rates, with provider and cadence/delay labels. Not every quote is real-time.

## Where it runs

| Platform | What you can try |
|---|---|
| **Mac** | Beta **0.24.2 (34)**. Native AppKit/SwiftUI app, macOS 14+, Universal Apple Silicon/Intel. Optional on-device English-to-Russian translation needs macOS 15+ and prepared Apple language models. |
| **Android TV / Google TV** | Experimental **0.2.2** receiver for your Mac feed. Mac stays on; basic pairing/overlay tested on Philips Android TV 11 in receiver 0.2.1. [TV guide](TVCompanion/README.md). |
| **iPhone + autonomous TV** | [Experimental Lab](Labs/Ecosystem/README.md): common editor, QR/TLS pairing and a TV-owned source engine. iPhone build/device acceptance and full feature parity remain incomplete. |
| **Windows** | A future port direction. No Windows app is included. |

Settings, messages and caches stay local. There is no developer news backend, analytics or advertising SDK. Private Telegram subscriptions, social-account timelines and universal HDMI/DRM overlays are outside this beta.

## Download or build

The [latest GitHub prerelease](https://github.com/kosbushe/stroka/releases/tag/v0.24.2-beta.1) contains the Mac beta, experimental TV receiver and SHA-256 checksums. These are **locally signed prototype builds**, not notarized Developer ID releases or App Store/Google Play apps. Keep macOS protections enabled. Building from source is the supported developer route if your Mac refuses the downloadable beta.

Requires **macOS 14+**, Apple Command Line Tools and a compatible Swift/macOS SDK. No external Swift packages are required for the desktop app.

```sh
git clone https://github.com/kosbushe/stroka.git
cd stroka
zsh build.sh "$PWD/dist"
open "$PWD/dist/Stroka.app"
```

The default build is Universal and includes the optional window-fitting helper. Set `STROKA_WINDOW_FIT=0` to omit that direct-download-only helper. The main app stays sandboxed; the helper requires a separate user-approved Accessibility grant.

The default build is Universal. Use `STROKA_ARCHS=arm64` for Apple Silicon only. Configure your own `STROKA_SIGN_IDENTITY` for an owner's signing identity. The [TV guide](TVCompanion/README.md) covers Android SDK/JDK prerequisites and local installation. Never commit signing keys.

## Checks and evidence

```sh
python3 Scripts/check_release.py
STROKA_ARCHS="$(uname -m)" STROKA_DIAGNOSTICS=1 zsh build.sh "$PWD/qa"
zsh Scripts/verify.zsh "$PWD/qa/Stroka.app"
```

Core checks use isolated settings and fixture responses. Native GUI and live-network checks are separate: see [verification](Docs/FINAL-REVIEW.md), [height-45 update](Docs/HEIGHT-45.md) and [TV rendering evidence](Docs/TV-RENDERING-v0.2.1.md). Short animation samples are not a battery-life or all-day frame-rate guarantee. GitHub Actions checks the desktop source/build and shared Lab rules; inspect the actual workflow result before treating it as passed.

The autonomous-TV Lab has explicit [parity gaps](Labs/Ecosystem/Docs/PARITY.md) and [iPhone installation steps](Labs/Ecosystem/Docs/INSTALL-iPhone.md). An iOS source target is not a built IPA. Successful isolated TLS/QR tests are not full phone-to-TV acceptance.

## Rights, privacy and contributions

This is a **public source preview**, currently **without an open-source license grant**. Copyright is retained; see [LICENSE](LICENSE) and [source terms](LICENSE-DECISION.txt). Publishing this repository does not select MIT/Apache or grant rights to third-party news, logos, market data or translation. ZXing in the experimental Lab retains its own Apache 2.0 license.

Suggestions and bug reports can be filed in [Issues](https://github.com/kosbushe/stroka/issues). A Windows port and accessible, low-power rendering are welcome topics for discussion; contribution/source reuse terms must be agreed before code reuse. For vulnerabilities use [private reporting](https://github.com/kosbushe/stroka/security/advisories/new), not a public issue. See [Security](SECURITY.md) and [Privacy](Privacy.txt).

This is a beta repository, not a store launch. Signing/notarization, platform acceptance, provider terms, support operations and store metadata remain separate work.
