--!nolint
--[[ =============================================================
  KAYSER  |  full-stack executor utility  (single file, Luau)
  layers:  core -> executor abstraction -> services
           -> feature registry -> part-flood engine
           -> widget kit -> pages -> persistence
  RIGHT SHIFT = toggle UI        END = unload + restore world
============================================================= ]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local TweenService     = game:GetService("TweenService")
local StarterGui       = game:GetService("StarterGui")
local HttpService      = game:GetService("HttpService")

local PLR = Players.LocalPlayer
local CAM = workspace.CurrentCamera

local function try(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local ENV = try(getgenv) or _G
if ENV.__KAYSER_LOADED then try(ENV.__KAYSER_UNLOAD) end

--==============================================================
-- 1. executor abstraction (never touch raw globals again)
--==============================================================
local Toast
local IO = { ok = false, dir = "Kayser" }
pcall(function() IO.write, IO.read, IO.exists = writefile, readfile, isfile end)
IO.ok = IO.write ~= nil and IO.read ~= nil
if IO.ok and isfolder and not isfolder(IO.dir) then pcall(makefolder, IO.dir) end

local function notify(text, dur)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "KAYSER", Text = text, Duration = dur or 3 })
	end)
	if Toast then Toast(text) end
end

local function hook(signal, fn) return signal:Connect(fn) end

--==============================================================
-- 2. state
--==============================================================
local State = {
	esp = false, fullbright = false, noclip = false, fly = false,
	speed = 16, jump = 50, waypoints = {}, conns = {}, flyParts = nil, light = nil,
}
local Widgets = { toggles = {}, sliders = {} }
local ESP = {}   -- [player] = {objects}
local Features = {}

--==============================================================
-- 3. UI kit
--==============================================================
local C = {
	bg = Color3.fromRGB(15, 16, 21), panel = Color3.fromRGB(25, 27, 34),
	stroke = Color3.fromRGB(48, 52, 62), text = Color3.fromRGB(233, 235, 241),
	dim = Color3.fromRGB(146, 152, 165), accent = Color3.fromRGB(96, 165, 250),
	on = Color3.fromRGB(52, 211, 153), off = Color3.fromRGB(62, 66, 78),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local Gui = new("ScreenGui", {
	Name = "Kayser", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local host = try(gethui) or StarterGui
if not pcall(function() Gui.Parent = host end) then
	Gui.Parent = PLR:WaitForChild("PlayerGui")
end

local win = new("Frame", {
	Size = UDim2.fromOffset(440, 560), Position = UDim2.fromScale(.5, .5),
	AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = C.bg, BorderSizePixel = 0,
}, Gui)
corner(win, 10)
new("UIStroke", { Color = C.stroke, Thickness = 1 }, win)

local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, win)
corner(bar, 10)
new("TextLabel", {
	Size = UDim2.new(1, -100, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "KAYSER  ·  full stack",
}, bar)

local toastLbl = new("TextLabel", {
	Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 1, -30),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
	TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1,
}, win)
function Toast(text)
	toastLbl.Text = text
	TweenService:Create(toastLbl, TweenInfo.new(.12), { TextTransparency = 0 }):Play()
	task.delay(2.2, function()
		TweenService:Create(toastLbl, TweenInfo.new(.4), { TextTransparency = 1 }):Play()
	end)
end

-- drag
do
	local dragging, startPos, startFrame
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			win.Position = UDim2.fromOffset(win.AbsolutePosition.X, win.AbsolutePosition.Y)
			startPos, startFrame = i.Position, win.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
			local d = i.Position - startPos
			win.Position = UDim2.fromOffset(startFrame.X.Offset + d.X, startFrame.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

-- tab bar + pages
local tabBar = new("Frame", { Position = UDim2.fromOffset(10, 48), Size = UDim2.new(1, -20, 0, 30), BackgroundTransparency = 1 }, win)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, tabBar)
local pageHost = new("Frame", { Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 1, -96), BackgroundTransparency = 1 }, win)

local pageButtons, pages = {}, {}
local function page(name)
	local btn = new("TextButton", {
		Size = UDim2.fromOffset(64, 28), BackgroundColor3 = C.panel, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.dim, Text = name,
	}, tabBar)
	corner(btn)
	local frame = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, pageHost)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	new("UIPadding", { PaddingBottom = UDim.new(0, 20) }, frame)
	pages[name] = frame
	pageButtons[name] = btn
	btn.MouseButton1Click:Connect(function()
		for n, f in pairs(pages) do f.Visible = (n == name) end
		for n, b in pairs(pageButtons) do b.TextColor3 = (n == name) and C.text or C.dim end
	end)
	return frame
