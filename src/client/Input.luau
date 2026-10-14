--!strict
-- One input layer for mouse and keyboard, gamepad and touch. Other controllers read
-- Input.firing / sprinting / crouching and subscribe to one-shot actions; none of them look
-- at devices directly. On touch the scan, run and crouch buttons toggle by default, so the
-- right thumb stays free to look around (Roblox is mostly mobile: this has to be comfortable).

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

export type Device = "keyboard" | "gamepad" | "touch"
type HeldField = "firing" | "sprinting" | "crouching"

local Input = {}

Input.firing = false
Input.sprinting = false
Input.crouching = false
Input.device = "keyboard" :: Device

local actionListeners: { [string]: { () -> () } } = {}
local touchGui: ScreenGui? = nil
local touchButtons: { [string]: TextButton } = {}

-- Words for the current device, used by hints: Input.hint("fire") -> "Hold LEFT MOUSE".
local HINTS: { [string]: { [Device]: string } } = {
	fire = { keyboard = "Hold LEFT MOUSE", gamepad = "Hold RT", touch = "Tap SCAN" },
	sweep = { keyboard = "Press RIGHT MOUSE", gamepad = "Press LT", touch = "Tap SWEEP" },
	spread = { keyboard = "Scroll", gamepad = "Press LB or RB", touch = "Tap SPREAD" },
	crouch = { keyboard = "Hold CTRL or press C", gamepad = "Press B", touch = "Tap CROUCH" },
	sprint = { keyboard = "Hold SHIFT", gamepad = "Click the left stick", touch = "Tap RUN" },
	ping = { keyboard = "Press G", gamepad = "Press Y", touch = "Tap PING" },
	interact = { keyboard = "Press E", gamepad = "Press X", touch = "Tap the prompt" },
}

-- Keys that toggle a held state instead of holding it.
local TOGGLE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonL3] = true, -- sprint
	[Enum.KeyCode.C] = true, -- crouch
	[Enum.KeyCode.ButtonB] = true, -- crouch
}

-- Touch controls, laid out around the bottom-right corner where the jump button would be.
-- x and y are the offset of each button's bottom-right corner from the screen's.
local TOUCH_HELD = {
	{ name = "fire", field = "firing" :: HeldField, text = "SCAN", size = 96, x = -26, y = -28 },
	{
		name = "sprint",
		field = "sprinting" :: HeldField,
		text = "RUN",
		size = 58,
		x = -34,
		y = -138,
	},
	{
		name = "crouch",
		field = "crouching" :: HeldField,
		text = "CROUCH",
		size = 58,
		x = -216,
		y = -28,
	},
}
local TOUCH_PRESS = {
	{ name = "sweep", text = "SWEEP", size = 70, x = -136, y = -24 },
	{ name = "ping", text = "PING", size = 50, x = -112, y = -118 },
	{ name = "spreadCycle", text = "SPREAD", size = 46, x = -178, y = -108 },
	{ name = "emote", text = "SAY", size = 46, x = -104, y = -182 },
}

function Input.hint(action: string): string
	local words = HINTS[action]
	return if words then words[Input.device] else ""
end

-- Subscribes to a one-shot action: "sweep", "spreadIn", "spreadOut", "spreadCycle", "ping",
-- "photo", "emote", "map".
function Input.onAction(name: string, listener: () -> ())
	local list = actionListeners[name]
	if list == nil then
		list = {}
		actionListeners[name] = list
	end
	table.insert(list, listener)
end

local function fire(name: string)
	if State.menuOpen then
		return
	end
	for _, listener in actionListeners[name] or {} do
		task.spawn(listener)
	end
end

-- The scan button follows the scan-mode setting; run and crouch always toggle on touch.
local function scanToggles(): boolean
	local mode = State.profile.settings.scanMode
	return mode == "toggle" or (mode == "auto" and Input.device == "touch")
end

local function refreshTouchButtons()
	for _, spec in TOUCH_HELD do
		local button = touchButtons[spec.name]
		if button then
			local on = (Input :: any)[spec.field] == true
			button.BackgroundColor3 = if on then Ui.colors.line else Ui.colors.panel
			button.TextColor3 = if on then Ui.colors.ink else Ui.colors.line
		end
	end
end

-- Applies a press or release to one of the held states, honouring toggle mode. Sprinting
-- and crouching cancel each other.
local function setHeld(field: HeldField, pressed: boolean, toggle: boolean)
	local current = (Input :: any)[field] :: boolean
	local value = current
	if toggle then
		if pressed then
			value = not current
		end
	else
		value = pressed
	end
	if State.menuOpen then
		value = false
	end
	(Input :: any)[field] = value
	if value and field == "sprinting" then
		Input.crouching = false
	elseif value and field == "crouching" then
		Input.sprinting = false
	end
	refreshTouchButtons()
end

-- Releases everything: used when a menu opens or the player is caught.
function Input.releaseAll()
	Input.firing = false
	Input.sprinting = false
	Input.crouching = false
	refreshTouchButtons()
end

