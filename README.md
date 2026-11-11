# LibSecureUI

<p align="center"><img src="icon.png" width="160" alt="LibSecureUI icon — a shield with a check mark on a dark tile"></p>

## TL;DR

**LibSecureUI-1.0** is a small library for **WoW Classic Forever**
(Interface **16001**) that lets addon authors build **secure buttons and
frames** — the kind that can cast spells, use items, run macros, and
target units when clicked, even in combat — without tainting the default
UI or fighting combat lockdown by hand. Attribute changes that combat
forbids are **deferred automatically** until combat ends. Use it embedded
through LibStub, or install it standalone. Version **1.0.0**, MIT
license, no dependencies.

```lua
local LSU = LibStub("LibSecureUI-1.0")

local btn = LSU:CreateSecureButton(UIParent, nil, {
    type = "spell", action = "Fireball",
    size = 40, texture = "Interface\\Icons\\Spell_Fire_FlameBolt",
})
btn:SetPoint("CENTER", 0, -120)
```

**Docs:** [Features](FEATURES.md) · [Description](DESCRIPTION.md) · [Changelog](CHANGELOG.md)

**Requirements:** a WoW Classic Forever client (Interface **16001**).
Nothing else — LibStub is bundled for standalone use and steps aside
when a newer LibStub is already loaded. (The brief for this library
named Interface 11507; that is the Classic Era number. The Forever
client is 16001 — an addon declaring 11507 never loads there — so the
`.toc` targets 16001.)

## Why

