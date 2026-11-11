--!strict
-- Cutscenes, videotapes and camp talks, played from the story's scenes (LoreText.scene).
-- A scene is a list of beats; each is one of: a caption (a title), a line of speech (subtitled,
-- click to continue), a staging cue (Stage.luau draws the picture and says how long the scene
-- should wait for it) or, for a cutscene with no picture, a line of narration.
--
--   Cutscene.play(id, onDone, options)
--     options (optional): { values = { name = "text or number" }, keep = function(beat) -> bool }
--       values fills {name} in lines and captions; keep returning false drops a beat.
--
-- Three kinds of scene:
--   filmed     any scene with a `stage` (an office, a videotape on a CRT, the lamp room) or
--              any cutscene: the whole screen, letterbox bars, subtitles on a dark band.
--   camp talk  a "dialogue" with no stage: the world stays visible behind a light veil, and a
--              lit portrait of whoever speaks slides in beside the subtitles.
--   unknown    a scene whose `stage` Stage does not know has no picture: black, with the
--              scene's `shot` lines read as narration.
-- The player is held still while a scene plays (State.menuOpen). Every scene can be skipped:
-- hold Q (or B on a gamepad) for half a second, or press SKIP on a touch screen. If the player
-- leaves the stage the scene was started in (a friend opened the intake door, the run ended),
-- a filmed scene ends at once.
--
-- In Studio, `workspace:SetAttribute("DevScene", "tape.hollis")` plays that scene at once, from
-- any stage of the game; "" and then the id again replays it; "all" plays every scene in
-- LoreText.scenes in order. The scene itself is exactly what a player gets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Audio = require(script.Parent.Audio)
local Hud = require(script.Parent.Hud)
local Input = require(script.Parent.Input)
local LoreText = require(ReplicatedStorage.Shared.data.LoreText)
local Stage = require(script.Parent.Stage)
local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local TYPE_CPS = 60 -- characters per second
local CAPTION_SECONDS = 2.4
local FADE_SECONDS = 0.35
local BAR_HEIGHT = 0.12 -- of the screen, top and bottom, for filmed scenes
local THIN_BAR_HEIGHT = 0.05 -- for a camp talk
local VEIL_TRANSPARENCY = 0.75 -- a camp talk darkens the world by a quarter
local STRIP_HEIGHT = 150 -- the dark band under the subtitles, in interface pixels
local PORTRAIT_SIZE = 124
local SKIP_HOLD_SECONDS = 0.5
local TICK_EVERY = 3 -- a soft tick as every third character types
local CRT_SCRATCH = 48 -- grey frames in the static
local ADVANCE_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.E] = true,
}
local SKIP_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Q] = true,
	[Enum.KeyCode.ButtonB] = true,
}
local DEV_ATTRIBUTE = "DevScene"

export type Options = {
	values: { [string]: string | number }?,
	keep: ((beat: LoreText.Beat) -> boolean)?,
}

local Cutscene = {}
Cutscene.playing = false

local backdropGui: ScreenGui
local backdrop: Frame
local barTop: Frame
local barBottom: Frame
local gui: ScreenGui
local tapper: TextButton
local strip: Frame
local captionBand: Frame
local speakerLabel: TextLabel
local lineLabel: TextLabel
local captionLabel: TextLabel
local promptLabel: TextLabel
local skipHint: TextLabel
local skipBack: Frame
local skipFill: Frame
local portraitHolder: Frame
local built = false

local advance = Instance.new("BindableEvent")
local skipped = false
local typing = false
local finishTyping = false
local heldBefore = false
local cursorBefore = true
local skipHeldSince: number? = nil
local sceneStage = ""
local sceneFilmed = false
local staticLayer: Frame? = nil
local deadGlow: Frame? = nil