local function bindHeld(
	action: string,
	field: HeldField,
	toggleOnTouch: () -> boolean,
	...: Enum.KeyCode | Enum.UserInputType
)
	ContextActionService:BindAction(
		action,
		function(_, state: Enum.UserInputState, input: InputObject)
			-- Fingers only ever press the on-screen buttons, which handle themselves: a touch
			-- reaching here as well would toggle the same control a second time.
			local fromFinger = input.UserInputType == Enum.UserInputType.Touch
			if
				not fromFinger
				and (state == Enum.UserInputState.Begin or state == Enum.UserInputState.End)
			then
				local toggle = toggleOnTouch() or TOGGLE_KEYS[input.KeyCode] == true
				setHeld(field, state == Enum.UserInputState.Begin, toggle)
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		...
	)
end

local function bindPress(action: string, name: string, ...: Enum.KeyCode | Enum.UserInputType)
	ContextActionService:BindAction(action, function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			fire(name)
		end
		return Enum.ContextActionResult.Pass
	end, false, ...)
end

local function never(): boolean
	return false
end

local function buildTouchControls()
	local gui = Ui.screen("TouchControls", 5)
	gui.Enabled = false
	touchGui = gui
	local function round(name: string, text: string, size: number, x: number, y: number): TextButton
		local button = Ui.new("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, x, 1, y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Ui.colors.panel,
			BackgroundTransparency = 0.25,
			AutoButtonColor = false,
			FontFace = Ui.fontBold,
			TextSize = Ui.text.small,
			TextColor3 = Ui.colors.line,
			Text = text,
			Parent = gui,
		}, {
			Ui.new("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Ui.new("UIStroke", { Color = Ui.colors.line, Transparency = 0.5, Thickness = 1.5 }),
		})
		return button
	end
	for _, spec in TOUCH_HELD do
		local button = round(spec.name, spec.text, spec.size, spec.x, spec.y)
		touchButtons[spec.name] = button
		local function toggles(): boolean
			return spec.field ~= "firing" or scanToggles()
		end
		-- A finger, or a mouse click on a touch-layout screen. Each press is tracked by its own
		-- input object so a second finger elsewhere can never release or double-toggle this one.
		local pressing: InputObject? = nil
		button.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if
				pressing == nil
				and (kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1)
			then
				pressing = input
				setHeld(spec.field, true, toggles())
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input == pressing then
				pressing = nil
				setHeld(spec.field, false, toggles())
			end
		end)
	end
	for _, spec in TOUCH_PRESS do
		local button = round(spec.name, spec.text, spec.size, spec.x, spec.y)
		touchButtons[spec.name] = button
		button.Activated:Connect(function()
			fire(spec.name)
		end)
	end
end

local function refreshDevice()
	local last = UserInputService:GetLastInputType()
	local device: Device = Input.device
	if last == Enum.UserInputType.Touch then
		device = "touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		device = "gamepad"
	elseif last == Enum.UserInputType.Keyboard or last.Name:sub(1, 5) == "Mouse" then
		device = "keyboard"
	end
	Input.device = device
	local gui = touchGui
	if gui then
		local stage = State.server.stage
		gui.Enabled = device == "touch" and stage ~= "title" and not State.menuOpen
		touchButtons.ping.Visible = stage == "level"
		touchButtons.emote.Visible = State.server.partySize > 1
	end
end

function Input.start()
	Input.device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "touch"
		else "keyboard"
	buildTouchControls()

	bindHeld(
		"LidarFire",
		"firing",
		scanToggles,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	bindHeld("LidarSprint", "sprinting", never, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	bindHeld(
		"LidarCrouch",
		"crouching",
		never,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonB
	)
	bindPress(
		"LidarSweep",
		"sweep",
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonL2
	)
	bindPress("LidarSpreadIn", "spreadIn", Enum.KeyCode.Z, Enum.KeyCode.ButtonL1)
	bindPress("LidarSpreadOut", "spreadOut", Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
	-- The wheel only reports a direction: up narrows the spread, down widens it.
	ContextActionService:BindAction(
		"LidarSpreadWheel",
		function(_, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Change and input.Position.Z ~= 0 then
				fire(if input.Position.Z > 0 then "spreadIn" else "spreadOut")
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.UserInputType.MouseWheel
	)
	bindPress(
		"LidarPing",
		"ping",
		Enum.KeyCode.G,
		Enum.UserInputType.MouseButton3,
		Enum.KeyCode.ButtonY
	)
	bindPress("LidarPhoto", "photo", Enum.KeyCode.P, Enum.KeyCode.DPadRight)
	bindPress("LidarEmote", "emote", Enum.KeyCode.B, Enum.KeyCode.DPadDown)
	bindPress("LidarMap", "map", Enum.KeyCode.M, Enum.KeyCode.DPadLeft)

	UserInputService.LastInputTypeChanged:Connect(refreshDevice)
	State.onState(refreshDevice)
	State.onProfile(refreshDevice)
	-- With a mouse, the scan button and "click the prompt" are the same click, so prompts
	-- answer only to their key there. On touch, tapping the prompt is how they are used.
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		prompt.ClickablePrompt = Input.device == "touch"
	end)
	-- A window losing focus can swallow the release event; never leave the scanner stuck on.
	UserInputService.WindowFocusReleased:Connect(Input.releaseAll)
	Players.LocalPlayer.CharacterAdded:Connect(Input.releaseAll)
	refreshDevice()
end

-- Menus call this when they open or close so the touch controls hide and inputs release.
function Input.menuChanged()
	if State.menuOpen then
		Input.releaseAll()
	end
	refreshDevice()
end

return Input