end

local function selectPage(name)
	for n, f in pairs(pages) do f.Visible = (n == name) end
	for n, b in pairs(pageButtons) do b.TextColor3 = (n == name) and C.text or C.dim end
end

local function header(p, text)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Text = text,
	}, p)
end

local function toggle(p, label, default, cb)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, p)
	corner(r)
	new("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, r)
	local pill = new("TextButton", {
		Size = UDim2.fromOffset(36, 18), Position = UDim2.new(1, -46, .5, 0), AnchorPoint = Vector2.new(0, .5),
		BackgroundColor3 = C.off, BorderSizePixel = 0, Text = "",
	}, r)
	corner(pill, 9)
	local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.text, BorderSizePixel = 0 }, pill)
	corner(knob, 7)
	local on = default
	local function render()
		pill.BackgroundColor3 = on and C.on or C.off
		knob.Position = UDim2.fromOffset(on and 20 or 2, 2)
	end
	local function set(v)
		on = v
		render()
		task.spawn(cb, v)
	end
	pill.MouseButton1Click:Connect(function() set(not on) end)
	render()
	Widgets.toggles[label] = { set = function(v) on = v; render() end }
end

local function slider(p, label, min, max, default, cb)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, p)
	corner(r)
	new("TextLabel", {
		Size = UDim2.new(1, -80, 0, 20), Position = UDim2.fromOffset(10, 4), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, r)
	local out = new("TextLabel", {
		Size = UDim2.fromOffset(60, 20), Position = UDim2.new(1, -70, 0, 4), BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(default),
	}, r)
	local track = new("Frame", {
		Size = UDim2.new(1, -20, 0, 5), Position = UDim2.new(0, 10, 0, 34),
		BackgroundColor3 = C.off, BorderSizePixel = 0,
	}, r)
	corner(track, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0 }, track)
	corner(fill, 3)
	local val, dragging = default, false
	local function render()
		fill.Size = UDim2.fromScale(math.clamp((val - min) / (max - min), 0, 1), 1)
		out.Text = tostring(val)
	end
	local function apply(x)
		local f = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local raw = min + f * (max - min)
		val = (max - min) >= 20 and math.round(raw) or math.floor(raw * 10 + .5) / 10
		render()
		cb(val)
	end
	track.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			apply(i.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			apply(i.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function() dragging = false end)
	render()
	Widgets.sliders[label] = { set = function(v) val = v; render() end }
end

local function button(p, label, cb)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.panel, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text, Text = label,
	}, p)
	corner(b)
	b.MouseButton1Click:Connect(function() task.spawn(cb) end)
	return b
end

local function divider(p)
	return new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.stroke, BorderSizePixel = 0, LayoutOrder = 50 }, p)
end

--==============================================================
-- 4. features
--==============================================================
local function charPart()
	local ch = PLR.Character
	return ch, ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end

-- ESP ---------------------------------------------------------
local function clearOne(plr)
	local set = ESP[plr]
	if not set then return end
	for _, o in pairs(set) do pcall(function() o:Destroy() end) end
	ESP[plr] = nil
end

