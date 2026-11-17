# Security

Use [GitHub private vulnerability reporting](https://github.com/kosbushe/stroka/security/advisories/new) for security reports and [Issues](https://github.com/kosbushe/stroka/issues) for ordinary bugs. Response times are not guaranteed during the beta. Do not place secrets, private messages, remote-control URLs or personal caches in a public issue.

The standard edition uses App Sandbox, hardened runtime, outgoing network access, optional local-network serving, and user-selected read-only files for logo import. Feed fetches require HTTPS, reject insecure redirects, cap received bodies at 5 MB, and limit concurrency to four. The XML parser does not resolve external entities, stops at forty accepted items and rejects oversized fields. These limits reduce resource exposure; they are not a claim of a complete penetration test.

Phone Remote is optional and off by default. It binds only to a private IPv4 LAN interface. Its random URL is a bearer secret. Local HTTP has no TLS; use only a trusted network, disable it when finished, and do not expose the listening port to the internet. The implementation caps eight active connections, 16 KB total request data, 4 KB action bodies and an eight-second connection lifetime. Disabling it cancels connections; old instances cannot apply delayed commands after reenabling. Full phone-to-Mac security acceptance remains a release gate.

This app is not a screen locker, emergency alert system or guaranteed real-time financial terminal. Never disable Gatekeeper or other macOS security protections as an installation instruction. Public direct distribution requires Developer ID signing and notarization; store distribution requires an appropriate Xcode archive and App Store Connect validation.
