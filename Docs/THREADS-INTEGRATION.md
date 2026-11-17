# Threads - integration checkpoint

No Threads account is connected and no live posts have been imported in this build. Entering a handle alone is not authentication. Do not display a connected state or invent a user's feed.

First supported implementation path is the authorized account's own posts, using Meta's official Threads API and `threads_basic`. It needs an owner's Meta application, a registered OAuth callback and an actual user login. Store granted credentials in macOS Keychain, never in source, ordinary preferences, pasted chat messages or logs. A shipped desktop application must not embed a client secret; use an owner's managed confidential OAuth component if the provider requires one.

Public author discovery is a separate API permission, `threads_profile_discovery`. Meta's standard access is limited to its listed test profiles; arbitrary public author lookup needs advanced access/App Review. The documented public-profile conditions include at least 100 followers and a daily request limit. A public username or a sample-app test is not evidence that a requested author can be read. Check eligibility and approved permissions in the actual owner application before building a public-author UI. The API is not assumed to expose the user's personalized following/home timeline.

Once authorized, normalize posts into the existing source pipeline with original timestamp and permalink, source username, duplicate ID and original language. Apply the same 24-hour expiry (explicit highlights at most 48 hours), optional short-text rules and on-device translation. On permission removal/expiry show a reconnect state and discard expired posts. No scraping around login walls, private-profile access or silent publishing permissions.

Next blocked dependency: an owner's configured Meta application and an interactive login for the intended Threads account. Until these exist, RSS, public Telegram previews and own text remain the live content sources.

Official references checked during this session: [Meta Threads profiles](https://developers.facebook.com/documentation/threads/threads-profiles), [Meta sample application permission clarification](https://github.com/fbsamples/threads_api/issues/72). Recheck actual API endpoints and scopes at implementation time.
