# LibSecureUI — Features

Version 1.0.0 · WoW Classic Forever · Interface 16001

## Secure creation

- `CreateSecureButton` over `SecureActionButtonTemplate` with a
  plain-words option set: `type` (`spell` / `item` / `macro` / `action` /
  `target`), `action`, `target`, `unit`, extra `attributes`, `size`,
  `texture`, `text`, `tooltip`.
- `CreateSecureFrame` for `SecureHandlerStateTemplate`,
  `SecureHandlerShowHideTemplate`, `SecureHandlerBaseTemplate`, and
  `SecureGroupHeaderTemplate` frames.
- Library XML templates (`LibSecureUIButtonTemplate`,
  `LibSecureUIStateFrameTemplate`, `LibSecureUIShowHideFrameTemplate`)
  are pure inheritance — no snippets, no scripts — with automatic
  fallback to the Blizzard template names when the XML is not embedded.

## Combat safety

- `SetSecureAttribute`: the combat-aware setter. In combat on a
  protected frame it defers the change to `PLAYER_REGEN_ENABLED` and
  returns `false`; otherwise it applies immediately. Nothing errors,
  nothing taints.
- Deferred work runs from one anonymous event frame that only listens
  while work is queued.
- `IsCombatLocked()` for honest branching in caller code.
- `RunSecure` routes through `SecureCall` when available to avoid
  spreading taint (documented as granting no protected-action rights).

## State drivers

- `RegisterStateDriver` wrapper with validation of the frame, the state
  name, and a non-empty condition string; `UnregisterStateDriver`
  alongside it.
- Drivers are the in-combat mechanism: secure-environment visibility and
  state changes like `[combat] show; hide` and
  `[vehicleui] show; hide`.

## Pooling

- `AcquireButton(poolName, parent, options)` reuses released buttons,
  clearing the seven action attributes and re-applying options through
  the same path as fresh creation.
- `ReleaseButton` clears, hides, and recycles; in combat it defers to
  the end of combat. Acquire refuses in combat (`nil, "combat"`) rather
  than returning a half-configured protected button.

## Observability and testing

- `GetStats()`: buttons/frames created, drivers registered, deferred
  totals and pending count, per-pool free counts.
- `/libsecureui test` builds a real secure macro button (`/wave`) with a
  visibility state driver, prints a checklist (protected, type
  attribute, driver, pool round-trip), and stays on screen so you can
  click it **in combat** — the true taint test. Run again to remove.
- `/libsecureui stats` (alias `/lsui`) prints the counters.

## Integration

- LibStub library `LibSecureUI-1.0`, minor-version safe across embeds;
  also runs standalone (bundled LibStub steps aside when a newer one is
  present).
- Taint rules documented in the README as three lists: secure,
  insecure-in-combat (with the library's deferral/refusal behavior), and
  never.
- Full LuaDoc on every public function and table. No dependencies, no
  SavedVariables, no OnUpdate.
