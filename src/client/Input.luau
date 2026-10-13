--!strict
-- One input layer for mouse and keyboard, gamepad and touch. Other controllers read
-- Input.firing / focusing / sprinting and subscribe to one-shot actions; none of them look
-- at devices directly. On touch the scan and focus buttons toggle by default, so the right
-- thumb stays free to look around (Roblox is mostly mobile: this has to be comfortable).

local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

export type Device = "keyboard" | "gamepad" | "touch"

local Input = {}

Input.firing = false
Input.focusing = false
Input.sprinting = false
Input.device = "keyboard" :: Device

local actionListeners: { [string]: { () -> () } } = {}
local touchGui: ScreenGui? = nil
local touchButtons: { [string]: TextButton } = {}

-- Words for the current device, used by hints: Input.hint("fire") -> "Hold LEFT MOUSE".
local HINTS: { [string]: { [Device]: string } } = {
	fire = { keyboard = "Hold LEFT MOUSE", gamepad = "Hold RT", touch = "Tap SCAN" },
	focus = { keyboard = "Hold RIGHT MOUSE", gamepad = "Hold LT", touch = "Tap FOCUS" },
	sprint = { keyboard = "Hold SHIFT", gamepad = "Click the left stick", touch = "Tap RUN" },
	ping = { keyboard = "Press G", gamepad = "Press Y", touch = "Tap PING" },
	interact = { keyboard = "Press E", gamepad = "Press X", touch = "Tap the prompt" },
	lens = { keyboard = "Press V", gamepad = "Press D-pad up", touch = "Tap LENS" },
}

function Input.hint(action: string): string
	return HINTS[action][Input.device]
end

-- Subscribes to a one-shot action: "ping", "lens", "photo", "emote", "map".
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

local function togglesOnTouch(): boolean
	local mode = State.profile.settings.scanMode
	return mode == "toggle" or (mode == "auto" and Input.device == "touch")
end

local function refreshTouchButtons()
	for name, button in touchButtons do
		local on = (name == "fire" and Input.firing)
			or (name == "focus" and Input.focusing)
			or (name == "sprint" and Input.sprinting)
		button.BackgroundColor3 = if on then Ui.colors.line else Ui.colors.panel
		button.TextColor3 = if on then Ui.colors.ink else Ui.colors.line
	end
end

-- Applies a press or release to one of the held states, honouring toggle mode.
local function setHeld(name: string, pressed: boolean, toggle: boolean)
	local current = (Input :: any)[name] :: boolean
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
	(Input :: any)[name] = value
	refreshTouchButtons()
end

-- Releases everything: used when a menu opens or the player is caught.
function Input.releaseAll()
	Input.firing = false
	Input.focusing = false
	Input.sprinting = false
	refreshTouchButtons()
end

local function bindHeld(action: string, field: string, ...: Enum.KeyCode | Enum.UserInputType)
	ContextActionService:BindAction(
		action,
		function(_, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin or state == Enum.UserInputState.End then
				local gamepadToggle = input.KeyCode == Enum.KeyCode.ButtonL3
				setHeld(
					field,
					state == Enum.UserInputState.Begin,
					togglesOnTouch() or gamepadToggle
				)
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
	-- Laid out around the bottom-right corner, where the jump button would otherwise be.
	local held = {
		{ name = "fire", text = "SCAN", size = 96, x = -26, y = -28 },
		{ name = "focus", text = "FOCUS", size = 70, x = -136, y = -24 },
		{ name = "sprint", text = "RUN", size = 62, x = -34, y = -138 },
	}
	for _, spec in held do
		local button = round(spec.name, spec.text, spec.size, spec.x, spec.y)
		touchButtons[spec.name] = button
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				setHeld(spec.name, true, togglesOnTouch())
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				setHeld(spec.name, false, togglesOnTouch())
			end
		end)
	end
	local presses = {
		{ name = "ping", text = "PING", size = 54, x = -118, y = -108 },
		{ name = "lens", text = "LENS", size = 46, x = -214, y = -34 },
		{ name = "emote", text = "SAY", size = 46, x = -112, y = -176 },
	}
	for _, spec in presses do
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
		touchButtons.lens.Visible = (State.profile.upgrades.lens or 0) > 0
		touchButtons.ping.Visible = stage == "level"
		touchButtons.emote.Visible = State.server.partySize > 1
	end
end

function Input.start()
	Input.device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then "touch"
		else "keyboard"
	buildTouchControls()

	bindHeld("LidarFire", "firing", Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	bindHeld(
		"LidarFocus",
		"focusing",
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.F,
		Enum.KeyCode.ButtonL2
	)
	bindHeld("LidarSprint", "sprinting", Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	bindPress(
		"LidarPing",
		"ping",
		Enum.KeyCode.G,
		Enum.UserInputType.MouseButton3,
		Enum.KeyCode.ButtonY
	)
	bindPress("LidarLens", "lens", Enum.KeyCode.V, Enum.KeyCode.DPadUp)
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