local function buildOne(plr)
	if plr == PLR or ESP[plr] then return end
	local ch = plr.Character
	if not (ch and ch:FindFirstChild("Head")) then return end
	local set = {}
	set.hl = new("Highlight", {
		Name = "KAYSER_ESP", Adornee = ch, FillColor = C.accent, FillTransparency = .7,
		OutlineColor = Color3.new(1, 1, 1), DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = ch,
	})
	set.gui = new("BillboardGui", {
		Name = "KAYSER_ESP_NAME", Adornee = ch.Head, Size = UDim2.fromOffset(220, 30),
		StudsOffset = Vector3.new(0, 2.4, 0), AlwaysOnTop = true, Parent = ch.Head,
	})
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = .4,
		Text = plr.Name .. "  [" .. math.floor((charPart() and PLR:DistanceFromCharacter(ch.Head.Position)) or 0) .. "m]",
	}, set.gui)
	ESP[plr] = set
end

local espCharConn = {}
function Features.esp(on)
	State.esp = on
	for _, p in Players:GetPlayers() do
		if on then buildOne(p) else clearOne(p) end
		if on and not espCharConn[p] then
			espCharConn[p] = p.CharacterAdded:Connect(function()
				task.wait(.6)
				if State.esp then buildOne(p) end
			end)
		end
	end
	if on then
		local acc = 0
		State.conns.espRefresh = hook(RunService.Heartbeat, function(dt)
			acc += dt
			if acc < 1 then return end
			acc = 0
			for p in pairs(ESP) do buildOne(p) end
		end)
	else
		if State.conns.espRefresh then State.conns.espRefresh:Disconnect() end
	end
	notify("ESP " .. (on and "on" or "off"))
end

-- fullbright ---------------------------------------------------
function Features.fullbright(on)
	State.fullbright = on
	if on then
		State.light = {
			Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
			Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd,
		}
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		Lighting.FogEnd = 100000
	elseif State.light then
		for k, v in pairs(State.light) do Lighting[k] = v end
		State.light = nil
	end
end

