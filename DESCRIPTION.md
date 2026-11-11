# LibSecureUI-1.0

**Secure buttons that work in combat — without the taint errors.**

Casting a spell, using a potion, or targeting a unit from an addon click
is only possible through WoW's secure templates, and their rules are
strict: touch a protected frame the wrong way during combat and the
client blocks the action, blames your addon, or taints the default UI.
Every addon author re-learns those rules the hard way.

LibSecureUI packages them. Create a secure button with one call and a
plain option table — spell, item, macro, action slot, or target. Set
attributes through a combat-aware setter that quietly defers whatever
combat forbids and applies it the moment the fight ends. Change
visibility during combat the sanctioned way, with validated state
drivers. Reuse buttons from a pool instead of churning frames. The taint
rules themselves are written down in the README as three short lists:
what is secure, what is locked in combat (and what the library does
instead), and what you must never do.

For addon authors: embed it through LibStub, build your click-casting,
action bars, and state-driven frames on it, and run `/libsecureui test`
to watch a secure button fire `/wave` in the middle of combat — no
errors, no taint. Under 500 lines of Lua plus a small XML template file,
no dependencies.

For players: like most libraries, it does nothing on its own. It is the
safety layer inside other addons that keeps their buttons working when
the fight starts.
