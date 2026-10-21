# VK Audio source integration

Status: implementation plan / review scaffold. This document does not claim that VK playback is already implemented.

## Goal

Add VK as an optional audio source for an existing YAYMA track, without replacing the current Flutter UI or changing Yandex Music playback by default. The first usable slice should resolve a VK audio item to a stream URL and feed that URL through the existing track-override/stream pipeline.

## What already exists in YAYMA

- `src/rust/src/plugin_host/mod.rs` maintains replacement maps keyed by Yandex track ID.
- `src/rust/src/api/plugins.rs` exposes the per-track override API.
- `src/rust/src/audio/stream_manager.rs` checks a replacement URL before falling back to the Yandex stream, and falls back to Yandex if replacement streaming fails.
- The track context menu already has **Подменить аудио…**.

Therefore the first iteration should reuse these paths rather than introduce a parallel player or redesign the UI.

## Proposed UX

1. Keep **Подменить аудио…** in the existing track menu.
2. Add a source choice in that dialog: direct audio URL (current behavior) or VK audio item.
3. For VK, accept an audio item reference such as `owner_id_audio_id` and show a clear connection/token state.
4. Add a small VK section in existing settings for the user's VK audio API token and matching User-Agent. Never request or store the account password in YAYMA.
5. Keep Yandex as the fallback if VK resolution or streaming fails.

## Integration boundary

The upstream `vodka2/vk-audio-token` repository is a PHP library, not a Rust/Flutter dependency. It obtains tokens for VK's unofficial audio API and documents that the User-Agent associated with the token must be sent on API requests. It should not be copied wholesale into the Rust application.

For a mobile-first implementation, prefer one of these explicit paths:

- **User-supplied token (preferred first slice):** the user obtains a token outside YAYMA, pastes it into settings, and YAYMA only uses it for audio lookups. This avoids embedding a password-based login flow or brittle Android/GMS emulation.
- **Separate optional helper:** if automatic token acquisition is later required, isolate it behind a separately deployed helper with an explicit trust boundary. Do not send VK passwords to a server silently.

Do not attempt to resolve a VK share/page URL by treating it as an MP3 URL. VK audio API responses may require additional URL decoding or client-specific handling, and must be validated against real responses before being used for streaming.

## Implementation checklist

- [ ] Add a Rust VK audio client with bounded request timeouts, status/error parsing, and tests using mocked JSON responses.
- [ ] Add an explicit configuration DTO for token and User-Agent; persist secrets using platform-secure storage rather than plain settings JSON.
- [ ] Resolve VK audio item IDs to stream URLs and normalize metadata needed by the existing override pipeline.
- [ ] Extend the existing replacement dialog with a VK-item mode, without changing the main player layout.
- [ ] Make VK overrides take precedence only for the selected Yandex track; preserve the existing manual URL override priority.
- [ ] Keep Yandex fallback behavior on HTTP, API, decode, or codec failures.
- [ ] Ensure tokens, authorization headers, and audio URLs are redacted from logs.
- [ ] Add tests for malformed IDs, missing URLs, expired/invalid tokens, non-success API responses, and Yandex fallback.
- [ ] Run `flutter_rust_bridge_codegen generate`, `cargo test`, `flutter analyze`, and an Android release build.

## Compatibility and limitations

- `vodka2/vk-audio-token` is PHP and its upstream token acquisition is based on unofficial/private VK client flows; it cannot be imported directly into this Rust project.
- VK API behavior and audio URL formats can change independently of YAYMA.
- Only play audio the user is entitled to access. This integration must not bypass access controls or attempt to access private audio.
- Preserve the upstream MIT license notice if any code is eventually copied; do not copy implementation code as part of this planning document.
