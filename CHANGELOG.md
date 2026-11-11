# Changelog

All notable changes to LibSecureUI are recorded here.
Format follows Keep a Changelog; versions use semantic versioning.

## [1.0.0] - 2026-11-10

### Added

- Initial release of the `LibSecureUI-1.0` library for WoW Classic
  Forever (Interface 16001).
- `CreateSecureButton` over `SecureActionButtonTemplate` with the
  simplified type system (`spell`, `item`, `macro`, `action`, `target`)
  and options for size, texture, text label, tooltip, unit, and extra
  attributes.
- `SetSecureAttribute`: combat-aware attribute setter that defers
  protected-frame changes to `PLAYER_REGEN_ENABLED` during combat
  lockdown instead of erroring or tainting.
- `CreateSecureFrame` for SecureHandler state / show-hide / base frames
  and secure group headers.
- `RegisterStateDriver` / `UnregisterStateDriver` wrappers with input
  validation.
- Frame pooling: `AcquireButton` / `ReleaseButton` with full attribute
  reset on recycle, combat refusal on acquire, deferred release.
- `IsCombatLocked`, `RunSecure` (SecureCall when available), `GetStats`.
- Virtual secure templates in `LibSecureUI-1.0.xml` (pure inheritance,
  with automatic fallback to Blizzard template names).
- Self-test: `/libsecureui test` secure macro button with a visibility
  state driver, a printed checklist, and an in-combat click check;
  `/libsecureui stats` subcommand (`/lsui` alias).
- Addon and repo icon (shield) with the `.toc` `IconTexture` entry.
- Out-of-game logic checks in `tests/test_libsecureui.lua`.
