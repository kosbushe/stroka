# Window fitting in the direct-download Mac build

The optional **Keep windows clear of ticker** switch is available in Settings and More settings. Start the ticker, enable the switch, then grant **Stroka Windows** Accessibility access in macOS. This grant is performed by the user, not by the application. No screen recording permission is needed.

The helper fits standard resizable windows of the foreground application within the selected display's visible area, minus the actual ticker height. A smaller overlapping window moves without shrinking if it can fit; a desktop-filling window becomes shorter. Activation and AX move/resize notifications trigger a debounced adjustment. There is no per-frame window polling. A two-second lifecycle/configuration check handles disable, quit and permission changes.

Desktop Fill/Zoom is supported. Native Full Screen and Split View spaces are deliberately excluded: macOS owns those layouts. The ticker does not intercept the green button or change its default behavior. Windows of fixed size, dialogs, minimized windows and windows primarily on another display are excluded. Applications may reject an AX resize or enforce their own minimum size; such windows cannot be guaranteed to fit.

Disabling the mode or stopping/quitting Stroka restores a window only if its bounds still match the last bounds applied by the helper. A user-arranged window keeps its current bounds. Ticker edge/height/display changes restore prior untouched bounds before applying the new reservation. Force-killing the helper cannot restore its in-memory history.

## Build and isolation

`build.sh` embeds `Contents/Helpers/Stroka Windows.app` by default. Set `STROKA_WINDOW_FIT=0` to omit it; the controls then explain that this capability is unavailable. The main application retains its existing App Sandbox entitlements. The separately launched helper is not sandboxed and has its own bundle identifier and Accessibility consent. It exposes no network endpoint, reads no window titles/content or keystrokes, and keeps restoration geometry in memory only.

The helper accepts only its fixed configuration path in the parent application's private container, validates the running owner PID/bundle path, limits the strip height, and derives available bounds from the selected real display. The configuration contains only enabled state, owner identity, display ID, edge, height and language. It contains no news, messages, tokens or source selections. The helper exits when its owner is absent. This direct-download capability is not an App Store acceptance claim. The Xcode target compiles the client but does not automatically bundle the helper.

Relevant Apple references: [App Sandbox restrictions](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox), [visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), [AX observers](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification), [Full Screen](https://support.apple.com/guide/mac-help/use-apps-in-full-screen-mchl9c21d2be/mac).

## Verification

The independent `Tests/WindowFitGeometryTests.swift` suite checks top/bottom reservations at 45/84/180 pt, Fill, smaller overlapping windows, unaffected windows, a second display with negative coordinates, reversible AX coordinates, and restoration eligibility. Live permission, real-app resize/Fill, restoration and helper load must also be checked on the installed build before calling the feature accepted.

Local validation on 18 November: 17 geometry checks passed; the Apple Silicon 0.24.0 (32) application and nested helper passed deep/strict signature validation and were installed with a rollback copy. The existing row selections, speed and style compared unchanged; only the opt-in fitting setting changed. The helper's fixed-container configuration and parent-bundle checks were exercised on the installed application. Configuration URL comparison uses normalized paths so differing file-URL directory hints do not incorrectly reject the parent.

Permission acceptance must use a normal manual launch from Applications. A launch under UI automation can attribute an access check to its already-authorized launcher, which does not demonstrate the installed application's own grant. System Settings may list both Stroka and Stroka Windows; verify the helper's permission, rather than assuming that granting the parent alone is enough. Never grant these switches automatically during acceptance.

The user enabled both listed permissions after a manual launch and confirmed that a normal window using Window > Fill stays above the ticker. In a short four-reading observation, the helper used 0-0.1% CPU and 16 MB reported memory. Restore-on-stop remains implemented but is not claimed as a separately completed live acceptance check in this session.