-- noclip -------------------------------------------------------
function Features.noclip(on)
	State.noclip = on
	if State.conns.noclip then State.conns.noclip:Disconnect() end
	if on then
		State.conns.noclip = hook(RunService.Stepped, function()
			local ch = PLR.Character
			if not ch then return end
			for _, p in ipairs(ch:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end)
	else
		local _, _, hum = charPart()
		if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
	end
end

-- fly ----------------------------------------------------------
function Features.fly(on)
	State.fly = on
	local ch, hrp = charPart()
	if on then
		if not hrp then notify("no character"); State.fly = false; return end
		local bv = new("BodyVelocity", { Name = "KAYSER_FLY", MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = hrp })
		local bg = new("BodyGyro", { Name = "KAYSER_FLY_GYRO", MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2000, D = 60, Parent = hrp })
		State.flyParts = { bv, bg }
		State.conns.fly = hook(RunService.RenderStepped, function()
			local _, root = charPart()
			if not root or not bv.Parent then return end
			local cf = CAM.CFrame
			local move = Vector3.zero
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cf.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cf.LookVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cf.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cf.RightVector end
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
			bv.Velocity = move.Magnitude > 0 and move.Unit * (State.speed * 3) or Vector3.zero
			bg.CFrame = cf
		end)
	else
		if State.conns.fly then State.conns.fly:Disconnect() end
		if State.flyParts then
			for _, o in ipairs(State.flyParts) do pcall(function() o:Destroy() end) end
			State.flyParts = nil
		end
	end
end

-- speed / jump -------------------------------------------------
function Features.speed(v)
	State.speed = v
	local _, _, hum = charPart()
	if hum then hum.WalkSpeed = v end
end

function Features.jump(v)
	State.jump = v
	local _, _, hum = charPart()
	if hum then
		hum.UseJumpPower = true
		hum.JumpPower = v
	end
end

-- waypoints ----------------------------------------------------
local function persistWaypoints()
	if not IO.ok then return end
	local out = {}
	for name, cf in pairs(State.waypoints) do
		out[name] = { cf:GetComponents() }
	end
	pcall(IO.write, IO.dir .. "/waypoints.json", HttpService:JSONEncode(out))
end

function Features.loadWaypoints()
	if not IO.ok or not IO.exists(IO.dir .. "/waypoints.json") then return end
	local ok, data = pcall(IO.read, IO.dir .. "/waypoints.json")
	if not ok or not data then return end
	local ok2, dec = pcall(function() return HttpService:JSONDecode(data) end)
	if not ok2 then return end
	for name, c in pairs(dec) do
		local ok3, cf = pcall(CFrame.new, table.unpack(c))
		if ok3 then State.waypoints[name] = cf end
	end
end

function Features.saveWaypoint(name)
	local _, hrp = charPart()
	if not hrp or name == "" then return notify("invalid waypoint") end
	State.waypoints[name] = hrp.CFrame
	persistWaypoints()
	notify("saved: " .. name)
end

function Features.teleport(cf)
	local ch = charPart()
	if not ch or not cf then return end
	pcall(function() ch:PivotTo(cf + Vector3.new(0, 3, 0)) end)
end

function Features.teleportMouse()
	local ray = CAM:ViewportPointToRay(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { PLR.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	Features.teleport(CFrame.new(res and res.Position or (ray.Origin + ray.Direction * 200)))
end

function Features.teleportPlayer(name)
	local t = Players:FindFirstChild(name)
	local ch = t and t.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then Features.teleport(hrp.CFrame) end
end

--==============================================================
-- 4b. part flood engine
--==============================================================
local PartCrash = {
	running = false, busy = false, created = 0, fires = 0, inflight = 0,
	cands = {}, selected = nil, variant = "cframe", prefix = {},
	budget = 4000, rate = 400, localMode = false, anchored = true,
	countConn = nil, loopThread = nil, target = "",
}

if workspace:FindFirstChild("KayserSpam") then workspace.KayserSpam:Destroy() end
local spamFolder = new("Folder", { Name = "KayserSpam", Parent = workspace })

local function isOurs(inst)
	local p = inst
	while p and p ~= workspace do
		if p == spamFolder or p == PLR.Character then return true end
		p = p.Parent
	end
	return false
end

local KEYWORDS = {
	"part", "build", "place", "spawn", "create", "add", "draw", "block",
	"brick", "make", "paint", "item", "object", "cube", "prop", "model", "plot",
}

local function scoreName(name)
	local n = name:lower()
	local s = 0
	for _, k in ipairs(KEYWORDS) do if n:find(k, 1, true) then s += 10 end end
	if name:find("^R?F_") then s += 1 end
	return s
end

local function pool()
	local out = {}
	for _, root in ipairs({ game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				out[#out + 1] = { obj = d, score = scoreName(d.Name) }
			end
		end
	end
	table.sort(out, function(a, b) return a.score > b.score end)
	return out
end

function PartCrash.stop(reason)
	if not PartCrash.running then return end
	PartCrash.running = false
	if PartCrash.countConn then PartCrash.countConn:Disconnect() PartCrash.countConn = nil end
	notify(("stopped [%s] · %d fires · %d parts"):format(reason or "manual", PartCrash.fires, PartCrash.created), 4)
	PartCrash.fires = 0
end

local function buildPayload(cf)
	local v = PartCrash.variant
	if v == "cframe" then return cf end
	if v == "pos" then return cf.Position end
	if v == "table_cf" then return { cframe = cf, CFrame = cf } end
	if v == "cf_size" then return cf, Vector3.new(2, 2, 2) end
	if v == "name_cf" then return "Part", cf end
	if v == "double" then return cf, cf end
	return { name = "Part", cframe = cf, size = Vector3.new(2, 2, 2), Color = Color3.new(1, 0, 0) }
end

local function fire(cand, cf)
	local o = cand.obj
	local args = {}
	for i = 1, #PartCrash.prefix do args[#args + 1] = PartCrash.prefix[i] end
	local p1, p2 = buildPayload(cf)
	args[#args + 1] = p1
	if p2 ~= nil then args[#args + 1] = p2 end
	if o:IsA("RemoteEvent") then
		pcall(o.FireServer, o, table.unpack(args))
	else
		if PartCrash.inflight > 40 then return false end
		PartCrash.inflight += 1
		task.spawn(function()
			pcall(o.InvokeServer, o, table.unpack(args))
			PartCrash.inflight -= 1
		end)
	end
	PartCrash.fires += 1
	return true
end

local function targetCF(name)
	local plr = name ~= "" and Players:FindFirstChild(name) or nil
	local ch = plr and plr.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.CFrame end
	local _, mine = charPart()
	return mine and mine.CFrame or CFrame.new()
end

local function jitter(base, spread)
	return base * CFrame.new(
		(math.random() - .5) * spread,
		(math.random() - .5) * spread,
		(math.random() - .5) * spread
	) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
end

-- probe: fire once per shape, count parts the server actually made
function PartCrash.probe()
	if PartCrash.busy or not PartCrash.selected then return notify("select a remote first") end
	PartCrash.busy = true
	local ok, err = pcall(function()
		local bestShape, bestHits = nil, 0
		local shapes = { "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }
		for _, shape in ipairs(shapes) do
			PartCrash.variant = shape
			local hits, conn = 0, workspace.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") and not isOurs(d) then hits += 1 end
			end)
			fire(PartCrash.selected, targetCF(PartCrash.target))
			task.wait(.35)
			conn:Disconnect()
			if hits > bestHits then bestShape, bestHits = shape, hits end
			if hits > 0 then break end
		end
		PartCrash.variant = bestShape or "cframe"
		if bestHits > 0 then
			notify(("hit · payload=%s · +%d parts"):format(bestShape, bestHits), 5)
		else
			notify("no shape produced parts — try another remote", 5)
		end
	end)
	PartCrash.busy = false
	if not ok then notify("probe errored: " .. tostring(err)) end
	if PartCrash.render then PartCrash.render() end
end

function PartCrash.start(name)
	if PartCrash.running then return notify("already flooding") end
	if not PartCrash.selected and not PartCrash.localMode then return notify("no remote selected") end
	PartCrash.created, PartCrash.fires = 0, 0
	PartCrash.running = true
	local base = targetCF(name)
	local budget = PartCrash.budget

	PartCrash.countConn = workspace.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") or isOurs(d) then return end
		PartCrash.created += 1
		if PartCrash.created >= budget then PartCrash.stop("budget") end
	end)

	PartCrash.loopThread = task.spawn(function()
		while PartCrash.running do
			if PartCrash.localMode then
				for _ = 1, PartCrash.rate do
					if not PartCrash.running then break end
					new("Part", {
						Name = "KayserPart", Anchored = PartCrash.anchored,
						CanCollide = not PartCrash.anchored, CanQuery = false, CanTouch = false,
						Size = Vector3.new(2, 2, 2),
						Color = Color3.fromHSV(math.random(), .8, 1),
						CFrame = jitter(base, 12), Parent = spamFolder,
					})
					PartCrash.created += 1
					if PartCrash.created >= budget then PartCrash.stop("budget") break end
				end
			else
				for _ = 1, PartCrash.rate do
					if not PartCrash.running then break end
					fire(PartCrash.selected, jitter(base, 8))
				end
			end
			task.wait(1)
		end
	end)
	notify(("flooding %s @ %d/s · cap %d"):format(name ~= "" and name or "server", PartCrash.rate, budget), 4)
end

function PartCrash.wipe()
	local n = #spamFolder:GetChildren()
	spamFolder:ClearAllChildren()
	notify(("wiped %d local parts"):format(n))
end

--==============================================================
-- 5. pages
--==============================================================
local pMain = page("main")
local pVis  = page("visuals")
local pMove = page("movement")
local pTp   = page("teleport")
local pCfg  = page("config")
local pCrash = page("crash")
selectPage("main")

header(pMain, "session")
button(pMain, "Rejoin server", function()
	game:GetService("TeleportService"):Teleport(game.PlaceId, PLR)
end)
button(pMain, "Copy JobId", function()
	pcall(setclipboard, game.JobId)
	notify("JobId copied")
end)
button(pMain, "Unload (restore world)", function() try(ENV.__KAYSER_UNLOAD) end)
divider(pMain)
header(pMain, "info")
new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
	TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true, Text = "Right Shift toggles the UI · END unloads · persistence: " .. (IO.ok and "enabled" or "unavailable"),
}, pMain)

header(pVis, "player esp")
toggle(pVis, "ESP", false, Features.esp)
toggle(pVis, "Fullbright", false, Features.fullbright)

header(pMove, "movement")
slider(pMove, "WalkSpeed", 8, 250, 16, Features.speed)
slider(pMove, "JumpPower", 30, 300, 50, Features.jump)
toggle(pMove, "Noclip", false, Features.noclip)
toggle(pMove, "Fly (WASD / Space / LCTRL)", false, Features.fly)

header(pTp, "waypoints")
local wpRow = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, pTp)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, wpRow)
local wpBox = new("TextBox", {
	Size = UDim2.new(1, -80, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text, PlaceholderText = "waypoint name", Text = "",
}, wpRow)
corner(wpBox)
local wpSave = new("TextButton", {
	Size = UDim2.fromOffset(74, 30), BackgroundColor3 = C.accent, BorderSizePixel = 0,
	Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.bg, Text = "save",
}, wpRow)
corner(wpSave)
wpSave.MouseButton1Click:Connect(function() Features.saveWaypoint(wpBox.Text) end)

local wpList = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, pTp)
new("UIListLayout", { Padding = UDim.new(0, 4) }, wpList)

function Features.renderWaypoints()
	for _, c in ipairs(wpList:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for name, cf in pairs(State.waypoints) do
		local b = button(wpList, "→ " .. name, function() Features.teleport(cf) end)
		b.Size = UDim2.new(1, -80, 0, 26)
		local del = new("TextButton", {
			Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -74, 0, 0),
			BackgroundColor3 = C.off, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
			TextSize = 11, TextColor3 = C.text, Text = "del",
		}, wpList)
		corner(del)
		del.MouseButton1Click:Connect(function()
			State.waypoints[name] = nil
			persistWaypoints()
			Features.renderWaypoints()
		end)
	end
end

header(pTp, "mouse / players")
button(pTp, "Teleport to mouse", Features.teleportMouse)

local plrList = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, pTp)
new("UIListLayout", { Padding = UDim.new(0, 4) }, plrList)

local function refreshPlayers()
	for _, c in ipairs(plrList:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= PLR then
			button(plrList, "→ " .. p.Name, function() Features.teleportPlayer(p.Name) end)
		end
	end
end

local lastRoster = ""
task.spawn(function()
	while Gui.Parent do
		local sig = ""
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= PLR then sig ..= p.Name .. "|" end
		end
		if sig ~= lastRoster then
			lastRoster = sig
			refreshPlayers()
		end
		task.wait(1)
	end
end)

header(pCfg, "config store")
button(pCfg, "Save settings", function()
	local data = { esp = State.esp, fullbright = State.fullbright, noclip = State.noclip,
		fly = State.fly, speed = State.speed, jump = State.jump }
	if IO.ok then
		pcall(IO.write, IO.dir .. "/config.json", HttpService:JSONEncode(data))
		notify("settings saved")
	else
		notify("no filesystem")
	end
end)
button(pCfg, "Load settings", function()
	if not IO.ok then return notify("no filesystem") end
	local ok, raw = pcall(IO.read, IO.dir .. "/config.json")
	if not ok then return notify("no config") end
	local ok2, d = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok2 then return end
	local tmap = { ESP = "esp", Fullbright = "fullbright", Noclip = "noclip" }
	for key, w in pairs(Widgets.toggles) do
		local f = tmap[key]
		if f and d[f] ~= nil then w.set(d[f]) end
	end
	local smap = { WalkSpeed = "speed", JumpPower = "jump" }
	for key, w in pairs(Widgets.sliders) do
		local f = smap[key]
		if f and d[f] then w.set(d[f]); Features[f](d[f]) end
	end
	notify("settings loaded")
end)
divider(pCfg)
header(pCfg, "debug")
local logLbl = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
	TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = "ready",
}, pCfg)
local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
	logLbl.Text = table.concat(parts, " ")
end

-- crash page ---------------------------------------------------
header(pCrash, "target")
local ctBox = new("TextBox", {
	Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
	PlaceholderText = "player name  (blank = server centre)", Text = "",
}, pCrash)
corner(ctBox)

header(pCrash, "remotes")
local candList = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 116), BackgroundColor3 = C.bg, BorderSizePixel = 0,
	ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pCrash)
