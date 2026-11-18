# Source picker repair - 18 November 2026

The embedded row editor previously constrained the chooser to 640 x 520 pt. Telegram, translation and filter controls consumed nearly all the height, leaving approximately one publisher row visible.

The editor now opens at 820 pt wide, with height adapted to the visible screen up to 900 pt. Its publisher list has a minimum 400 pt viewport with 40 pt rows. The duplicate embedded heading is removed and language/translation/filter settings share a collapsed disclosure. Search, public Telegram insertion, source status and Save/Cancel remain available.

While checking the complete library, profiling also identified repeated reconstruction of the selected-source array inside the catalog sort comparator. Selection membership is now captured once as a URL set. Catalog feed values are shared, and publisher rows use their stable URLs as identifiers. The binding reads the same selection snapshot used to render the row.

## Installed acceptance

- Apple Silicon release 0.24.1 (33) built and passed deep/strict signature validation.
- The installed window visibly displayed 12 checkbox rows at once on the user's display.
- Opening the Publishers tab and toggling a selected source returned promptly in native UI checks.
- Removing one selection changed the count from 50 to 49. Cancel and reopening retained the original 50-source World collection.
- Saved settings compared equal across update and the cancelled edit, including the user's current World/Technology/Markets rows, speed, Minimal appearance and optional window-fitting setting.
- The independently permissioned window helper binary was byte-identical across this update.
- The desktop ticker was restarted after acceptance.

The repair is included in the 0.24.2 beta release. Raw process samples and private preference backups remain outside the repository. The count of 12 visible rows is a live observation at the tested window size, not a guarantee for every macOS text-size or display configuration.
