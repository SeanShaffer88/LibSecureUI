-- Out-of-game logic checks for LibSecureUI-1.0 (plain Lua 5.1).
-- Stubs the WoW functions the library touches, with a protected-frame
-- model and a controllable combat lockdown, and drives the deferred
-- queue by firing PLAYER_REGEN_ENABLED by hand.
-- Run from the repo root:  lua5.1 tests/test_libsecureui.lua
-- Note: the stub REJECTS the library's own XML template names, so every
-- creation also exercises the fallback to Blizzard template names.

local realPrint = print
local scriptDir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local root = scriptDir .. "/.."

local inCombat = false
local frames, capturedPrints, driverCalls = {}, {}, {}
local secureCallUsed = false

local function newRegion()
	return { SetAllPoints = function() end, SetTexture = function() end,
		SetText = function() end }
end

local function newFrame(kind, name, parent, template)
	if template and template:match("^LibSecureUI") then
		error("template not found: " .. template) -- XML absent in the stub
	end
	local f = { _attrs = {}, _parent = parent, _shown = false,
		_protected = template ~= nil and template:find("Secure") ~= nil,
		_events = {}, _scripts = {} }
	function f:SetAttribute(a, v) self._attrs[a] = v end
	function f:GetAttribute(a) return self._attrs[a] end
	function f:IsProtected() return self._protected end
	function f:SetSize() end
	function f:SetPoint() end
	function f:SetParent(p) self._parent = p end
	function f:GetParent() return self._parent end
	function f:Show() self._shown = true end
	function f:Hide() self._shown = false end
	function f:IsShown() return self._shown end
	function f:SetScript(n, fn) self._scripts[n] = fn end
	function f:CreateTexture() return newRegion() end
	function f:CreateFontString() return newRegion() end
	function f:RegisterEvent(e) self._events[e] = true end
	function f:UnregisterEvent(e) self._events[e] = nil end
	frames[#frames + 1] = f
	return f
end

_G.CreateFrame = newFrame
_G.UIParent = newFrame("Frame", "UIParent", nil, nil)
_G.InCombatLockdown = function() return inCombat end
_G.RegisterStateDriver = function(frame, state, condition)
	driverCalls[#driverCalls + 1] = { frame = frame, state = state, condition = condition }
end
_G.UnregisterStateDriver = function() end
_G.SecureCall = function(fn, ...) secureCallUsed = true; return fn(...) end
_G.strmatch = string.match
_G.SlashCmdList = {}
_G.geterrorhandler = function() return function() end end
_G.print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	capturedPrints[#capturedPrints + 1] = table.concat(parts, " ")
end

dofile(root .. "/LibStub.lua")
dofile(root .. "/LibSecureUI-1.0.lua")
local LSU = LibStub("LibSecureUI-1.0")

local failures = 0
local function check(name, cond)
	realPrint((cond and "ok   - " or "FAIL - ") .. name)
	if not cond then failures = failures + 1 end
end

local function fireRegenEnabled()
	for _, f in ipairs(frames) do
		if f._events["PLAYER_REGEN_ENABLED"] and f._scripts.OnEvent then
			f._scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
		end
	end
end

-- 1. Button type mappings ------------------------------------------------------
local spell = LSU:CreateSecureButton(_G.UIParent, nil,
	{ type = "spell", action = "Fireball", size = 40 })
check("spell button is protected", spell:IsProtected())
check("spell attributes set", spell:GetAttribute("type") == "spell"
	and spell:GetAttribute("spell") == "Fireball")

local item = LSU:CreateSecureButton(nil, nil, { type = "item", action = "Major Healing Potion" })
check("item attributes set", item:GetAttribute("type") == "item"
	and item:GetAttribute("item") == "Major Healing Potion")

local macro = LSU:CreateSecureButton(nil, nil, { type = "macro", action = "/wave" })
check("macro text attribute set", macro:GetAttribute("type") == "macro"
	and macro:GetAttribute("macrotext") == "/wave")

local macroIdx = LSU:CreateSecureButton(nil, nil, { type = "macro", action = 3 })
check("macro index attribute set", macroIdx:GetAttribute("macro") == 3)

local act = LSU:CreateSecureButton(nil, nil, { type = "action", action = 12 })
check("action slot attribute set", act:GetAttribute("type") == "action"
	and act:GetAttribute("action") == 12)

local tgt = LSU:CreateSecureButton(nil, nil, { type = "target", target = "focus" })
check("target button attributes set", tgt:GetAttribute("type") == "target"
	and tgt:GetAttribute("unit") == "focus")

local clickcast = LSU:CreateSecureButton(nil, nil,
	{ type = "spell", action = "Flash Heal", unit = "mouseover" })
check("unit attribute set for click-cast", clickcast:GetAttribute("unit") == "mouseover")

check("unknown button type errors",
	not pcall(function() LSU:CreateSecureButton(nil, nil, { type = "dance" }) end))

-- 2. SetSecureAttribute: immediate, deferred in combat, applied at regen -------
check("attribute set immediately out of combat",
	LSU:SetSecureAttribute(spell, "spell", "Pyroblast") == true
	and spell:GetAttribute("spell") == "Pyroblast")

inCombat = true
check("IsCombatLocked reports true", LSU:IsCombatLocked())
check("protected attribute deferred in combat",
	LSU:SetSecureAttribute(spell, "spell", "Frostbolt") == false
	and spell:GetAttribute("spell") == "Pyroblast")
local plain = { _attrs = {}, SetAttribute = function(s, a, v) s._attrs[a] = v end }
check("non-protected frame sets immediately in combat",
	LSU:SetSecureAttribute(plain, "x", 1) == true and plain._attrs.x == 1)
inCombat = false
fireRegenEnabled()
check("deferred attribute applied at end of combat",
	spell:GetAttribute("spell") == "Frostbolt")

-- 3. State drivers ---------------------------------------------------------------
local bar = LSU:CreateSecureFrame(nil, nil, { kind = "state" })
check("valid state driver registers",
	LSU:RegisterStateDriver(bar, "visibility", "[combat] show; hide") == true)
check("driver call recorded", #driverCalls >= 1)
local okBad = LSU:RegisterStateDriver(bar, "bad name!", "show")
check("invalid state name rejected", okBad == false)
local okEmpty = LSU:RegisterStateDriver(bar, "visibility", "")
check("empty condition rejected", okEmpty == false)

local driven = LSU:CreateSecureFrame(nil, nil, {
	kind = "state",
	stateDriver = { state = "visibility", condition = "[vehicleui] show; hide" },
})
check("frame option stateDriver registers", driven ~= nil and #driverCalls >= 2)
check("unknown frame kind errors",
	not pcall(function() LSU:CreateSecureFrame(nil, nil, { kind = "portal" }) end))

-- 4. Pooling -----------------------------------------------------------------------
local p1 = LSU:AcquireButton("grid", nil, { type = "spell", action = "Fireball" })
check("pool acquire creates a button", p1 ~= nil and p1:GetAttribute("spell") == "Fireball")
check("release returns true", LSU:ReleaseButton(p1) == true)
check("pool has one free button", LSU:GetStats().pools["grid"] == 1)
local p2 = LSU:AcquireButton("grid", nil, { type = "item", action = "Conjured Water" })
check("pool reuses the same frame", p2 == p1)
check("recycled button reconfigured", p2:GetAttribute("type") == "item"
	and p2:GetAttribute("item") == "Conjured Water"
	and p2:GetAttribute("spell") == nil)

inCombat = true
local pCombat, pErr = LSU:AcquireButton("grid", nil, { type = "spell", action = "X" })
check("acquire refused in combat", pCombat == nil and pErr == "combat")
check("release deferred in combat", LSU:ReleaseButton(p2) == false)
inCombat = false
fireRegenEnabled()
check("deferred release landed after combat", LSU:GetStats().pools["grid"] == 1)
check("double release refused", LSU:ReleaseButton(p2) == false)

-- 5. RunSecure and stats -------------------------------------------------------------
local sum = LSU:RunSecure(function(a, b) return a + b end, 2, 3)
check("RunSecure returns results via SecureCall", sum == 5 and secureCallUsed)
local s = LSU:GetStats()
check("stats count creations", s.buttons >= 7 and s.frames >= 2 and s.drivers >= 2)
check("stats deferred counters", s.deferredTotal >= 2 and s.deferredPending == 0)

-- 6. Self-test path ---------------------------------------------------------------------
LSU:RunTest()
local joined = table.concat(capturedPrints, "\n")
check("test prints the protected checklist", joined:find("button protected: true") ~= nil)
check("test prints the pool round-trip", joined:find("pool round%-trip: true") ~= nil)
LSU:RunTest()
joined = table.concat(capturedPrints, "\n")
check("second test run removes the button", joined:find("test button removed") ~= nil)
check("slash handler registered", type(_G.SlashCmdList["LIBSECUREUI"]) == "function")
_G.SlashCmdList["LIBSECUREUI"]("stats")
check("slash stats prints", table.concat(capturedPrints, "\n"):find("deferred pending") ~= nil)

realPrint(failures == 0 and "PASS - all LibSecureUI checks passed"
	or ("FAIL - " .. failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
