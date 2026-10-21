# VK Music as a full YAYMA source

## Current state

Branch feature/vk-audio-source contains only an MVP for manual audio replacement in settings. It is NOT a full VK Music integration: there is no separate VK session, catalog, search, playlists, or VK playback queue. Do not treat the existing replacement UI as a complete provider.

## Screenshot error: AppError.invalidToken()

This screen alone does not prove the issue is VK-related. It may be the current Yandex Music session token error. The VK token in the MVP is only used after opening the replacement dialog. Authentication errors must be handled per provider so a VK token cannot break Yandex startup or session state.

## Architecture

YAYMA uses Flutter UI and a Rust backend through Flutter Rust Bridge. Add VK as a separate provider; do not replace the Yandex client or mix their tokens.

### 1. VK authorization

- Add a dedicated Connect VK Music screen/dialog.
- Use a supported VK OAuth flow through the system browser/Custom Tabs and callback/deep link. Do not ask for a VK password in app fields or embed it in requests.
- Configure the OAuth client ID, redirect URI, and allowed scopes explicitly. Never commit secrets or attempt to bypass OAuth/CAPTCHA.
- Store VK credentials separately from the Yandex token using platform secure storage; never log tokens.
- Represent connected, expired, and reauthorization-required states, and provide disconnect.
- If official access to the audio API is unavailable for the chosen OAuth client, show a clear error instead of treating an unofficial token extractor as reliable authorization.

### 2. Backend provider

Add a Rust module src/rust/src/vk_music/ with separate types VkSession, VkTrack, VkArtist, VkPlaylist, VkApiError, and an HTTP client. Existing ApiService and yandex_music remain responsible for Yandex.

Proposed FRB functions, with final signatures adapted to existing DTOs and FRB code generation:
- vk_auth_status(), vk_disconnect()
- vk_search_tracks(query, page) and vk_search_playlists(query, page)
- vk_get_library_playlists(page) and vk_get_playlist(playlist_id, page)
- vk_get_track_stream(track_id), resolving the stream immediately before playback rather than persisting a temporary URL.

Every network call needs timeouts, bounded pagination, VK error parsing, and response validation before converting to DTOs.

### 3. Search and playlists

- Add a Yandex / VK / All source selector to search while preserving the existing screen and visual style.
- Add a VK library view with user playlists and paginated playlist contents.
- Internal IDs must include provider identity (for example vk:<owner_id>:<audio_id>) to avoid collisions with Yandex track IDs.
- Cover art, title, artist, and duration should be optional because API responses may omit fields.
- VK failures or offline state must not break Yandex search, library, or playback.

### 4. Playback

- Do not use the global manual URL replacement mechanism as the foundation of a full provider.
- Extend the current track model with source metadata or introduce TrackSource and TrackRef, preserving Yandex compatibility.
- The queue must store provider and provider-specific ID. On starting a VK track, resolve a fresh stream URL and pass it to the existing audio engine.
- Handle expiring URLs, stream re-resolution, request cancellation when switching tracks, and clear access/subscription errors.
- Prewarm, history, next-track behavior, system media controls, and notifications must use VK metadata. Yandex fallback is valid only for Yandex tracks, not arbitrary VK IDs.

### 5. Security and tests

- Never request or store a VK password.
- Never log access tokens, callback URLs containing tokens, or full audio stream URLs.
- Test OAuth callback success/denial/cancel, invalid/expired token, empty search, pagination, empty playlist, unavailable track, expired stream URL, VK↔Yandex switching, and offline mode.
- Before enabling the feature, run flutter_rust_bridge_codegen, cargo check, flutter analyze, tests, and manual Android verification.

## Blockers

1. Real authorization requires a VK OAuth application/client ID and agreed redirect URI; these are not present in YAYMA source.
2. VK Audio methods and permissions depend on VK policy. The third-party vk-audio-token library does not guarantee stable or officially supported API access.
3. Until the OAuth client, available audio methods, and real-account testing are confirmed, we cannot honestly claim that full auth/search/playlists work.
4. The current PR is an initial manual-replacement step plus design documentation, not a release of a full VK Music backend.
