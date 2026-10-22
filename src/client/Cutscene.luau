--!strict
-- Cutscenes, videotapes and surveyors talking, played from the story's scenes (LoreText.scene).
-- Each beat is one of: a caption (a title on black), a line of speech (subtitled, click to
-- continue) or a line of narration (what the picture would show). Taps and clicks finish a
-- line that is still typing, then move on. There is no voice yet, so every line is read, and
-- every scene can be skipped.
--
-- A cutscene or tape takes the whole screen; a talk with a surveyor leaves the world visible
-- behind a dim veil. The player is held still while a scene plays (State.menuOpen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Input = require(script.Parent.Input)
local LoreText = require(ReplicatedStorage.Shared.data.LoreText)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local TYPE_CPS = 60 -- characters per second
local CAPTION_SECONDS = 2.4
local FADE_SECONDS = 0.35
local BAR_HEIGHT = 0.12 -- of the screen, top and bottom, for cutscenes and tapes
local ADVANCE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.E] = true,
}

local Cutscene = {}
Cutscene.playing = false

local backdropGui: ScreenGui
local backdrop: Frame
local barTop: Frame
local barBottom: Frame
local gui: ScreenGui
local speakerLabel: TextLabel
local lineLabel: TextLabel
local captionLabel: TextLabel
local promptLabel: TextLabel
local tapper: TextButton
local built = false

local advance = Instance.new("BindableEvent")
local skipped = false
local typing = false
local finishTyping = false
local heldBefore = false

local function build()
	built = true
	backdropGui = Ui.overlay("CutsceneBackdrop", 40)
	backdrop = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = backdropGui,
	})
	barTop = Ui.new("Frame", {
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Visible = false,
		Parent = backdropGui,
	})
	barBottom = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Visible = false,
		Parent = backdropGui,
	})

	gui = Ui.screen("Cutscene", 41)
	gui.Enabled = false
	tapper = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = gui,
	})
	tapper.Activated:Connect(function()
		advance:Fire()
	end)
	captionLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.8, 0, 0, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.large,
		TextTransparency = 1,
		Parent = gui,
	})
	speakerLabel = Ui.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.1, 0, 1, -112),
		Size = UDim2.new(0.8, 0, 0, 20),
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.gold,
		Parent = gui,
	})
	lineLabel = Ui.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.1, 0, 1, -48),
		Size = UDim2.new(0.8, 0, 0, 62),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Ui.text.body,
		Parent = gui,
	})
	promptLabel = Ui.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.9, 0, 1, -26),
		Size = UDim2.fromOffset(260, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		Parent = gui,
	})
	Ui.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(88, 30),
		Text = "SKIP",
		TextSize = Ui.text.small,
		ZIndex = 3,
		Parent = gui,
	}, function()
		skipped = true
		advance:Fire()
	end, Ui.colors.dim)
end

local function fade(object: GuiObject, goal: number, seconds: number)
	TweenService:Create(object, TweenInfo.new(seconds), { BackgroundTransparency = goal }):Play()
end

-- One line of speech or narration, typed out. A press while it types shows the rest.
local function showLine(speaker: string, text: string, narration: boolean)
	speakerLabel.Text = speaker
	lineLabel.Text = text
	lineLabel.TextColor3 = if narration then Ui.colors.dim else Ui.colors.line
	lineLabel.FontFace = if narration then Font.fromEnum(Enum.Font.RobotoMono) else Ui.font
	lineLabel.TextTransparency = 0
	lineLabel.MaxVisibleGraphemes = 0
	promptLabel.Text = ""
	typing = true
	finishTyping = false
	local length = utf8.len(text) or #text
	local shown = 0
	local startedAt = os.clock()
	while shown < length and not finishTyping and not skipped do
		shown = math.min(length, math.floor((os.clock() - startedAt) * TYPE_CPS))
		lineLabel.MaxVisibleGraphemes = shown
		task.wait()
	end
	lineLabel.MaxVisibleGraphemes = -1
	typing = false
	if not skipped then
		promptLabel.Text = "[" .. Input.hint("interact") .. " or click to continue]"
		advance.Event:Wait()
	end
end

local function showCaption(text: string)
	speakerLabel.Text = ""
	lineLabel.Text = ""
	promptLabel.Text = ""
	captionLabel.Text = text
	TweenService:Create(captionLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 0 }):Play()
	local pressed = false
	local connection = advance.Event:Connect(function()
		pressed = true
	end)
	local startedAt = os.clock()
	while not pressed and not skipped and os.clock() - startedAt < CAPTION_SECONDS do
		task.wait()
	end
	connection:Disconnect()
	TweenService:Create(captionLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 1 }):Play()
	task.wait(FADE_SECONDS)
end

-- Plays a scene (LoreText scene id) and calls onDone when it ends or is skipped. A scene that
-- does not exist, or one already playing, just calls onDone.
function Cutscene.play(id: string, onDone: (() -> ())?)
	local scene = LoreText.scene(id)
	if scene == nil or Cutscene.playing then
		if onDone then
			onDone()
		end
		return
	end
	if not built then
		build()
	end
	Cutscene.playing = true
	skipped = false
	heldBefore = State.menuOpen
	State.menuOpen = true
	Input.menuChanged()

	local filmed = scene.kind ~= "dialogue"
	backdrop.Visible = true
	barTop.Visible = filmed
	barBottom.Visible = filmed
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	fade(backdrop, if filmed then 0 else 0.55, FADE_SECONDS)
	gui.Enabled = true
	if Input.device == "gamepad" then
		Ui.focus(tapper)
	end

	local keyConnection = UserInputService.InputBegan:Connect(
		function(input: InputObject, _processed: boolean)
			if ADVANCE_KEYS[input.KeyCode] then
				if typing then
					finishTyping = true
				else
					advance:Fire()
				end
			end
		end
	)
	local tapConnection = tapper.Activated:Connect(function()
		if typing then
			finishTyping = true
		end
	end)

	task.spawn(function()
		task.wait(FADE_SECONDS)
		if scene.kind == "tape" then
			showCaption("TAPE: " .. string.upper(scene.title))
		end
		for _, beat in scene.beats do
			if skipped then
				break
			end
			if beat.cap ~= nil then
				showCaption(beat.cap)
			elseif beat.sp ~= nil and beat.line ~= nil then
				showLine(string.upper(beat.sp), beat.line, false)
			elseif beat.shot ~= nil then
				showLine("", beat.shot, true)
			end
		end
		keyConnection:Disconnect()
		tapConnection:Disconnect()
		speakerLabel.Text = ""
		lineLabel.Text = ""
		promptLabel.Text = ""
		gui.Enabled = false
		barTop.Visible = false
		barBottom.Visible = false
		fade(backdrop, 1, FADE_SECONDS)
		task.wait(FADE_SECONDS)
		backdrop.Visible = false
		Ui.focus(nil)
		State.menuOpen = heldBefore
		Input.menuChanged()
		Cutscene.playing = false
		if onDone then
			onDone()
		end
	end)
end

return Cutscene