local function build()
	built = true
	backdropGui = Ui.overlay("CutsceneBackdrop", 60) -- above the red aura and the fade (50)
	backdropGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	backdrop = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
		Parent = backdropGui,
	})
	barTop = Ui.new("Frame", {
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = backdropGui,
	})
	barBottom = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, BAR_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = backdropGui,
	})

	gui = Ui.screen("Cutscene", 61)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	tapper = Ui.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
		Parent = gui,
	})
	tapper.Activated:Connect(function()
		advance:Fire()
	end)
	-- the dark band the subtitles sit on, and the one behind a caption
	strip = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, STRIP_HEIGHT),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	captionBand = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.45),
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	captionLabel = Ui.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.8, 0, 0, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Ui.fontBold,
		TextSize = Ui.text.large,
		TextTransparency = 1,
		ZIndex = 3,
		Parent = gui,
	})
	speakerLabel = Ui.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.1, 0, 1, -118),
		Size = UDim2.new(0.8, 0, 0, 20),
		FontFace = Ui.fontBold,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.gold,
		ZIndex = 3,
		Parent = gui,
	})
	lineLabel = Ui.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.1, 0, 1, -48),
		Size = UDim2.new(0.8, 0, 0, 62),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = Ui.text.body,
		ZIndex = 3,
		Parent = gui,
	})
	promptLabel = Ui.label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.9, 0, 1, -22),
		Size = UDim2.fromOffset(260, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		ZIndex = 3,
		Parent = gui,
	})
	portraitHolder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(-0.3, 0, 1, -STRIP_HEIGHT - 6),
		Size = UDim2.fromOffset(PORTRAIT_SIZE, PORTRAIT_SIZE),
		BackgroundColor3 = Color3.fromRGB(22, 24, 30),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 3,
		Parent = gui,
	}, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Ui.new("UIStroke", { Color = Ui.colors.gold, Transparency = 0.4, Thickness = 2 }),
	})
	Ui.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(88, 30),
		Text = "SKIP",
		TextSize = Ui.text.small,
		ZIndex = 4,
		Parent = gui,
	}, function()
		skipped = true
		advance:Fire()
	end, Ui.colors.dim)
	-- hold Q to skip: the hint fills while the key is held
	skipHint = Ui.label({
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.fromOffset(190, 16),
		TextSize = Ui.text.small,
		TextColor3 = Ui.colors.dim,
		ZIndex = 4,
		Parent = gui,
	})
	skipBack = Ui.new("Frame", {
		Position = UDim2.new(0, 16, 0, 32),
		Size = UDim2.fromOffset(150, 3),
		BackgroundColor3 = Ui.colors.line,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = gui,
	})
	skipFill = Ui.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Ui.colors.gold,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = skipBack,
	})
	-- A friend opened the intake door, the run ended: a filmed scene ends where it stands.
	State.onState(function(server)
		if Cutscene.playing and sceneFilmed and server.stage ~= sceneStage then
			skipped = true
			advance:Fire()
		end
	end)
end

--------------------------------------------------------------------------------------------
-- The television a tape is watched on

-- Returns the screen (where the stage goes) and a function that tears it down. The static is
-- grey frames re-scattered every frame; the dead glow is what is left when the tape ends.
local function buildScreen(): (Frame, () -> ())
	local crt = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
		Parent = backdropGui,
	}, {
		Ui.new("UIAspectRatioConstraint", { AspectRatio = 1.33 }),
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 28) }),
		Ui.new("UIStroke", { Color = Color3.fromRGB(60, 62, 66), Thickness = 8 }),
	})
	deadGlow = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(34, 40, 48),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = crt,
	})
	local flicker = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.96,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = crt,
	})
	for line = 0, 23 do
		Ui.new("Frame", {
			Position = UDim2.fromScale(0, line / 24),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = crt,
		})
	end
	local noise = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(70, 72, 76),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 7,
		Parent = crt,
	})
	staticLayer = noise
	local scratches: { Frame } = {}
	for _ = 1, CRT_SCRATCH do
		table.insert(
			scratches,
			Ui.new("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
				ZIndex = 8,
				Parent = noise,
			})
		)
	end
	local connection = RunService.RenderStepped:Connect(function()
		flicker.BackgroundTransparency = 0.93 + math.random() * 0.06
		if noise.Visible then
			for _, scratch in scratches do
				local grey = 0.25 + math.random() * 0.7
				scratch.BackgroundColor3 = Color3.new(grey, grey, grey)
				scratch.BackgroundTransparency = math.random() * 0.4
				scratch.Position = UDim2.fromScale(math.random() * 0.9, math.random())
				scratch.Size = UDim2.fromScale(0.1 + math.random() * 0.5, math.random() * 0.06)
			end
		end
	end)
	return crt,
		function()
			connection:Disconnect()
			staticLayer = nil
			deadGlow = nil
			crt:Destroy()
		end
end