corner(candList)
new("UIListLayout", { Padding = UDim.new(0, 3) }, candList)
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4) }, candList)

function PartCrash.render()
	for _, c in ipairs(candList:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
	end
	for i = 1, math.min(#PartCrash.cands, 40) do
		local entry = PartCrash.cands[i]
		local sel = (PartCrash.selected == entry)
		local row = new("TextButton", {
			Size = UDim2.new(1, -8, 0, 22), BackgroundColor3 = sel and C.accent or C.panel,
			BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 11,
			TextColor3 = sel and C.bg or C.dim, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = ("%s%s  [%d]"):format(entry.obj:IsA("RemoteFunction") and "RF " or "RE ", entry.obj:GetFullName(), entry.score),
		}, candList)
		corner(row, 4)
		row.MouseButton1Click:Connect(function()
			PartCrash.selected = entry
			PartCrash.render()
			notify("selected " .. entry.obj.Name)
		end)
	end
	if #PartCrash.cands == 0 then
		new("TextLabel", {
			Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
			Text = "  nothing searched yet",
		}, candList)
	end
end

button(pCrash, "1 · Search remotes", function()
	PartCrash.cands = pool()
	PartCrash.selected = nil
	PartCrash.render()
	local named = 0
	for _, e in ipairs(PartCrash.cands) do if e.score >= 10 then named += 1 end end
	notify(("%d remotes · %d build-named"):format(#PartCrash.cands, named), 4)
end)

button(pCrash, "2 · Probe payload shapes", function()
	PartCrash.target = ctBox.Text
	PartCrash.probe()
end)

local shapeBtn = button(pCrash, "payload: cframe", function()
	local cycles = { "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }
	for i, s in ipairs(cycles) do
		if s == PartCrash.variant then
			PartCrash.variant = cycles[(i % #cycles) + 1]
			break
		end
	end
	shapeBtn.Text = "payload: " .. PartCrash.variant
end)

local preBox = new("TextBox", {
	Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.panel, BorderSizePixel = 0,
	Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
	PlaceholderText = "prefix args, comma separated (e.g. 5,wood)", Text = "",
}, pCrash)
corner(preBox)
preBox.FocusLost:Connect(function()
	PartCrash.prefix = {}
	for piece in preBox.Text:gmatch("[^,]+") do
		piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
		PartCrash.prefix[#PartCrash.prefix + 1] = tonumber(piece) or piece
	end
	notify(("%d prefix args"):format(#PartCrash.prefix))
end)

divider(pCrash)
header(pCrash, "flood")
slider(pCrash, "Rate (fires / parts per sec)", 50, 2000, 400, function(v) PartCrash.rate = v end)
slider(pCrash, "Part budget", 200, 40000, 4000, function(v) PartCrash.budget = math.floor(v) end)
toggle(pCrash, "Local mode (no remote)", false, function(v)
	PartCrash.localMode = v
	notify(v and "local mode: your client only" or "remote mode")
end)
toggle(pCrash, "Unanchored (violent)", false, function(v) PartCrash.anchored = not v end)

button(pCrash, "3 · Flood target", function() PartCrash.start(ctBox.Text) end)
button(pCrash, "Stop", function() PartCrash.stop("manual") end)
button(pCrash, "Wipe local parts", PartCrash.wipe)

local pcLbl = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.Code,
	TextSize = 11, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "idle",
}, pCrash)
task.spawn(function()
	while Gui.Parent do
		if PartCrash.running then
			pcLbl.TextColor3 = C.on
			pcLbl.Text = ("RUN  fires %d · parts %d / %d"):format(PartCrash.fires, PartCrash.created, PartCrash.budget)
		else
			pcLbl.TextColor3 = C.dim
			pcLbl.Text = ("idle · selected %s · variant %s"):format(
				PartCrash.selected and PartCrash.selected.obj.Name or "none", PartCrash.variant)
		end
		task.wait(.4)
	end
end)

--==============================================================
-- 6. input + lifecycle
--==============================================================
State.conns.uinput = UserInputService.InputBegan:Connect(function(i, gp)
	if gp then return end
	if not Gui.Parent then return end
	if i.KeyCode == Enum.KeyCode.RightShift then
		Gui.Enabled = not Gui.Enabled
	elseif i.KeyCode == Enum.KeyCode.End then
		try(ENV.__KAYSER_UNLOAD)
	elseif i.KeyCode == Enum.KeyCode.Home then
		Gui.Enabled = true
		selectPage("main")
	end
end)

local function onChar()
	if State.fly then Features.fly(false); Features.fly(true) end
	task.delay(.5, function()
		local _, _, hum = charPart()
		if hum then
			hum.WalkSpeed = State.speed
			hum.UseJumpPower = true
			hum.JumpPower = State.jump
		end
	end)
end
State.conns.char = PLR.CharacterAdded:Connect(onChar)

local origSpeed = 16
do
	local _, _, hum = charPart()
	if hum then origSpeed = hum.WalkSpeed end
end

ENV.__KAYSER_UNLOAD = function()
	State.esp = false; State.fly = false; State.noclip = false; State.fullbright = false
	for _, c in pairs(State.conns) do pcall(function() c:Disconnect() end) end
	for p in pairs(ESP) do clearOne(p) end
	for _, c in pairs(espCharConn) do c:Disconnect() end
	if State.flyParts then for _, o in ipairs(State.flyParts) do pcall(function() o:Destroy() end) end end
	if State.light then for k, v in pairs(State.light) do Lighting[k] = v end end
	PartCrash.running = false
	if PartCrash.countConn then PartCrash.countConn:Disconnect() end
	if spamFolder then spamFolder:Destroy() end
	local _, _, hum = charPart()
	if hum then hum.WalkSpeed = origSpeed end
	Gui:Destroy()
	ENV.__KAYSER_LOADED = nil
	ENV.__KAYSER_UNLOAD = nil
	notify("unloaded", 2)
end
ENV.__KAYSER_LOADED = true

--==============================================================
-- 7. boot
--==============================================================
Features.loadWaypoints()
Features.renderWaypoints()
Features.speed(State.speed)
Features.jump(State.jump)
PartCrash.render()
notify("KAYSER loaded · RightShift = UI · END = unload", 4)
log("executor:", (identifyexecutor and identifyexecutor()) or "unknown", "| io:", IO.ok and "yes" or "no")
notify(IO.ok and "persistence ready" or "no filesystem: config disabled", 5)