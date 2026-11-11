--[[---------------------------------------------------------------------------
LibSecureUI-1.0 -- a safe, simplified layer over WoW's secure templates.

Secure templates are the ONLY way an addon may cast a spell, use an item,
run a macro, or target a unit from a click -- and the rules are strict.
This library packages the strict parts (creation, attributes, state
drivers, combat deferral, pooling) so authors stop re-learning them.

TAINT RULES IN ONE SCREEN (full version in README.md):
  * SECURE (always fine, even in combat): clicking a properly built
    secure button; state-driver visibility changes the DRIVER ITSELF
    makes; reading attributes.
  * INSECURE (blocked / tainting on protected frames during combat
    lockdown): setting attributes, showing/hiding, moving, resizing, or
    reparenting a protected frame from addon code. This library DEFERS
    those to PLAYER_REGEN_ENABLED instead of erroring or tainting.
  * NEVER: hooksecurefunc is fine, but never hook, replace, or call
    protected functions (CastSpellByName, TargetUnit, ...) from addon
    code, and never let insecure code touch a secure frame's scripts.
Usage: local LSU = LibStub("LibSecureUI-1.0")
---------------------------------------------------------------------------]]
local MAJOR, MINOR = "LibSecureUI-1.0", 1

---@class LibSecureUI-1.0
---@field VERSION string Semantic version of this library release.
local lib
if _G.LibStub then
	lib = _G.LibStub:NewLibrary(MAJOR, MINOR)
	if not lib then return end -- a newer or equal copy is already loaded
else
	lib = {} -- standalone fallback: no LibStub present, expose one global
	_G[MAJOR] = lib
end
lib.MAJOR, lib.MINOR, lib.VERSION = MAJOR, MINOR, "1.0.0"

-- Localized globals (upvalues; keeps the secure paths taint-free).
local type, pcall, pairs, error, tostring, tonumber =
	type, pcall, pairs, error, tostring, tonumber
local setmetatable, geterrorhandler = setmetatable, geterrorhandler
local str_format, str_lower, str_match = string.format, string.lower, string.match
local CreateFrame, InCombatLockdown = CreateFrame, InCombatLockdown
local RegisterStateDriver, UnregisterStateDriver =
	_G.RegisterStateDriver, _G.UnregisterStateDriver
local SecureCall, UIParent = _G.SecureCall, _G.UIParent

-- State -----------------------------------------------------------------------
local deferred = {} -- work waiting for PLAYER_REGEN_ENABLED (functions)
local eventFrame = nil
local pools = {} -- poolName -> { free = { button, ... } }
local stats = { buttons = 0, frames = 0, drivers = 0, deferredTotal = 0 }
local testButton = nil

---@return boolean True while combat lockdown is active.
function lib:IsCombatLocked() return InCombatLockdown() end