local function setStatic(on: boolean)
	local layer = staticLayer
	if layer then
		layer.Visible = on
	end
end

-- A burst of static with its hiss: the tape starting, a cue, or the tape ending.
local function staticBurst(seconds: number)
	setStatic(true)
	Audio.click()
	Audio.sequence({ 2.2, 1.9, 2.4, 2.0, 2.3, 1.8, 2.5, 2.1, 2.3, 1.9 }, seconds / 10, 0.12)
	task.wait(seconds)
	setStatic(false)
end

--------------------------------------------------------------------------------------------
-- Words

local function fade(object: GuiObject, goal: number, seconds: number)
	TweenService:Create(object, TweenInfo.new(seconds), { BackgroundTransparency = goal }):Play()
end

local function fill(text: string, options: Options?): string
	local values = if options then options.values else nil
	if values == nil then
		return text
	end
	local result = string.gsub(text, "{([%w_]+)}", function(name: string): string?
		local value = values[name]
		if value == nil then
			return nil
		end
		return tostring(value)
	end)
	return result
end

local function clearText()
	speakerLabel.Text = ""
	lineLabel.Text = ""
	promptLabel.Text = ""
	fade(strip, 1, 0.15)
end

-- Waits `seconds`, ignoring clicks and keys. Only SKIP (or the stage changing) ends it early.
local function hold(seconds: number)
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime and not skipped do
		task.wait()
	end
end

-- Slides the portrait in from the speaker's side and shows them.
local portrait: Stage.Portrait? = nil
local portraitSide = ""

local function showPortrait(speaker: string, seconds: number)
	local shown = portrait
	if shown == nil then
		return
	end
	local side = if speaker == "Theo" then "right" else "left"
	local resting = if side == "right"
		then UDim2.new(0.94, -PORTRAIT_SIZE, 1, -STRIP_HEIGHT - 6)
		else UDim2.new(0.06, 0, 1, -STRIP_HEIGHT - 6)
	local away = if side == "right"
		then UDim2.new(1.2, 0, 1, -STRIP_HEIGHT - 6)
		else UDim2.new(-0.3, 0, 1, -STRIP_HEIGHT - 6)
	if portraitSide ~= side then
		portraitSide = side
		portraitHolder.Position = away
		portraitHolder.Visible = true
		TweenService:Create(
			portraitHolder,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = resting }
		):Play()
	end
	shown.show(speaker)
	shown.talk(seconds)
end

-- One line of speech or narration, typed out. A press while it types shows the rest.
local function showLine(speaker: string, text: string, narration: boolean)
	speakerLabel.Text = string.upper(speaker)
	local length = utf8.len(text) or #text
	local seconds = length / TYPE_CPS
	if not narration then
		Stage.speak(speaker, seconds)
		showPortrait(speaker, seconds)
	end
	fade(strip, 0.4, 0.15)
	lineLabel.Text = text
	lineLabel.TextColor3 = if narration then Ui.colors.dim else Ui.colors.line
	lineLabel.FontFace = if narration then Font.fromEnum(Enum.Font.RobotoMono) else Ui.font
	lineLabel.TextTransparency = 0
	lineLabel.MaxVisibleGraphemes = 0
	promptLabel.Text = ""
	typing = true
	finishTyping = false
	local shown = 0
	local ticked = 0
	local startedAt = os.clock()
	while shown < length and not finishTyping and not skipped do
		shown = math.min(length, math.floor((os.clock() - startedAt) * TYPE_CPS))
		lineLabel.MaxVisibleGraphemes = shown
		if shown - ticked >= TICK_EVERY then
			ticked = shown
			Audio.blip(1.7 + math.random() * 0.3, 0.05)
		end
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
	fade(strip, 1, 0.1)
	captionLabel.Text = text
	if text == "LIDAR" then
		Audio.arrive(false)
		Audio.sequence({ 0.5, 0.38 }, 0.16, 0.55)
	end
	TweenService:Create(captionLabel, TweenInfo.new(FADE_SECONDS), { TextTransparency = 0 }):Play()
	fade(captionBand, 0.35, FADE_SECONDS)
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
	fade(captionBand, 1, FADE_SECONDS)
	task.wait(FADE_SECONDS)
end

--------------------------------------------------------------------------------------------
-- Skipping

