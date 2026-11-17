# Stroka TV - beta receiver 0.2.2

Companion for Android TV / Google TV, Android 8.0 (API 26) or later. This is an installable local test APK, not a Google Play release. APK signatures, Java compilation, address validation and Mac-side pairing/renewal/revocation were checked; installation, pairing and basic overlay were verified on the owner's Philips Android TV 11. Extended video/lifecycle acceptance remains open.

## Try it

1. Install `Stroka-TV-0.2.2.apk` on your own TV. For ADB installation, enable developer options, approve your Mac on the TV, and run `adb install -r Stroka-TV-0.2.2.apk`. Android 11+ wireless debugging may require `adb pair IP:PAIR_PORT` first. Older Philips firmware may expose network debugging instead. The device must supply its own IP/ports; do not guess them.
2. On the Mac: Stroka -> Settings -> Television -> Connect a TV -> Share my ticker with TV. Keep the Mac awake and on the same trusted home network. Enter its displayed address and six-digit code in Stroka TV, then Connect. A code is valid for ten minutes and one pairing.
3. On the TV: allow Display over other apps, return to Stroka TV and press Start. Open the TV app you want to watch. Use Stop in Stroka TV or its persistent notification to stop the overlay.
4. To revoke a connection, turn Mac TV sharing off, quit Stroka, or create a new pairing code. Re-pair after restarting Mac sharing.

Up to four rows, the four colour families, selected text, original-source expiry, top/bottom placement, date/time/weekday, pause and graduated speeds follow the Mac. Logos are not transferred yet; Glass is a flat dark approximation on TV. Height uses TV density-independent units, so its physical size differs from Mac points. The strip is partially translucent to preserve interaction with underlying apps. Remote keys stay with the underlying TV app. No boot auto-start.

Some TV apps and protected system/video surfaces can suppress overlays. HDMI inputs, all live TV paths and DRM apps are not guaranteed. AirPlay mirroring does not place a separate strip over TV-native apps. Actual Philips acceptance remains necessary.

## Local connection and privacy

The separate Mac listener binds only to a private IPv4 interface. Six-digit pairing has a ten-minute deadline and attempt limit; the resulting random session can only read the shared feed. It cannot use the phone remote's control API. Local HTTP is unencrypted: use a trusted home network, do not forward the port or share codes/session links. Pairing is not intended for public venue Wi-Fi.

TV stores only its Mac address and session capability in private app preferences, with Android backup disabled. Feed payloads stay in memory. No account, analytics, advertising SDK, screen capture, Accessibility service, camera or microphone. The service is user-started from the visible TV app; it polls sequentially every five seconds, hides the strip on network errors/screen-off and stops when asked. Expired items disappear even between polls. Mac's normal news limit is 24 hours, explicitly starred highlights at most 48 hours.

Android requires Display over other apps and a visible foreground service. Android 13+ also offers the notification permission. For public Play distribution the foreground-service special-use declaration, review, launcher assets, privacy/contact URLs and device testing are still required.

## Build

Use a JDK 17+ and official Android SDK Platform 35 / Build Tools 35.0.0. No Gradle or external app libraries are required. Generate an **external local debug** key with alias `androiddebugkey`, store/key passwords `android` (debug defaults). Do not commit keys. Run:

```sh
python3 build.py --android-jar /path/to/android.jar \
  --build-tools /path/to/build-tools/35.0.0 \
  --java-home /path/to/jdk/Contents/Home \
  --keystore /private/path/tv-debug.keystore \
  --output /path/to/Stroka-TV-0.2.2.apk
```

The script compiles resources and Java, converts DEX, aligns, signs and verifies the APK. The supplied APK uses a local prototype key; public distribution needs an owner's managed release key and store workflow. The current target is API 35 for this local prototype, not a claim that future store target requirements are satisfied.

Official references: [overlays](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#TYPE_APPLICATION_OVERLAY), [special permission](https://developer.android.com/reference/android/Manifest.permission#SYSTEM_ALERT_WINDOW), [foreground service](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use), [TV app setup](https://developer.android.com/training/tv/get-started/create).

The TV clock follows the Mac server clock and timezone. Network loss hides the strip; the TV screen explains that it is waiting for the Mac and sequential polling reconnects it when possible. Renewing the Mac code revokes the old session; re-pair and Start again. The first receiver preparation preceded device access; the later 0.2.1 test on Philips is recorded below. The 0.2.2 height update builds successfully but has not received a separate long physical-device run. See [acceptance steps](../Docs/TV-ACCEPTANCE.md) before making a compatibility claim.

## TV rendering update 0.2.1

The ticker now shapes text when content changes, caches bounded 512-pixel raster tiles and moves every row from one display-vsync clock. Speed/pause changes retain position. Clock text changes only when its displayed value changes; unchanged network polls no longer resize the overlay window. Hardware acceleration is explicitly requested for the service window.

Installed on the owner’s Philips 65PUS8507/60, Android TV 11, 1920x1080 at 60 Hz. Original 0.2.0 pairing and overlay were accepted by the owner; the owner confirmed noticeably smoother motion with 0.2.1 after restarting. The cumulative old gfxinfo showed heavy historical jank, but a fresh 16-second old-build sample was already 0.10% janky with p95 5 ms. Do not claim an improvement from historical counters versus a fresh sample. An active 16-second 0.2.1 sample recorded 993 frames, zero janky frames and p95 5 ms with the Stroka TV activity foreground. The fresh old sample used YouTube, so this is a bounded absolute result, not a matched-workload speedup claim. Longer video sessions remain to be accepted.

## Height update 0.2.2

The whole strip accepts 45-180 density-independent units for any row count. Removed the hidden per-row height floor; text adapts to lane height. The existing installed 0.2.1 session was preserved by the owner while this update was prepared.
