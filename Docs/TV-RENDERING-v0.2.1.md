# Stroka TV 0.2.1 rendering review

15 November 2026. Installed and exercised on the owner’s Philips 65PUS8507/60, Android TV 11, 1920x1080 UI at 60 Hz, density 320. The owner confirmed noticeably smoother motion.

Text is now shaped on data/font changes and rendered into bounded 512-pixel bitmap tiles. One Choreographer clock advances all rows from elapsed frame time. Changes in speed and pause retain position; unchanged news polling does not restart animations or resize the window. Clock text changes only when the displayed minute/date changes. Service windows explicitly request hardware acceleration.

The installed APK retained the existing overlay permission and pairing data; its foreground service and visible overlay were verified. 22 Android address/capability checks and 11 timing/seam cadence checks passed. Local APK alignment and v2/v3 signatures validate.

Fresh old sample: 965 frames in roughly 16 seconds, one janky frame (0.10%), p95 5 ms, YouTube foreground. New sample: 993 frames in roughly 16 seconds, no janky frames or deadline misses, p95 5 ms, Stroka TV activity foreground. These foreground workloads differ. Do not use the historical cumulative 82.76% jank counter as a matched baseline or claim a numerical speedup from these samples. Glyph/phase jumps are not fully described by gfxinfo frame counters; owner visual feedback is recorded separately.

The bitmap cache trades a small bounded amount of memory for avoiding repeated glyph work. GPU/cache statistics and CPU samples depend on foreground video and are not battery-life guarantees. No all-day, all-apps, protected-video, sleep/wake or store acceptance claim is made. Repository publication remains on hold until the owner’s final TV acceptance and source-distribution decision.

Implementation guidance: [Android hardware acceleration](https://developer.android.com/develop/ui/views/graphics/hardware-accel), [rendering diagnosis](https://developer.android.com/topic/performance/issues/render).