local function updateSkipHint()
	local since = skipHeldSince
	if since == nil then
		skipFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local share = (os.clock() - since) / SKIP_HOLD_SECONDS
	skipFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	if share >= 1 and not skipped then
		skipped = true
		advance:Fire()
	end
end

--------------------------------------------------------------------------------------------
-- Playing a scene

local function firstSpeaker(beats: { LoreText.Beat }): string?
	for _, beat in beats do
		if beat.sp ~= nil and beat.sp ~= "Theo" then
			return beat.sp
		end
	end
	return nil
end

-- Plays a scene (LoreText scene id) and calls onDone when it ends or is skipped. A scene that
-- does not exist, or one already playing, just calls onDone.
function Cutscene.play(id: string, onDone: (() -> ())?, options: Options?)
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
	skipHeldSince = nil
	portraitSide = ""
	heldBefore = State.menuOpen
	cursorBefore = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false -- no pointer over the picture
	State.menuOpen = true
	Input.menuChanged()
	Hud.setCutscene(true)

	local beats: { LoreText.Beat } = {}
	for _, beat in scene.beats do
		local wanted = true
		if options and options.keep then
			local ok, answer = pcall(options.keep :: (LoreText.Beat) -> boolean, beat)
			wanted = not ok or answer ~= false
		end
		if wanted then
			table.insert(beats, beat)
		end
	end

	local staged = scene.stage ~= nil
	local filmed = staged or scene.kind ~= "dialogue"
	sceneFilmed = filmed
	sceneStage = State.server.stage
	local kind = scene.kind
	backdrop.Visible = true
	barTop.Visible = true
	barBottom.Visible = true
	local barSize = if filmed then BAR_HEIGHT else THIN_BAR_HEIGHT
	barTop.Size = UDim2.fromScale(1, barSize)
	barBottom.Size = UDim2.fromScale(1, barSize)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	fade(backdrop, if filmed then 0 else VEIL_TRANSPARENCY, FADE_SECONDS)
	gui.Enabled = true
	captionLabel.TextTransparency = 1
	captionBand.BackgroundTransparency = 1
	strip.BackgroundTransparency = 1
	portraitHolder.Visible = false
	if Input.device == "gamepad" then
		Ui.focus(tapper)
	end
	-- a hint for the skip key, filling while it is held (a touch screen has its button)
	local onTouch = Input.device == "touch"
	skipHint.Visible = not onTouch
	skipHint.Text = "[" .. (if Input.device == "gamepad" then "B" else "Q") .. "] hold to skip"
	skipFill.Size = UDim2.fromScale(0, 1)
	skipBack.Visible = not onTouch

	local closeScreen: (() -> ())? = nil
	local pictured = false
	local tapeScreen = false
	if staged then
		local container: GuiObject = backdrop
		if scene.stage == "tape" then
			local crt, close = buildScreen()
			container = crt
			closeScreen = close
			tapeScreen = true
		end
		pictured = Stage.open(container, scene.stage :: string, scene.id, firstSpeaker(beats))
		if not pictured and closeScreen then
			closeScreen()
			closeScreen = nil
			tapeScreen = false
		end
	end
	local narrate = not pictured and kind == "cutscene"
	if not filmed and not staged then
		portrait = Stage.openPortrait(portraitHolder)
	end
	if filmed then
		Audio.muffle(true) -- the maze's drone drops away under a filmed scene
	end

	local keyConnection = UserInputService.InputBegan:Connect(
		function(input: InputObject, _processed: boolean)
			if ADVANCE_KEYS[input.KeyCode] then
				if typing then
					finishTyping = true
				else
					advance:Fire()
				end
			elseif SKIP_KEYS[input.KeyCode] and skipHeldSince == nil then
				skipHeldSince = os.clock()
			end
		end
	)
	local keyEndConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		if SKIP_KEYS[input.KeyCode] then
			skipHeldSince = nil
		end
	end)
	local tapConnection = tapper.Activated:Connect(function()
		if typing then
			finishTyping = true
		end
	end)
	local skipConnection = RunService.Heartbeat:Connect(updateSkipHint)

	local function runBeat(beat: LoreText.Beat)
		if beat.cap ~= nil then
			showCaption(fill(beat.cap, options))
		elseif beat.sp ~= nil and beat.line ~= nil then
			showLine(beat.sp, fill(beat.line, options), false)
		elseif beat.stage ~= nil then
			clearText()
			local seconds = Stage.run(beat.stage)
			if tapeScreen and beat.stage == "static" then
				-- the picture dies under static and the screen stays dark for the rest of the tape
				setStatic(true)
				Audio.click()
				Audio.sequence({ 2.3, 1.9, 2.5, 2.0, 2.4, 1.8, 2.2, 2.0 }, 0.1, 0.14)
				hold(math.max(seconds, 0.9))
				setStatic(false)
				local glow = deadGlow
				if glow then
					glow.Visible = true
				end
			elseif seconds > 0 then
				hold(seconds)
			end
		elseif beat.shot ~= nil and narrate then
			showLine("", beat.shot, true) -- a scene with no picture reads its shots instead
		end
	end

	task.spawn(function()
		local ok, problem = pcall(function()
			task.wait(FADE_SECONDS)
			if kind == "tape" and pictured then
				-- half a second of static, then the title alone
				staticBurst(0.5)
				showCaption(string.upper(scene.title))
			elseif kind == "tape" then
				showCaption(string.upper(scene.title))
			end
			for _, beat in beats do
				if skipped then
					break
				end
				local fine, trouble = pcall(runBeat, beat)
				if not fine then
					warn("Cutscene beat:", trouble) -- a beat that errors is passed over
				end
			end
			if not skipped then
				hold(Stage.settle())
			end
			if tapeScreen and not skipped then
				local glow = deadGlow
				if glow == nil or not glow.Visible then
					staticBurst(0.5)
				end
			end
		end)
		if not ok then
			warn("Cutscene:", problem)
		end
		keyConnection:Disconnect()
		keyEndConnection:Disconnect()
		tapConnection:Disconnect()
		skipConnection:Disconnect()
		-- the picture fades out with the screen instead of cutting to black
		local picture = Stage.frame()
		if picture and not tapeScreen then
			TweenService:Create(
				picture,
				TweenInfo.new(FADE_SECONDS),
				{ ImageTransparency = 1, BackgroundTransparency = 1 }
			):Play()
		end
		if tapeScreen then
			Stage.close()
			if closeScreen then
				closeScreen()
			end
		end
		speakerLabel.Text = ""
		lineLabel.Text = ""
		promptLabel.Text = ""
		captionLabel.TextTransparency = 1
		captionBand.BackgroundTransparency = 1
		strip.BackgroundTransparency = 1
		skipHint.Text = ""
		skipFill.Size = UDim2.fromScale(0, 1)
		local shownPortrait = portrait
		if shownPortrait then
			shownPortrait.close()
			portrait = nil
		end
		portraitHolder.Visible = false
		gui.Enabled = false
		fade(backdrop, 1, FADE_SECONDS)
		task.wait(FADE_SECONDS)
		Stage.close()
		barTop.Visible = false
		barBottom.Visible = false
		backdrop.Visible = false
		Ui.focus(nil)
		if filmed then
			Audio.muffle(false)
		end
		UserInputService.MouseIconEnabled = cursorBefore
		State.menuOpen = heldBefore
		Input.menuChanged()
		Hud.setCutscene(false)
		sceneFilmed = false
		Cutscene.playing = false
		if onDone then
			onDone()
		end
	end)
end

-- Ends the scene now, as if the player had skipped it. Does nothing when none is playing.
function Cutscene.skip()
	if Cutscene.playing then
		skipped = true
		advance:Fire()
	end
end

--------------------------------------------------------------------------------------------
-- Studio: watch a scene without playing to it

if RunService:IsStudio() then
	local request = 0
	workspace:GetAttributeChangedSignal(DEV_ATTRIBUTE):Connect(function()
		request += 1
		local mine = request
		local value = workspace:GetAttribute(DEV_ATTRIBUTE)
		if type(value) ~= "string" or value == "" then
			return
		end
		task.spawn(function()
			local waited = 0
			while Cutscene.playing and waited < 4 do
				Cutscene.skip()
				waited += task.wait(0.1)
			end
			if request ~= mine then
				return
			end
			if value == "all" then
				for _, scene in LoreText.scenes do
					if request ~= mine then
						return
					end
					local done = false
					Cutscene.play(scene.id, function()
						done = true
					end)
					while not done and request == mine do
						task.wait(0.1)
					end
				end
			else
				Cutscene.play(value)
			end
		end)
	end)
end

return Cutscene
