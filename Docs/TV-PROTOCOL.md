# Local TV state protocol, schema 1

Mac is the source; the Android TV client is a read-only receiver. Both use the same trusted private LAN. HTTP is unencrypted: never forward the listener or publish codes/capability URLs.

1. User enables Settings > Television. The listener binds to a private IPv4 interface and shows its address/port and six-digit code.
2. Receiver POSTs JSON containing the displayed code to /pair with Content-Type application/json. The code expires after ten minutes, allows one pairing and is rate limited.
3. Successful response contains statePath with a fresh random read capability. Keep it in private app preferences, disable backup, never log it.
4. Receiver GETs this path sequentially every five seconds. Response limit: 512 KB. Redirects are rejected.
5. State contains schema, serverTime, brand, style (news/night/minimal/glass), edge (top/bottom), height, clock, date, language, timeZone, separator, rounded, playing, reducedMotion and rows. Rows contain title, kind, speed and items. An item contains id, text and optional expiresAt in Unix seconds.
6. Expire items locally between polls using serverTime plus monotonic elapsed time. A null expiry denotes original offline/authored content. TV heights use density-independent units; rendering is platform-specific.
7. Hide on connection loss/screen-off; stop polling and animation when stopped. Sharing off, replacement code and Mac quit revoke the session. Re-pair after replacement/restart. TV capabilities cannot invoke phone control commands.

Source of truth: Sources/TVBridge.swift and TVCompanion/src/ru/bushe/strokatv. This protocol can support later receiver ports; it is not a Windows implementation or public cloud API.
