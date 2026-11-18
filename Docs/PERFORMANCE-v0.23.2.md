# Mac ticker performance repair - 18 November 2026

Status: built, installed locally as 0.23.2 (31), and launched with the existing three-feed profile. The repair is included in the 0.24.2 beta release.

## Report and cause

The installed 0.23.0 ticker visibly stalled with three content rows. A live process sample showed repeated `rowRecord` searches and `Story.line` construction inside `streamWindow`. Each window formatted the entire feed; each headline then scanned that feed for its source record. This made preparation quadratic in the number of headlines and could block the main thread beyond the compositor's animation continuation.

## Change

- Cache each row's lines and source records until content, settings, translation, or editorial expiry invalidates them.
- Resolve a source record by dictionary lookup, preserving the first matching record for duplicate lines.
- Format only adjacent headlines needed to cover the viewport and the outgoing message.
- Include text revision in the stream key so metadata changes refresh an otherwise identical stream.
- Keep market quotes live, outside the content-line cache.

No source selection, row speed, or visual style was reduced to obtain the improvement.

## Verification

The regression fixture uses three independent synthetic Russian feeds of 600 headlines each, 12 stream transitions, a 1500 pt viewport, and the night broadcast style. It does not load private or live news.

| Preparation time | Previous algorithm | Fixed algorithm |
| --- | ---: | ---: |
| Total, 12 transitions | 8080.03 ms | 32.65 ms |
| Worst transition | 703.09 ms | 13.97 ms |

The fixture also checks text/source attribution, edited headlines, and 24-hour expiry. The fast regression limit is 100 ms for a single transition, not an FPS target.

Additional checks passed: 101 core checks, 19 separator/boundary checks, 20 graduated-speed checks, and 18 multirow checks. The multirow suite skipped its live animation acceptance subsection; the separate graduated-speed suite did verify all four rows moving on the visible desktop.

The normal Apple Silicon release bundle passed signature verification and was installed on the M4 Mac. The user's saved settings compared equal before and after restart. The three original feeds were visibly restored. In a 12-second live process observation after startup, CPU readings after the initial sample ranged from 0.3% to 5.9% of one core, averaging 1.95%, with 105-107 MB reported process memory. The earlier application had short CPU readings of 74.8-78.7%; these are observations of different live intervals, not a controlled CPU benchmark.

## Limits and rollback

Preparation timings measure synchronous text work, not display FPS or long-term power consumption. Other system load can still affect presentation. The live observation is short and does not establish a sustained 60 FPS guarantee. TV playback was not changed or tested in this repair.

A private rollback copy of the previous application and preferences was retained outside the repository. Raw process samples, preferences, and private backup files must stay outside published artifacts.