---@param fn function Callback run when combat ends (or right away).
local function Defer(fn)
	deferred[#deferred + 1] = fn
	stats.deferredTotal = stats.deferredTotal + 1
	if not eventFrame then
		eventFrame = CreateFrame("Frame") -- anonymous: creates no global
		eventFrame:SetScript("OnEvent", function(_, event)
			if event ~= "PLAYER_REGEN_ENABLED" then return end
			eventFrame:UnregisterEvent(event)
			local work = deferred
			deferred = {}
			for i = 1, #work do
				local ok, err = pcall(work[i])
				if not ok and geterrorhandler then geterrorhandler()(err) end
			end
		end)
	end
	eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Secure attributes -------------------------------------------------------------

--- Sets an attribute on a frame, safely. When combat lockdown is active
--- and the frame is protected, the client forbids the change: instead of
--- erroring (or tainting), the change is queued and applied the moment
--- combat ends (PLAYER_REGEN_ENABLED).
--- @param frame table Frame with SetAttribute (usually protected).
--- @param attribute string Attribute name, e.g. "type", "spell", "unit".
--- @param value any Attribute value; nil clears the attribute.
--- @return boolean applied True when set now, false when deferred.
function lib:SetSecureAttribute(frame, attribute, value)
	if type(frame) ~= "table" or type(frame.SetAttribute) ~= "function" then
		error("LibSecureUI: SetSecureAttribute needs a frame", 2)
	end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		local f, a, v = frame, attribute, value
		Defer(function() f:SetAttribute(a, v) end)
		return false
	end
	frame:SetAttribute(attribute, value)
	return true
end

---@param frame table Frame to configure.
---@param attributes table|nil Map of attribute name -> value.
local function ApplyAttributes(frame, attributes)
	if not attributes then return end
	for name, value in pairs(attributes) do lib:SetSecureAttribute(frame, name, value) end
end

--- Creates a frame from a library template, falling back to the Blizzard
--- template when the library XML was not loaded (embed without the .xml).
---@param kind string "Button" or "Frame".
---@param name string|nil Frame name (a named frame creates a global).
---@param parent table Parent frame.
---@param libTemplate string Library template from LibSecureUI-1.0.xml.
---@param fallback string Blizzard template to use when XML is absent.
---@return table The created frame.
local function CreateWithTemplate(kind, name, parent, libTemplate, fallback)
	if lib._templateCache == nil then lib._templateCache = {} end
	local cache = lib._templateCache
	if cache[libTemplate] == nil then
		local ok, frame = pcall(CreateFrame, kind, name, parent, libTemplate)
		if ok and frame then
			cache[libTemplate] = true
			return frame
		end
		cache[libTemplate] = false
	end
	if cache[libTemplate] then return CreateFrame(kind, name, parent, libTemplate) end
	return CreateFrame(kind, name, parent, fallback)
end

-- Secure buttons ----------------------------------------------------------------

-- How each simplified button type maps onto secure attributes.
local BUTTON_TYPE_ATTRIBUTES = {
	spell = "spell", -- action -> "spell" attribute
	item = "item", -- action -> "item" attribute
	action = "action", -- action -> numeric action-bar slot
}

--- Applies the type/action/unit/attributes options to a secure button.
--- Shared by CreateSecureButton and by pool recycling, so a reused button
--- is configured exactly like a fresh one.
---@param btn table Secure button.
---@param options table Options (type, action, target, unit, attributes).
local function ApplyButtonOptions(btn, options)
	local btype = options.type and str_lower(tostring(options.type)) or nil
	if btype then
		if btype == "macro" then
			lib:SetSecureAttribute(btn, "type", "macro")
			if type(options.action) == "number" then
				lib:SetSecureAttribute(btn, "macro", options.action)
			elseif options.action ~= nil then
				lib:SetSecureAttribute(btn, "macrotext", options.action)
			end
		elseif btype == "target" then
			lib:SetSecureAttribute(btn, "type", "target")
			lib:SetSecureAttribute(btn, "unit", options.target or options.unit or "target")
		elseif BUTTON_TYPE_ATTRIBUTES[btype] then
			lib:SetSecureAttribute(btn, "type", btype)
			if options.action ~= nil then
				lib:SetSecureAttribute(btn, BUTTON_TYPE_ATTRIBUTES[btype], options.action)
			end
		else
			error("LibSecureUI: unknown secure button type " .. tostring(options.type), 3)
		end
	end
	if options.unit and btype ~= "target" then lib:SetSecureAttribute(btn, "unit", options.unit) end
	ApplyAttributes(btn, options.attributes)
end
--- Creates a secure action button (SecureActionButtonTemplate) that can
--- be clicked in combat without taint. Create buttons OUT of combat:
--- positioning, sizing and scripting a protected frame are locked in
--- combat; attribute changes are deferred safely by this library.
--- @param parent table|nil Parent frame (default UIParent).
--- @param name string|nil Frame name; a named frame creates a global of
---   that name -- pass nil for an anonymous button.
--- @param options table|nil {
---   type = "spell"|"item"|"macro"|"action"|"target",
---   action = string|number (spell/item name or id, macro text or index,
---     action slot), target = unit string for type "target",
---   unit = unit string stored as the button's "unit" attribute,
---   attributes = table of extra secure attributes,
---   size = number|{ w, h }, texture = path, text = string label,
---   tooltip = string shown in the GameTooltip on mouse-over }.
--- @return table The secure Button frame.
function lib:CreateSecureButton(parent, name, options)
	options = options or {}
	parent = parent or UIParent
	local btn = CreateWithTemplate("Button", name, parent,
		"LibSecureUIButtonTemplate", "SecureActionButtonTemplate")
	btn._lsuiSecureButton = true
	if options.size then
		local w, h = options.size, options.size
		if type(options.size) == "table" then w, h = options.size[1], options.size[2] end
		btn:SetSize(w or 36, h or 36)
	end
	if options.texture then
		local tex = btn:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints(btn)
		tex:SetTexture(options.texture)
		btn._lsuiTexture = tex
	end
	if options.text then
		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetAllPoints(btn)
		label:SetText(options.text)
		btn._lsuiLabel = label
	end
	if options.tooltip then
		local tip = options.tooltip
		btn:SetScript("OnEnter", function(self)
			if _G.GameTooltip then
				_G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				_G.GameTooltip:SetText(tip)
				_G.GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
	end
	ApplyButtonOptions(btn, options)
	stats.buttons = stats.buttons + 1
	return btn
end

-- Secure frames -----------------------------------------------------------------

local FRAME_KINDS = {
	state = { lib = "LibSecureUIStateFrameTemplate", fallback = "SecureHandlerStateTemplate" },
	showhide = { lib = "LibSecureUIShowHideFrameTemplate", fallback = "SecureHandlerShowHideTemplate" },
	base = { lib = nil, fallback = "SecureHandlerBaseTemplate" },
	header = { lib = nil, fallback = "SecureGroupHeaderTemplate" },
}

--- Creates a non-button secure frame: a SecureHandler frame or a secure
--- group header, for state-driven visibility and secure child handling.
--- @param parent table|nil Parent frame (default UIParent).
--- @param name string|nil Frame name (named frames create globals).
--- @param options table|nil { kind = "state"|"showhide"|"base"|"header"
---   (default "state"), attributes = table,
---   stateDriver = { state = string, condition = string } }.
--- @return table The secure Frame.
function lib:CreateSecureFrame(parent, name, options)
	options = options or {}
	parent = parent or UIParent
	local kind = FRAME_KINDS[options.kind or "state"]
	if not kind then error("LibSecureUI: unknown secure frame kind " .. tostring(options.kind), 2) end
	local frame
	if kind.lib then
		frame = CreateWithTemplate("Frame", name, parent, kind.lib, kind.fallback)
	else
		frame = CreateFrame("Frame", name, parent, kind.fallback)
	end
	ApplyAttributes(frame, options.attributes)
	if options.stateDriver then
		self:RegisterStateDriver(frame, options.stateDriver.state, options.stateDriver.condition)
	end
	stats.frames = stats.frames + 1
	return frame
end

-- State drivers -----------------------------------------------------------------

--- Registers a secure state driver with validation. State drivers are
--- the sanctioned way to change visibility or state DURING combat: the
--- driver string is evaluated by the secure environment, so conditions
--- like "[combat] show; hide" keep working when addon code is locked.
--- @param frame table Protected frame to drive.
--- @param state string State name: "visibility" or a custom name made of
---   letters, digits, "-" or "_" (stored as attribute "state-<name>").
--- @param condition string Secure condition string, e.g.
---   "[combat] show; hide" or "[vehicleui] 12; [mounted] 3; 0".
--- @return boolean ok, string|nil err
function lib:RegisterStateDriver(frame, state, condition)
	if type(frame) ~= "table" then return false, "frame required" end
	if type(state) ~= "string" or not str_match(state, "^[%w%-%_]+$") then
		return false, "invalid state name"
	end
	if type(condition) ~= "string" or condition == "" then
		return false, "condition must be a non-empty string"
	end
	if not RegisterStateDriver then return false, "RegisterStateDriver unavailable" end
	RegisterStateDriver(frame, state, condition)
	stats.drivers = stats.drivers + 1
	return true
end

--- Removes a state driver previously registered on the frame.
--- @param frame table Frame.
--- @param state string State name to unregister.
--- @return boolean True when the API was available and called.
function lib:UnregisterStateDriver(frame, state)
	if not UnregisterStateDriver then return false end
	UnregisterStateDriver(frame, state)
	return true
end

-- Frame pooling -----------------------------------------------------------------

local ACTION_ATTRIBUTES = { "type", "spell", "item", "macro", "macrotext", "action", "unit" }

---@param btn table Secure button whose action attributes are cleared.
local function ClearButton(btn)
	for i = 1, #ACTION_ATTRIBUTES do lib:SetSecureAttribute(btn, ACTION_ATTRIBUTES[i], nil) end
end

--- Acquires a secure button from a named pool, reusing a released button
--- when one is available and creating a new one otherwise. Pooling keeps
--- creation cost and attribute churn near zero for repeated UI (raid
--- frames, action grids). OUT OF COMBAT ONLY: creating, reparenting and
--- reconfiguring protected buttons are combat-locked, so in combat this
--- returns nil, "combat" rather than producing a half-set button.
--- @param poolName string Pool identifier, e.g. "raid-buttons".
--- @param parent table|nil Parent for the button.
--- @param options table|nil Same options as CreateSecureButton; applied
---   fresh to a reused button (previous action attributes are cleared).
--- @return table|nil button, string|nil err
function lib:AcquireButton(poolName, parent, options)
	if type(poolName) ~= "string" or poolName == "" then
		error("LibSecureUI: AcquireButton needs a pool name", 2)
	end
	if InCombatLockdown() then return nil, "combat" end
	local pool = pools[poolName]
	if not pool then pool = { free = {} }; pools[poolName] = pool end
	local btn = pool.free[#pool.free]
	if btn then
		pool.free[#pool.free] = nil
		ClearButton(btn)
		btn:SetParent(parent or UIParent)
		ApplyButtonOptions(btn, options or {})
		btn._lsuiInUse = true
		btn:Show()
		return btn
	end
	btn = self:CreateSecureButton(parent, nil, options)
	btn._lsuiPool, btn._lsuiInUse = poolName, true
	return btn
end

--- Returns a pooled button to its pool: action attributes are cleared
--- and the button is hidden until the next AcquireButton. In combat the
--- release is deferred to the end of combat and false is returned.
--- @param button table Button previously obtained from AcquireButton.
--- @return boolean True when released now, false when deferred/unknown.
function lib:ReleaseButton(button)
	if type(button) ~= "table" or not button._lsuiPool or not button._lsuiInUse then
		return false
	end
	if InCombatLockdown() then
		local btn = button
		Defer(function() lib:ReleaseButton(btn) end)
		return false
	end
	ClearButton(button)
	button:Hide()
	button._lsuiInUse = false
	local pool = pools[button._lsuiPool]
	if pool then pool.free[#pool.free + 1] = button end
	return true
end

-- Secure calls and stats ----------------------------------------------------------

--- Runs a function through SecureCall when it is available, so the call
--- executes without spreading taint into secure code paths; otherwise
--- calls it directly. This does NOT give the function protected-action
--- rights -- it cannot cast spells or target for you; use secure buttons
--- and attributes for that.
--- @param func function Function to call.
--- @param ... any Arguments passed to the function.
--- @return any The function's return values.
function lib:RunSecure(func, ...)
	if type(func) ~= "function" then error("LibSecureUI: RunSecure needs a function", 2) end
	if SecureCall then return SecureCall(func, ...) end
	return func(...)
end

--- Returns library statistics in a fresh table.
--- @return table { buttons, frames, drivers, deferredTotal,
---   deferredPending, pools = { name = freeCount } }.
function lib:GetStats()
	local poolInfo = {}
	for name, pool in pairs(pools) do poolInfo[name] = #pool.free end
	return {
		buttons = stats.buttons, frames = stats.frames, drivers = stats.drivers,
		deferredTotal = stats.deferredTotal, deferredPending = #deferred,
		pools = poolInfo,
	}
end

--- Enables or disables nothing in secure land -- kept for parity with
--- sister libraries: toggles the library's own chat prints.
---@param enabled boolean True to print library debug lines.
function lib:SetDebug(enabled) lib._debug = not not enabled end

---@param fmt string Format string.
---@param ... any Format arguments. Prints only in debug mode.
local function DebugPrint(fmt, ...)
	if lib._debug then print("|cff33ff99LibSecureUI:|r " .. str_format(fmt, ...)) end
end

-- Self-test ---------------------------------------------------------------------

--- Creates (or removes) the secure test button and runs load-time checks.
--- The button casts nothing dangerous: it is a macro button for "/wave".
--- A state driver keeps it shown in and out of combat, so the real check
--- is yours: pull a training dummy, and CLICK IT IN COMBAT. A working
--- secure button waves, with no taint error. Also "/libsecureui test".
function lib:RunTest()
	if testButton then
		testButton:Hide()
		testButton = nil
		print("|cff33ff99LibSecureUI test:|r test button removed")
		return
	end
	if InCombatLockdown() then
		print("|cff33ff99LibSecureUI test:|r run the test out of combat (creation is combat-locked)")
		return
	end
	local btn = self:CreateSecureButton(UIParent, nil, {
		type = "macro", action = "/wave",
		size = { 190, 42 }, text = "LibSecureUI Test",
		tooltip = "Secure test button: click me in combat and I will /wave.",
	})
	btn:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	btn:Show()
	testButton = btn
	local ok, err = self:RegisterStateDriver(btn, "visibility", "[combat] show; show")
	print(str_format("|cff33ff99LibSecureUI test:|r button protected: %s | type attribute: %s | state driver: %s%s",
		tostring(btn.IsProtected and btn:IsProtected() or "unknown"),
		tostring(btn:GetAttribute("type")), tostring(ok), err and (" (" .. err .. ")") or ""))
	local pooled = self:AcquireButton("test-pool", UIParent, { type = "macro", action = "/bow" })
	local pooledOk = pooled ~= nil
	if pooled then self:ReleaseButton(pooled) end
	print(str_format("|cff33ff99LibSecureUI test:|r pool round-trip: %s | deferred pending: %d",
		tostring(pooledOk), #deferred))
	print("|cff33ff99LibSecureUI test:|r now enter combat (training dummy) and click the button: it should /wave with no taint error. Run the command again to remove it.")
	DebugPrint("test button created")
end

-- Slash command (the SLASH_ globals are required by the WoW slash system).
if _G.SlashCmdList then
	_G.SLASH_LIBSECUREUI1 = "/libsecureui"
	_G.SLASH_LIBSECUREUI2 = "/lsui"
	_G.SlashCmdList["LIBSECUREUI"] = function(msg)
		local cmd = str_lower(tostring(msg or ""):match("^%s*(%S+)") or "")
		if cmd == "test" then
			lib:RunTest()
		elseif cmd == "stats" then
			local s = lib:GetStats()
			print(str_format("|cff33ff99LibSecureUI:|r buttons %d, frames %d, drivers %d, deferred pending %d",
				s.buttons, s.frames, s.drivers, s.deferredPending))
		else
			print("|cff33ff99LibSecureUI:|r /libsecureui test | stats")
		end
	end
end

return lib