Secure templates are powerful and unforgiving. Get one rule wrong —
change an attribute in combat, show a protected frame from the wrong
code path, let insecure code touch a secure handler — and the result is
a taint error, a blocked action ("Interface action failed because of an
AddOn"), or a button that silently stops working mid-fight. Every author
re-learns the same rules. LibSecureUI encodes them once: creation through
the right templates, attributes through a combat-aware setter, state
drivers for anything that must change *during* combat, and pooling so
repeated secure UI does not churn frames.

## Installation

### Standalone

1. Download this repository (or the release zip) and unzip it.
2. Keep the folder named **`LibSecureUI-1.0`** — it must match the `.toc`
   name or the game will not load it.
3. Move it into `World of Warcraft\_classic_\Interface\AddOns\` so the
   path reads `AddOns\LibSecureUI-1.0\LibSecureUI-1.0.toc`.
4. Restart the game (a brand-new addon needs a restart, not `/reload`)
   and tick **LibSecureUI-1.0** in the AddOns list.

### Embedded in your addon

1. Copy `LibStub.lua`, `LibSecureUI-1.0.xml`, `LibSecureUI-1.0.lua`, and
   `embeds.xml` into your addon, e.g. under `YourAddon\libs\LibSecureUI-1.0\`.
   (If your addon already loads LibStub, keep yours.)
2. Include the folder's `embeds.xml` from your addon's own `embeds.xml`,
   or list the files in your `.toc` **in this order**: `LibStub.lua`,
   `LibSecureUI-1.0.xml`, `LibSecureUI-1.0.lua` — the XML templates must
   load before the Lua that uses them.
3. In your code: `local LSU = LibStub("LibSecureUI-1.0")`.

If the XML is missing from an embed, the library falls back to Blizzard's
own template names automatically.

## The taint rules (read this first)

**Secure** — always allowed, including in combat:

- Clicking a properly built secure button: the click is evaluated by the
  secure environment from the button's attributes.
- Changes made **by a state driver itself** (visibility, paging) — the
  driver string runs in the secure environment.
- Reading attributes (`GetAttribute`), `IsProtected`, `GetStats`.

**Insecure on protected frames during combat lockdown** — the client
blocks these from addon code, and forcing them is how addons taint:

- Setting or clearing attributes (`SetAttribute`).
- Showing/hiding, moving, resizing, reparenting, setting scripts.
- Creating configured secure UI mid-combat.

LibSecureUI's answer: `SetSecureAttribute` **defers** instead of failing —
changes queue and apply on `PLAYER_REGEN_ENABLED`. Pool acquire/release
refuse in combat (acquire returns `nil, "combat"`) rather than hand you a
half-configured button. Create your secure UI **out of combat** (at load,
or on `PLAYER_REGEN_ENABLED`), and let state drivers do the in-combat
changes.

**Never**, in any library, including this one:

- Never call protected functions from addon code (`CastSpellByName`,
  `TargetUnit`, `FocusUnit`, ...) — use a secure button instead.
- Never hook or replace secure handlers, and never let insecure code set
  scripts on a protected frame after creation.
- Never store secure snippets that reach back into insecure tables.
- `RunSecure` (SecureCall) prevents taint *spread*; it grants **no**
  protected-action rights. It cannot cast for you.

## API

All public functions carry LuaDoc comments in
[`LibSecureUI-1.0.lua`](LibSecureUI-1.0.lua).

### `LSU:CreateSecureButton(parent, name, options)` → Button

Creates a button from `SecureActionButtonTemplate` (through the
library's `LibSecureUIButtonTemplate` when the XML is loaded). `name`
may be nil for an anonymous button — a named frame creates a global, by
your choice.

| Option | Meaning |
|---|---|
| `type` | `"spell"`, `"item"`, `"macro"`, `"action"`, or `"target"`. |
| `action` | For spell/item: name or id. For macro: macro text, or a macro index number. For action: the action-bar slot number. |
| `target` | Unit for `type = "target"` (default `"target"`). |
| `unit` | Stored as the button's `unit` attribute (click-cast style buttons). |
| `attributes` | Table of extra secure attributes to set. |
| `size` | A number (square) or `{ width, height }`. Default 36×36. |
| `texture` | Texture path for an ARTWORK texture covering the button. |
| `text` | Centered label (creates a font string). |
| `tooltip` | Text shown in the GameTooltip on mouse-over. |

Returns the Button frame. Set points and show it yourself —
positioning a protected frame is combat-locked, so do layout out of
combat.

### `LSU:SetSecureAttribute(frame, attribute, value)` → boolean

The safe setter used by everything above. Out of combat (or on a
non-protected frame) it sets immediately and returns `true`. In combat
on a protected frame it queues the change for the end of combat and
returns `false`. `value = nil` clears an attribute.

### `LSU:CreateSecureFrame(parent, name, options)` → Frame

Creates a non-button secure frame.

| Option | Meaning |
|---|---|
| `kind` | `"state"` (SecureHandlerStateTemplate — default), `"showhide"` (SecureHandlerShowHideTemplate), `"base"` (SecureHandlerBaseTemplate), or `"header"` (SecureGroupHeaderTemplate). |
| `attributes` | Table of secure attributes to set. |
| `stateDriver` | `{ state = ..., condition = ... }`, registered through the validated wrapper below. |

### `LSU:RegisterStateDriver(frame, state, condition)` → ok, err

Validated wrapper around `RegisterStateDriver`. `state` must be a plain
name (letters, digits, `-`, `_`) — `"visibility"` is the special built-in
state; any other name is stored as the attribute `state-<name>`.
`condition` must be a non-empty secure condition string. State drivers
are the sanctioned mechanism for in-combat changes: the secure
environment evaluates the condition, so `[combat] show; hide` works
while your code is locked. `LSU:UnregisterStateDriver(frame, state)`
removes one.

### Frame pooling: `LSU:AcquireButton(poolName, parent, options)` and `LSU:ReleaseButton(button)`

For repeated secure UI (unit-frame grids, action bars), creation cost
and attribute churn add up. `AcquireButton` reuses a released button
from the named pool — clearing its old action attributes and applying
the new options exactly as `CreateSecureButton` would — or creates a new
one when the pool is empty. `ReleaseButton` clears the button's action
attributes, hides it, and returns it to its pool. Both are **out of
combat only**: acquire returns `nil, "combat"` in combat; release defers
to the end of combat and returns `false`.

### `LSU:IsCombatLocked()` → boolean

Thin, honest wrapper: returns `InCombatLockdown()`.

### `LSU:RunSecure(func, ...)` → results

Runs `func` through `SecureCall` when available (executing without
spreading taint into secure paths), else calls it directly, and returns
its results. See the warning in the taint rules: this grants no
protected-action rights.

### `LSU:GetStats()` → table

`{ buttons, frames, drivers, deferredTotal, deferredPending, pools }` —
counts since load; `pools` maps each pool name to its free-button count.

### Version

`LSU.VERSION` is `"1.0.0"`; `LSU.MAJOR` is `"LibSecureUI-1.0"`.

## Examples

### Example 1 — simple: a secure spell button

One button that casts a spell when clicked, with an icon and a tooltip.
It works in combat because the *click* is what casts — your code only
built the button, out of combat.

```lua
local LSU = LibStub("LibSecureUI-1.0")

local btn = LSU:CreateSecureButton(UIParent, nil, {
    type = "spell",
    action = "Frostbolt",
    size = 48,
    texture = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    tooltip = "Cast Frostbolt",
})
btn:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
btn:Show()
```

### Example 2 — advanced: combat/vehicle visibility via a state driver

A secure frame holding utility buttons that must appear in combat and
while in a vehicle, and hide otherwise. Addon code cannot show or hide a
protected frame in combat — so it never tries. A **state driver** does
it from the secure environment:

```lua
local LSU = LibStub("LibSecureUI-1.0")

-- A state-driven secure container.
local bar = LSU:CreateSecureFrame(UIParent, nil, { kind = "state" })
bar:SetSize(120, 40)
bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)

-- Children are secure buttons parented to the driven frame: when the
-- driver hides the frame, the children hide with it.
local potion = LSU:CreateSecureButton(bar, nil, {
    type = "item", action = "Major Healing Potion", size = 40,
    texture = "Interface\\Icons\\INV_Potion_54",
})
potion:SetPoint("LEFT", bar, "LEFT", 0, 0)
potion:Show()

local bandage = LSU:CreateSecureButton(bar, nil, {
    type = "item", action = "Heavy Netherweave Bandage", size = 40,
    texture = "Interface\\Icons\\INV_Misc_Bandage_12",
})
bandage:SetPoint("LEFT", potion, "RIGHT", 8, 0)
bandage:Show()

-- Show in combat or in a vehicle; hide the rest of the time.
-- [vehicleui] is true while you control a vehicle; [combat] in combat.
local ok, err = LSU:RegisterStateDriver(bar, "visibility",
    "[combat] show; [vehicleui] show; hide")
assert(ok, err)

-- And a mid-combat change done RIGHT: re-pointing the potion button at
-- a different potion while fighting does not error -- it defers and
-- applies the moment combat ends.
--   LSU:SetSecureAttribute(potion, "item", "Super Healing Potion")
```

## Testing

### In game

1. Install standalone (above) and log in, **out of combat**.
2. Type **`/libsecureui test`** (or `/lsui test`). A button labelled
   "LibSecureUI Test" appears above the center of the screen, and chat
   prints a checklist line: the button is protected, its `type`
   attribute is `macro`, the state driver registered, and a pool
   round-trip succeeded.
3. **The real verification:** attack a training dummy to enter combat,
   then **click the test button**. It should make your character `/wave`
   — in combat, with no "Interface action failed" taint error. A secure
   button that fires in combat without taint is the whole point of the
   library.
4. Run `/libsecureui test` again to remove the button.
   `/libsecureui stats` prints creation/driver/deferred counts.

### Outside the game

`tests/test_libsecureui.lua` stubs the WoW functions the library touches
(frame creation with protected flags, combat lockdown, state drivers,
SecureCall) and checks creation, attribute mapping, combat deferral and
its end-of-combat application, state-driver validation, pooling, and the
slash test path:

```sh
lua5.1 tests/test_libsecureui.lua
```

These checks prove the library's logic. Only the in-game click-in-combat
test proves behavior in the real Forever client.

## Performance notes

- **Pooling** — recycled buttons skip creation entirely; release clears
  only the seven action attributes, so reconfiguration is a handful of
  attribute writes, not a rebuild.
- **No per-frame cost** — the library installs no OnUpdate. Its one event
  frame listens for `PLAYER_REGEN_ENABLED` only while deferred work is
  actually queued.
- **No attribute churn** — attributes are set at configuration time
  (creation, acquire, explicit `SetSecureAttribute`), never per click or
  per frame.
- **Template indirection** — the XML templates are pure inheritance: zero
  runtime cost, and they insulate embedders from Blizzard template
  renames.

## Known limitations

- **Creation is an out-of-combat activity.** The client combat-locks
  positioning, sizing, scripting, and (for practical purposes)
  configuring protected frames. The library defers *attribute* changes,
  but layout must happen out of combat; pool acquire refuses in combat
  instead of pretending otherwise.
- **Deferral is not retroactive.** A deferred attribute lands at the end
  of combat with its final queued value; intermediate values are not
  replayed as a timeline.
- **Secure snippets are out of scope.** The library does not generate
  SecureHandler `_onclick` / `_onattributechange` snippet code. Buttons
  use the built-in secure action machinery; authors who need custom
  secure logic should write snippets deliberately, by hand.
- **Group headers are configured, not managed.** `kind = "header"`
  creates a `SecureGroupHeaderTemplate` frame; the many header
  attributes (showRaid, groupFilter, ...) are yours to set — through
  `SetSecureAttribute` if combat safety matters.
- **`RunSecure` is not a permission slip.** See the taint rules.
- **Test button scope.** `/libsecureui test` proves one macro button in
  combat. It cannot prove your own buttons' attributes are right — only
  that the machinery is.

## Compatibility notes (Classic Forever)

- Targets **Interface 16001** (WoW Classic Forever, game version 1.60.1,
  sharing the modern Mainline API set). Uses `CreateFrame`,
  `InCombatLockdown`, `RegisterStateDriver` / `UnregisterStateDriver`,
  `SecureCall`, the `SecureActionButtonTemplate` / `SecureHandler*`
  templates, and events.
- **Taint scenarios to avoid** (all covered in the rules above): setting
  attributes on protected frames in combat (defer instead), letting
  insecure code re-script a protected frame after creation, showing or
  moving protected frames from insecure code in combat (use a state
  driver), and calling protected functions directly (use a secure
  button).
- **Forever's combat-data restrictions** (the "addon disarmament" the
  client shares with modern Mainline) limit what addons may *read*
  during combat; they do not change the secure-template rules — secure
  buttons and state drivers remain the sanctioned way to *act*.
- **No deprecated APIs**, no XML frame instances (templates only), and
  the library's only globals are the LibStub registration and the
  `SLASH_` entries the slash system requires. Named frames are created
  only when you pass a name.

## Files

| File | Purpose |
|---|---|
| `LibSecureUI-1.0.lua` | The library. |
| `LibSecureUI-1.0.xml` | Virtual secure templates (pure inheritance). |
| `LibStub.lua` | Bundled LibStub 1.0, for standalone use. |
| `LibSecureUI-1.0.toc` | Standalone addon metadata, Interface 16001. |
| `embeds.xml` | Include file for embedding in another addon. |
| `icon.png` / `Icon.tga` | The addon icon (shield); the `.tga` is the in-game texture named by the toc's `IconTexture` entry. |
| `tests/test_libsecureui.lua` | Out-of-game logic checks (Lua 5.1). |
| `FEATURES.md` / `DESCRIPTION.md` / `CHANGELOG.md` | Feature list, store-style description, history. |

## License

MIT — see [`LICENSE`](LICENSE).
