print("[K] start")
local ok0, err0 = xpcall(function()

--==========================================================
-- services
--==========================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Tween = game:GetService("TweenService")
local SG = game:GetService("StarterGui")
local HS = game:GetService("HttpService")
local VIM = game:GetService("VirtualInputManager")
local TS = game:GetService("TeleportService")
local Stats = game:GetService("Stats")

local PLR = Players.LocalPlayer
local CAM = workspace.CurrentCamera
if not CAM then CAM = workspace:WaitForChild("Camera", 10) or workspace.CurrentCamera end
if not CAM then error("no camera") end
print("[K] services ok")

local function try(fn, ...)
	local a, b, c = pcall(fn, ...)
	if a then return b, c end
end

local ENV = try(getgenv) or _G
if ENV.__K_UNLOAD then pcall(ENV.__K_UNLOAD) end

local EX = {
	hook = try(hookmetamethod), mt = try(getrawmetatable),
	click = try(mouse1click), clip = try(setclipboard), fps = try(setfpscap),
	draw = try(function() return type(Drawing) == "table" and Drawing or nil end),
	who = try(identifyexecutor),
}
local IO = { ok = false, dir = "Kayser" }
pcall(function() IO.w, IO.r, IO.e = writefile, readfile, isfile end)
IO.ok = IO.w ~= nil and IO.r ~= nil
if IO.ok and isfolder and not isfolder(IO.dir) then pcall(makefolder, IO.dir) end
print("[K] caps: hook", EX.hook ~= nil, "draw", EX.draw ~= nil, "io", IO.ok)

local Toast
local function note(t, d)
	pcall(function() SG:SetCore("SendNotification", { Title = "KAYSER", Text = t, Duration = d or 3 }) end)
	if Toast then Toast(t) end
end
local function bind(s, f) return s:Connect(f) end

local S = {
	esp = false, fb = false, noclip = false, fly = false, ij = false, av = false,
	voidY = -60, safe = nil, bSpd = 16, bJmp = 50, bFov = 70, aSpd = 0, aJmp = 0,
	wps = {}, cn = {}, flyParts = nil, light = nil, dead = false,
}
local W = { t = {}, s = {} }
local ESP, HB, F = {}, {}, {}

--==========================================================
-- palette + gui
--==========================================================
local C = {
	bg = Color3.fromRGB(14, 15, 20), bar = Color3.fromRGB(19, 21, 27),
	pane = Color3.fromRGB(27, 30, 38), card = Color3.fromRGB(22, 24, 31),
	line = Color3.fromRGB(45, 49, 61), txt = Color3.fromRGB(234, 236, 242),
	dim = Color3.fromRGB(140, 147, 162), acc = Color3.fromRGB(120, 150, 255),
	on = Color3.fromRGB(70, 220, 155), off = Color3.fromRGB(58, 63, 75),
	warn = Color3.fromRGB(250, 175, 75),
}
local function mk(cls, props, parent)
	local o = Instance.new(cls)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function crn(o, r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local gui = mk("ScreenGui", {
	Name = "Kayser", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local pg = PLR:FindFirstChildOfClass("PlayerGui") or PLR:WaitForChild("PlayerGui", 10)
if pg then
	gui.Parent = pg
else
	local h = try(gethui)
	gui.Parent = h or game:GetService("CoreGui")
end
print("[K] gui parent:", gui.Parent and gui.Parent:GetFullName() or "NIL")

local win = mk("Frame", {
	Size = UDim2.fromOffset(600, 400), Position = UDim2.fromScale(.5, .5),
	AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = C.bg,
	BorderSizePixel = 0, Parent = gui,
})
crn(win, 10)
mk("UIStroke", { Color = C.line, Thickness = 1 }, win)

local top = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.bar, BorderSizePixel = 0, Parent = win })
crn(top, 10)
mk("TextLabel", {
	Size = UDim2.fromOffset(200, 34), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.txt,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "KAYSER", Parent = top,
})
mk("TextLabel", {
	Size = UDim2.fromOffset(150, 34), Position = UDim2.new(1, -162, 0, 0), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 9, TextColor3 = C.dim,
	TextXAlignment = Enum.TextXAlignment.Right, Text = "RSHIFT UI | END unload", Parent = top,
})

local toastLbl = mk("TextLabel", {
	Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -24),
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 10,
	TextColor3 = C.acc, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, Parent = win,
})
function Toast(t)
	toastLbl.Text = t
	Tween:Create(toastLbl, TweenInfo.new(.1), { TextTransparency = 0 }):Play()
	task.delay(2.2, function()
		Tween:Create(toastLbl, TweenInfo.new(.35), { TextTransparency = 1 }):Play()
	end)
end

do
	local dn, p0, f0
	top.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dn = true
			win.Position = UDim2.fromOffset(win.AbsolutePosition.X, win.AbsolutePosition.Y)
			p0, f0 = i.Position, win.Position
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dn and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - p0
			win.Position = UDim2.fromOffset(f0.X.Offset + d.X, f0.Y.Offset + d.Y)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dn = false end
	end)
end

local tabs = mk("Frame", { Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 0, 26), BackgroundTransparency = 1, Parent = win })
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, tabs)
local pane = mk("Frame", { Position = UDim2.fromOffset(8, 70), Size = UDim2.new(1, -16, 1, -76), BackgroundTransparency = 1, Parent = win })

local foot = mk("TextLabel", {
	Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 1, -42), BackgroundTransparency = 1,
	Font = Enum.Font.Code, TextSize = 9, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "booting", Parent = win,
})

local pages, tbtns = {}, {}
local pick
local function tab(name, label)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(58, 26), BackgroundColor3 = C.pane, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 10, TextColor3 = C.dim, Text = label, Parent = tabs,
	})
	crn(b, 6)
	local f = mk("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = pane,
	})
	mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	mk("UIPadding", { PaddingBottom = UDim.new(0, 16) }, f)
	pages[name], tbtns[name] = f, b
	b.MouseButton1Click:Connect(function() pick(name) end)
	return f
end

pick = function(sel)
	for n, f in pairs(pages) do f.Visible = (n == sel) end
	for n, b in pairs(tbtns) do
		b.TextColor3 = (n == sel) and C.txt or C.dim
		b.BackgroundColor3 = (n == sel) and C.acc or C.pane
	end
end

local function card(p, h)
	local c = mk("Frame", {
		Size = UDim2.new(1, 0, 0, h or 0),
		AutomaticSize = h and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card, BorderSizePixel = 0, Parent = p,
	})
	crn(c, 7)
	mk("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, c)
	mk("UIListLayout", { Padding = UDim.new(0, 4) }, c)
	return c
end
local function hdr(p, t)
	return mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 9, TextColor3 = C.acc, TextXAlignment = Enum.TextXAlignment.Left, Text = t:upper(), Parent = p,
	})
end
local function lbl(p, t, h)
	return mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, h or 14), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = 9, TextColor3 = C.dim, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Text = t, Parent = p,
	})
end
local function tog(p, label, default, cb)
	local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = C.pane, BorderSizePixel = 0, Parent = p })
	crn(r, 5)
	mk("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.txt,
		TextXAlignment = Enum.TextXAlignment.Left, Text = label, Parent = r,
	})
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(28, 15), Position = UDim2.new(1, -36, .5, 0), AnchorPoint = Vector2.new(0, .5),
		BackgroundColor3 = C.off, BorderSizePixel = 0, Text = "", Parent = r,
	})
	crn(b, 7)
	local k = mk("Frame", { Size = UDim2.fromOffset(11, 11), BackgroundColor3 = C.txt, BorderSizePixel = 0, Parent = b })
	crn(k, 5)
	local on = default
	local function draw()
		b.BackgroundColor3 = on and C.on or C.off
		k.Position = UDim2.fromOffset(on and 15 or 2, 2)
	end
	local function set(v)
		on = v
		draw()
		task.spawn(cb, v)
	end
	b.MouseButton1Click:Connect(function() set(not on) end)
	draw()
	W.t[label] = { set = function(v) on = v; draw() end }
end
local function sld(p, label, mn, mx, dv, cb)
	local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.pane, BorderSizePixel = 0, Parent = p })
	crn(r, 5)
	mk("TextLabel", {
		Size = UDim2.new(1, -60, 0, 14), Position = UDim2.fromOffset(8, 2), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left, Text = label, Parent = r,
	})
	local out = mk("TextLabel", {
		Size = UDim2.fromOffset(44, 14), Position = UDim2.new(1, -52, 0, 2), BackgroundTransparency = 1,
		Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.acc,
		TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(dv), Parent = r,
	})
	local tr = mk("Frame", { Size = UDim2.new(1, -16, 0, 4), Position = UDim2.fromOffset(8, 24), BackgroundColor3 = C.off, BorderSizePixel = 0, Parent = r })
	crn(tr, 2)
	local fl = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.acc, BorderSizePixel = 0, Parent = tr })
	crn(fl, 2)
	local v, drag = dv, false
	local function draw()
		fl.Size = UDim2.fromScale(math.clamp((v - mn) / (mx - mn), 0, 1), 1)
		out.Text = tostring(v)
	end
	local function at(x)
		local f = math.clamp((x - tr.AbsolutePosition.X) / math.max(tr.AbsoluteSize.X, 1), 0, 1)
		local raw = mn + f * (mx - mn)
		v = (mx - mn) >= 20 and math.round(raw) or math.floor(raw * 100 + .5) / 100
		draw()
		cb(v)
	end
	tr.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			drag = true
			at(i.Position.X)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then at(i.Position.X) end
	end)
	UIS.InputEnded:Connect(function() drag = false end)
	draw()
	W.s[label] = { set = function(x) v = x; draw() end }
end
local function btn(p, label, cb, tone)
	local b = mk("TextButton", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = tone or C.pane, BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium, TextSize = 10, Text = label,
		TextColor3 = tone and C.bg or C.txt, Parent = p,
	})
	crn(b, 5)
	b.MouseButton1Click:Connect(function() task.spawn(cb) end)
	return b
end
local function mini(p, label, w, cb, tone)
	local b = mk("TextButton", {
		Size = UDim2.fromOffset(w or 40, 22), BackgroundColor3 = tone or C.off, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 9, Text = label,
		TextColor3 = tone and C.bg or C.txt, Parent = p,
	})
	crn(b, 4)
	b.MouseButton1Click:Connect(function() task.spawn(cb) end)
	return b
end
local function row(p)
	local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = p })
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, r)
	return r
end
local function inp(p, ph)
	local h = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = p })
	local b = mk("TextBox", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.pane, BorderSizePixel = 0,
		Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.txt,
		PlaceholderText = ph, Text = "", ClearTextOnFocus = false, Parent = h,
	})
	crn(b, 4)
	return b
end
print("[K] kit ok")

--==========================================================
-- helpers
--==========================================================
local function parts()
	local ch = PLR.Character
	return ch, ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end
local rawCast = workspace.Raycast
local mouse = try(function() return PLR:GetMouse() end)

local function applyMove()
	local _, _, hum = parts()
	if not hum then return end
	hum.WalkSpeed = math.max(1, S.bSpd + S.aSpd)
	hum.UseJumpPower = true
	hum.JumpPower = math.max(1, S.bJmp + S.aJmp)
end

--==========================================================
-- combat
--==========================================================
local A = { on = false, silent = false, wall = false, hb = false, auto = false,
	fov = 250, smooth = .3, max = 1500, skipTeam = true, check = true, target = nil, pos = nil }
local R = { on = false, rate = .06, acc = 0 }
local HK = { on = false, orig = nil }
local circle = nil

local function wallCast(self, org, dir, par)
	if not par then return rawCast(self, org, dir, par) end
	local o, d, n = org, dir, 0
	while n < 20 do
		n += 1
		local res = rawCast(self, o, d, par)
		if not res then return nil end
		local ins = res.Instance
		local hum = ins and (ins:FindFirstChildOfClass("Humanoid") or (ins.Parent and ins.Parent:FindFirstChildOfClass("Humanoid")))
		if hum then return res end
		local gone = (res.Position - o).Magnitude
		if gone >= d.Magnitude - .5 then return res end
		o = res.Position + d.Unit * .8
		d = d.Unit * math.max(d.Magnitude - gone - .8, .5)
	end
end

local function hookOn()
	if HK.on or not (EX.hook and EX.mt) then return end
	local ok, orig = pcall(EX.hook, game, "__index", function(self, key)
		if self == mouse and A.silent and A.pos then
			if key == "Hit" then return CFrame.new(A.pos) end
			if key == "Target" then return A.target and A.target.Character end
			if key == "UnitRay" then return Ray.new(CAM.CFrame.Position, (A.pos - CAM.CFrame.Position).Unit * 2000) end
		end
		if self == workspace and key == "Raycast" and A.wall then return wallCast end
		return orig(self, key)
	end)
	if ok then HK.on, HK.orig = true, orig end
end
local function hookOff()
	if HK.on and EX.hook then pcall(EX.hook, game, "__index", HK.orig) end
	HK.on = false
end

local function body(p)
	local ch = p.Character
	if not ch then return end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	return ch, ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
end

local function findTarget()
	local best, bs, bp
	local _, me = parts()
	local vp = CAM.ViewportSize
	local centre = Vector2.new(vp.X * .5, vp.Y * .5)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= PLR and not (A.skipTeam and PLR.Team and p.Team == PLR.Team) then
			local ch, head = body(p)
			if ch and head then
				local dist = me and (head.Position - me.Position).Magnitude or 0
				if dist <= A.max then
					local sp = CAM:WorldToViewportPoint(head.Position)
					if sp.Z > 0 then
						local sc = (Vector2.new(sp.X, sp.Y) - centre).Magnitude
						if sc <= A.fov and (not bs or sc < bs) then
							local see = true
							if A.check then
								local rp = RaycastParams.new()
								rp.FilterType = Enum.RaycastFilterType.Include
								rp.FilterDescendantsInstances = { ch }
								see = rawCast(workspace, CAM.CFrame.Position, head.Position - CAM.CFrame.Position, rp) ~= nil
							end
							if see then best, bs, bp = p, sc, head.Position end
						end
					end
				end
			end
		end
	end
	return best, bp
end

local function shoot()
	local ch = PLR.Character
	local tool = ch and ch:FindFirstChildOfClass("Tool")
	if tool then
		pcall(function() tool:Activate() end)
	elseif EX.click then
		pcall(EX.click)
	else
		pcall(function()
			VIM:SendMouseButtonEvent(0, 0, 0, true, game, 1)
			VIM:SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end)
	end
end

local function drawCircle()
	if not circle then return end
	circle.Visible = A.on
	if not A.on then return end
	local vp = CAM.ViewportSize
	circle.Position = Vector2.new(vp.X * .5, vp.Y * .5)
	circle.Radius = A.fov
	circle.Color = A.target and C.on or C.acc
end

local function tick(dt)
	if A.on then
		A.target, A.pos = findTarget()
		drawCircle()
		if A.target and A.pos and not A.silent then
			local goal = CFrame.lookAt(CAM.CFrame.Position, A.pos)
			CAM.CFrame = A.smooth <= 0 and goal or CAM.CFrame:Lerp(goal, math.clamp(1 - A.smooth, .05, 1))
		end
	end
	local autoFire = A.on and A.auto and A.target ~= nil
	if R.on or autoFire then
		R.acc += dt
		if R.acc >= R.rate then
			R.acc = 0
			shoot()
		end
	end
end

local function combatSync()
	if A.on or R.on then
		if not S.cn.tick then S.cn.tick = bind(RunService.RenderStepped, tick) end
	elseif S.cn.tick then
		S.cn.tick:Disconnect()
		S.cn.tick = nil
		A.target, A.pos = nil, nil
		drawCircle()
	end
	if A.on or A.wall then hookOn() else hookOff() end
end

local function dropHb(p)
	if HB[p] then pcall(function() HB[p]:Destroy() end) end
	HB[p] = nil
end
local function makeHb(p)
	if HB[p] or p == PLR then return end
	local ch = p.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local h = mk("Part", {
		Name = "K_HB", Size = Vector3.new(9, 9, 9), Transparency = .75, Color = C.acc,
		CanCollide = false, CanQuery = true, CanTouch = true, Massless = true,
		CastShadow = false, Parent = hrp,
	})
	mk("WeldConstraint", { Part0 = hrp, Part1 = h, Parent = h })
	HB[p] = h
end
function F.hitbox(on)
	A.hb = on
	for _, p in ipairs(Players:GetPlayers()) do
		if on then makeHb(p) else dropHb(p) end
	end
	if on and not S.cn.hb then
		local acc = 0
		S.cn.hb = bind(RunService.Heartbeat, function(dt)
			acc += dt
			if acc < 1 then return end
			acc = 0
			for _, p in ipairs(Players:GetPlayers()) do makeHb(p) end
		end)
	elseif not on and S.cn.hb then
		S.cn.hb:Disconnect()
		S.cn.hb = nil
	end
	note("hitbox " .. (on and "on" or "off"))
end

--==========================================================
-- visual / movement
--==========================================================
function F.esp(on)
	S.esp = on
	local function add(p)
		if p == PLR or ESP[p] then return end
		local ch = p.Character
		if not (ch and ch:FindFirstChild("Head")) then return end
		local set = {}
		set.h = mk("Highlight", {
			Name = "K_ESP", Adornee = ch, FillColor = C.acc, FillTransparency = .75,
			OutlineColor = Color3.new(1, 1, 1), DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = ch,
		})
		set.g = mk("BillboardGui", {
			Name = "K_TAG", Adornee = ch.Head, Size = UDim2.fromOffset(180, 24),
			StudsOffset = Vector3.new(0, 2.2, 0), AlwaysOnTop = true, Parent = ch.Head,
		})
		set.t = mk("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = .3, Text = p.Name, Parent = set.g,
		})
		ESP[p] = set
	end
	local function rem(p)
		if not ESP[p] then return end
		for _, o in pairs(ESP[p]) do pcall(function() o:Destroy() end) end
		ESP[p] = nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if on then add(p) else rem(p) end
	end
	if on and not S.cn.esp then
		local acc = 0
		S.cn.esp = bind(RunService.Heartbeat, function(dt)
			acc += dt
			if acc < 1 then return end
			acc = 0
			local _, me = parts()
			for p, set in pairs(ESP) do
				local ch = p.Character
				local head = ch and ch:FindFirstChild("Head")
				if head and me then set.t.Text = ("%s [%dm]"):format(p.Name, (head.Position - me.Position).Magnitude) end
			end
		end)
	elseif not on and S.cn.esp then
		S.cn.esp:Disconnect()
		S.cn.esp = nil
	end
end

function F.fb(on)
	S.fb = on
	if on then
		S.light = {
			Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd,
		}
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.Ambient = Color3.new(1, 1, 1)
		Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		Lighting.FogEnd = 1e5
	elseif S.light then
		for k, v in pairs(S.light) do Lighting[k] = v end
		S.light = nil
	end
end

function F.noclip(on)
	S.noclip = on
	if S.cn.nc then S.cn.nc:Disconnect() end
	if on then
		S.cn.nc = bind(RunService.Stepped, function()
			local ch = PLR.Character
			if not ch then return end
			for _, p in ipairs(ch:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end)
	end
end

function F.fly(on)
	S.fly = on
	local _, hrp = parts()
	if on then
		if not hrp then S.fly = false return note("no character") end
		S.flyParts = {
			mk("BodyVelocity", { MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = hrp }),
			mk("BodyGyro", { MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2000, D = 60, Parent = hrp }),
		}
		S.cn.fly = bind(RunService.RenderStepped, function()
			local _, root = parts()
			if not root or not S.flyParts[1].Parent then return end
			local cf = CAM.CFrame
			local m = Vector3.zero
			if UIS:IsKeyDown(Enum.KeyCode.W) then m += cf.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.S) then m -= cf.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.D) then m += cf.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.A) then m -= cf.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.Space) then m += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then m -= Vector3.yAxis end
			S.flyParts[1].Velocity = m.Magnitude > 0 and m.Unit * ((S.bSpd + S.aSpd) * 3) or Vector3.zero
			S.flyParts[2].CFrame = cf
		end)
	else
		if S.cn.fly then S.cn.fly:Disconnect() end
		if S.flyParts then
			for _, o in ipairs(S.flyParts) do pcall(function() o:Destroy() end) end
			S.flyParts = nil
		end
	end
end

function F.ij(on)
	S.ij = on
	if S.cn.ij then S.cn.ij:Disconnect() end
	if on then
		S.cn.ij = bind(UIS.JumpRequest, function()
			local _, _, hum = parts()
			if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
		end)
	end
end

function F.av(on)
	S.av = on
	if S.cn.av then S.cn.av:Disconnect() S.cn.av = nil end
	if on then
		S.cn.av = bind(RunService.Heartbeat, function()
			local ch, root = parts()
			if not ch or not root then return end
			if root.Position.Y > S.voidY + 15 then
				S.safe = root.CFrame
			elseif root.Position.Y < S.voidY and S.safe then
				pcall(function() ch:PivotTo(S.safe) end)
			end
		end)
	end
end

function F.spd(v)
	S.aSpd = v
	if W.s["+ WalkSpeed"] then W.s["+ WalkSpeed"].set(v) end
	applyMove()
end
function F.jmp(v)
	S.aJmp = v
	if W.s["+ JumpPower"] then W.s["+ JumpPower"].set(v) end
	applyMove()
end

function F.tp(cf)
	local ch = parts()
	if not ch or not cf then return end
	pcall(function() ch:PivotTo(cf + Vector3.new(0, 3, 0)) end)
end
function F.tpMouse()
	local loc = UIS:GetMouseLocation()
	local ray = CAM:ViewportPointToRay(loc.X, loc.Y)
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { PLR.Character }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 5000, rp)
	F.tp(CFrame.new(res and res.Position or (ray.Origin + ray.Direction * 200)))
end
function F.tpPlayer(n)
	local p = Players:FindFirstChild(n)
	local ch = p and p.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then F.tp(hrp.CFrame) end
end

local function saveWps()
	if not IO.ok then return end
	local o = {}
	for n, cf in pairs(S.wps) do o[n] = { cf:GetComponents() } end
	pcall(IO.w, IO.dir .. "/wps.json", HS:JSONEncode(o))
end
function F.loadWps()
	if not IO.ok or not IO.e(IO.dir .. "/wps.json") then return end
	local ok, d = pcall(IO.r, IO.dir .. "/wps.json")
	if not ok or not d then return end
	local ok2, t = pcall(function() return HS:JSONDecode(d) end)
	if not ok2 then return end
	for n, c in pairs(t) do
		local ok3, cf = pcall(CFrame.new, table.unpack(c))
		if ok3 then S.wps[n] = cf end
	end
end
function F.saveWp(n)
	local _, hrp = parts()
	if not hrp or n == "" then return note("invalid waypoint") end
	S.wps[n] = hrp.CFrame
	saveWps()
	note("saved " .. n)
end

--==========================================================
-- flood
--==========================================================
local FL = { run = false, busy = false, made = 0, fires = 0, live = 0, list = {}, sel = nil,
	variant = "cframe", pre = {}, budget = 5000, rate = 400, local = false, anchor = true, cn = nil, tgt = "" }
local oldSpam = workspace:FindFirstChild("KayserSpam")
if oldSpam then oldSpam:Destroy() end
local spam = mk("Folder", { Name = "KayserSpam", Parent = workspace })

local function ours(i)
	local p = i
	while p and p ~= workspace do
		if p == spam or p == PLR.Character then return true end
		p = p.Parent
	end
	return false
end

local KW = { "part", "build", "place", "spawn", "create", "add", "draw", "block", "brick",
	"make", "item", "object", "cube", "prop", "model", "plot", "emit", "mesh" }
local function score(n0)
	local n = n0:lower()
	local s = 0
	for _, k in ipairs(KW) do if n:find(k, 1, true) then s += 10 end end
	if n:find("effect", 1, true) or n:find("vfx", 1, true) then s += 4 end
	return s
end
local function scan()
	local o = {}
	for _, root in ipairs({ game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst") }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				o[#o + 1] = { obj = d, sc = score(d.Name) }
			end
		end
	end
	table.sort(o, function(a, b) return a.sc > b.sc end)
	return o
end
local function at(name)
	local p = name ~= "" and Players:FindFirstChild(name) or nil
	local ch = p and p.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then return hrp.CFrame end
	local _, me = parts()
	return me and me.CFrame or CFrame.new()
end
local function jit(b, sp)
	return b * CFrame.new((math.random() - .5) * sp, (math.random() - .5) * sp, (math.random() - .5) * sp)
		* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
end
local function payload(cf)
	local v = FL.variant
	if v == "cframe" then return cf end
	if v == "pos" then return cf.Position end
	if v == "table_cf" then return { cframe = cf, CFrame = cf } end
	if v == "cf_size" then return cf, Vector3.new(2, 2, 2) end
	if v == "name_cf" then return "Part", cf end
	if v == "double" then return cf, cf end
	return { name = "Part", cframe = cf, size = Vector3.new(2, 2, 2), Color = Color3.new(1, 0, 0) }
end
local function fire(c, cf)
	local o = c.obj
	local args = {}
	for i = 1, #FL.pre do args[#args + 1] = FL.pre[i] end
	local a1, a2 = payload(cf)
	args[#args + 1] = a1
	if a2 ~= nil then args[#args + 1] = a2 end
	if o:IsA("RemoteEvent") then
		pcall(o.FireServer, o, table.unpack(args))
	else
		if FL.live > 30 then return end
		FL.live += 1
		task.spawn(function()
			pcall(o.InvokeServer, o, table.unpack(args))
			FL.live -= 1
		end)
	end
	FL.fires += 1
end
function FL.stop()
	if not FL.run then return end
	FL.run = false
	if FL.cn then FL.cn:Disconnect() FL.cn = nil end
	note(("stop | %d fires | %d parts"):format(FL.fires, FL.made), 4)
end
function FL.probe(c)
	for _, sh in ipairs({ "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }) do
		FL.variant = sh
		local hits = 0
		local con = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and not ours(d) then hits += 1 end
		end)
		fire(c, at(FL.tgt))
		task.wait(.3)
		con:Disconnect()
		if hits > 0 then return sh, hits end
	end
	return nil, 0
end
function FL.start(name)
	if FL.run then return note("already running") end
	if not FL.sel and not FL.local then return note("no remote selected") end
	FL.made, FL.fires = 0, 0
	FL.run = true
	local base = at(name)
	local cap = FL.budget
	FL.cn = workspace.DescendantAdded:Connect(function(d)
		if not d:IsA("BasePart") or ours(d) then return end
		FL.made += 1
		if FL.made >= cap then FL.stop() end
	end)
	task.spawn(function()
		while FL.run do
			if FL.local then
				for _ = 1, FL.rate do
					if not FL.run then break end
					mk("Part", {
						Name = "KPart", Anchored = FL.anchor, CanCollide = not FL.anchor,
						CanQuery = false, CanTouch = false, Size = Vector3.new(2, 2, 2),
						Color = Color3.fromHSV(math.random(), .8, 1), CFrame = jit(base, 12), Parent = spam,
					})
					FL.made += 1
					if FL.made >= cap then FL.stop() break end
				end
			else
				for _ = 1, FL.rate do
					if not FL.run then break end
					fire(FL.sel, jit(base, 8))
				end
			end
			task.wait(1)
		end
	end)
	note(("flood %s @ %d/s"):format(name ~= "" and name or "server", FL.rate), 4)
end
print("[K] engine ok")

--==========================================================
-- pages
--==========================================================
local pc = tab("c", "Combat")
local pv = tab("v", "Visual")
local pm = tab("m", "Move")
local pt = tab("t", "TP")
local pf = tab("f", "Flood")
local px = tab("x", "Config")
local ps = tab("s", "Session")
pick("c")
print("[K] tabs ok")

local c1 = card(pc)
hdr(c1, "aim")
tog(c1, "Aimbot (camera)", false, function(v) A.on = v; combatSync() end)
tog(c1, "Silent aim", false, function(v) A.silent = v; combatSync() end)
tog(c1, "Wallbang", false, function(v) A.wall = v; combatSync() end)
tog(c1, "Auto fire", false, function(v) A.auto = v; combatSync() end)
tog(c1, "Skip teammates", true, function(v) A.skipTeam = v end)
tog(c1, "Wall check", true, function(v) A.check = v end)
sld(c1, "FOV radius", 40, 800, 250, function(v) A.fov = v end)
sld(c1, "Smoothness", 0, 1, .3, function(v) A.smooth = v end)
sld(c1, "Max distance", 100, 5000, 1500, function(v) A.max = v end)

local c2 = card(pc)
hdr(c2, "fire")
tog(c2, "Rapid fire", false, function(v) R.on = v; combatSync() end)
sld(c2, "Interval", .01, .5, .06, function(v) R.rate = v end)
tog(c2, "Hitbox expander", false, F.hitbox)
local c3 = card(pc, 32)
hdr(c3, "target")
local tgtLbl = lbl(c3, "none", 12)

local c4 = card(pv)
hdr(c4, "world")
tog(c4, "Player ESP", false, F.esp)
tog(c4, "Fullbright", false, F.fb)
sld(c4, "Camera FOV", 70, 140, 70, function(v) CAM.FieldOfView = v end)
tog(c4, "Unlock FPS", false, function(v) if EX.fps then pcall(EX.fps, v and 240 or 60) end end)

local c5 = card(pm)
hdr(c5, "speed (adds to base)")
sld(c5, "+ WalkSpeed", -16, 500, 0, F.spd)
local r5 = row(c5)
mini(r5, "-10", 42, function() F.spd(math.max(-16, S.aSpd - 10)) end)
mini(r5, "+10", 42, function() F.spd(S.aSpd + 10) end)
mini(r5, "+50", 42, function() F.spd(S.aSpd + 50) end)
mini(r5, "reset", 46, function() F.spd(0) end, C.warn)
hdr(c5, "jump (adds to base)")
sld(c5, "+ JumpPower", -50, 500, 0, F.jmp)
local r6 = row(c5)
mini(r6, "-10", 42, function() F.jmp(math.max(-50, S.aJmp - 10)) end)
mini(r6, "+10", 42, function() F.jmp(S.aJmp + 10) end)
mini(r6, "+50", 42, function() F.jmp(S.aJmp + 50) end)
mini(r6, "reset", 46, function() F.jmp(0) end, C.warn)

local c7 = card(pm)
hdr(c7, "traversal")
tog(c7, "Noclip", false, F.noclip)
tog(c7, "Infinite jump", false, F.ij)
tog(c7, "Fly (WASD / Space / LCTRL)", false, F.fly)
tog(c7, "Anti-void", false, F.av)
sld(c7, "Void Y", -500, 100, -60, function(v) S.voidY = v end)

local c8 = card(pt)
hdr(c8, "position")
btn(c8, "Teleport to cursor", F.tpMouse)
local r8 = row(c8)
local wHost = mk("Frame", { Size = UDim2.new(1, -62, 1, 0), BackgroundTransparency = 1, Parent = r8 })
local wBox = mk("TextBox", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.pane, BorderSizePixel = 0,
	Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.txt,
	PlaceholderText = "waypoint name", Text = "", ClearTextOnFocus = false, Parent = wHost,
})
crn(wBox, 4)
mini(r8, "save", 56, function() F.saveWp(wBox.Text); F.renderWps() end, C.acc)
local wLst = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = c8 })
mk("UIListLayout", { Padding = UDim.new(0, 3) }, wLst)
function F.renderWps()
	for _, c in ipairs(wLst:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for n, cf in pairs(S.wps) do
		local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = wLst })
		local g = mk("TextButton", {
			Size = UDim2.new(1, -44, 1, 0), BackgroundColor3 = C.pane, BorderSizePixel = 0,
			Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = C.txt,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "  " .. n, Parent = r,
		})
		crn(g, 4)
		g.MouseButton1Click:Connect(function() F.tp(cf) end)
		local d = mk("TextButton", {
			Size = UDim2.fromOffset(40, 20), Position = UDim2.new(1, -40, 0, 0), BackgroundColor3 = C.off,
			BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 8, TextColor3 = C.txt, Text = "del", Parent = r,
		})
		crn(d, 4)
		d.MouseButton1Click:Connect(function()
			S.wps[n] = nil
			saveWps()
			F.renderWps()
		end)
	end
end

local c9 = card(pt)
hdr(c9, "players")
local pLst = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = c9 })
mk("UIListLayout", { Padding = UDim.new(0, 3) }, pLst)
local function fillPlayers()
	for _, c in ipairs(pLst:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= PLR then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local r = mk("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = pLst })
			local g = mk("TextButton", {
				Size = UDim2.new(1, -44, 1, 0), BackgroundColor3 = C.pane, BorderSizePixel = 0,
				Font = Enum.Font.Gotham, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = C.txt, Text = "  " .. p.Name, Parent = r,
			})
			crn(g, 4)
			g.MouseButton1Click:Connect(function() F.tpPlayer(p.Name) end)
			mk("TextLabel", {
				Size = UDim2.fromOffset(40, 20), Position = UDim2.new(1, -40, 0, 0), BackgroundColor3 = C.card,
				BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 8, TextColor3 = C.on,
				Text = hum and tostring(math.floor(hum.Health)) or "-", Parent = r,
			})
		end
	end
end

local c10 = card(pf)
hdr(c10, "target")
local tgBox = inp(c10, "player name (blank = server centre)")
lbl(c10, "auto scores build-named remotes, probes them in order, floods the first that works.", 26)

local c11 = card(pf)
hdr(c11, "auto")
btn(c11, "Find > probe > flood", function()
	if FL.busy or FL.run then return note("busy") end
	FL.busy = true
	FL.tgt = tgBox.Text
	FL.list = scan()
	F.renderRemotes()
	local got, sh
	for i = 1, math.min(#FL.list, 6) do
		FL.sel = FL.list[i]
		F.renderRemotes()
		local a, b = FL.probe(FL.list[i])
		if a then got, sh = FL.list[i], a break end
	end
	FL.busy = false
	if got then
		FL.variant = sh
		FL.start(FL.tgt)
	else
		note("no remote worked - pick manually", 5)
	end
end, C.acc)
tog(c11, "Local mode (no remote)", false, function(v) FL.local = v end)

local c12 = card(pf)
hdr(c12, "remotes")
local fltBox = inp(c12, "filter...")
local rl = mk("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = C.bg, BorderSizePixel = 0,
	ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = c12,
})
crn(rl, 4)
mk("UIListLayout", { Padding = UDim.new(0, 2) }, rl)
function F.renderRemotes()
	for _, c in ipairs(rl:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
	end
	local f = fltBox.Text:lower()
	local shown = 0
	for _, e in ipairs(FL.list) do
		local n = e.obj:GetFullName()
		if f == "" or n:lower():find(f, 1, true) then
			shown += 1
			if shown > 50 then break end
			local sel = FL.sel == e
			local b = mk("TextButton", {
				Size = UDim2.new(1, -6, 0, 19), BackgroundColor3 = sel and C.acc or C.pane,
				BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 8,
				TextColor3 = sel and C.bg or C.dim, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = ("%s%s [%d]"):format(e.obj:IsA("RemoteFunction") and "RF " or "RE ", n, e.sc), Parent = rl,
			})
			crn(b, 3)
			b.MouseButton1Click:Connect(function() FL.sel = e; F.renderRemotes() end)
		end
	end
	if #FL.list == 0 then lbl(rl, "  press search") end
end
fltBox:GetPropertyChangedSignal("Text"):Connect(function() F.renderRemotes() end)

local c13 = card(pf)
hdr(c13, "manual")
local r13 = row(c13)
mini(r13, "search", 58, function()
	FL.list = scan()
	FL.sel = nil
	F.renderRemotes()
	note(("%d remotes"):format(#FL.list))
end)
local shBtn = mini(r13, "cframe", 70, function()
	local cyc = { "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }
	for i, s in ipairs(cyc) do
		if s == FL.variant then FL.variant = cyc[(i % #cyc) + 1] break end
	end
	shBtn.Text = FL.variant
end)
mini(r13, "probe", 50, function()
	if FL.busy or not FL.sel then return note("select a remote") end
	FL.busy = true
	local a, b = FL.probe(FL.sel)
	FL.busy = false
	note(a and ("hit %s +%d"):format(a, b) or "no shape worked", 4)
end)
local preBox = inp(c13, "prefix args (5,wood)")
preBox.FocusLost:Connect(function()
	FL.pre = {}
	for piece in preBox.Text:gmatch("[^,]+") do
		piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
		FL.pre[#FL.pre + 1] = tonumber(piece) or piece
	end
end)
sld(c13, "Rate per second", 50, 2000, 400, function(v) FL.rate = v end)
sld(c13, "Part budget", 200, 40000, 5000, function(v) FL.budget = math.floor(v) end)
tog(c13, "Unanchored", false, function(v) FL.anchor = not v end)
btn(c13, "Flood target", function()
	FL.tgt = tgBox.Text
	FL.start(FL.tgt)
end)
local r13b = row(c13)
mini(r13b, "stop", 50, FL.stop, C.warn)
mini(r13b, "wipe local", 76, function()
	local n = #spam:GetChildren()
	spam:ClearAllChildren()
	note(("wiped %d"):format(n))
end)
local flLbl = lbl(c13, "idle", 12)

local c14 = card(px)
hdr(c14, "store")
btn(c14, "Save settings", function()
	if not IO.ok then return note("no filesystem") end
	local o = { esp = S.esp, fb = S.fb, noclip = S.noclip, fly = S.fly, ij = S.ij, av = S.av,
		silent = A.silent, wall = A.wall, auto = A.auto, hb = A.hb,
		spd = S.aSpd, jmp = S.aJmp, fov = A.fov, smooth = A.smooth }
	pcall(IO.w, IO.dir .. "/cfg.json", HS:JSONEncode(o))
	note("saved")
end)
btn(c14, "Load settings", function()
	if not IO.ok then return note("no filesystem") end
	local ok, raw = pcall(IO.r, IO.dir .. "/cfg.json")
	if not ok then return note("no config") end
	local ok2, d = pcall(function() return HS:JSONDecode(raw) end)
	if not ok2 then return end
	local m = { ["Player ESP"] = "esp", Fullbright = "fb", Noclip = "noclip", Fly = "fly",
		["Infinite jump"] = "ij", ["Anti-void"] = "av", ["Silent aim"] = "silent",
		Wallbang = "wall", ["Auto fire"] = "auto", ["Hitbox expander"] = "hb" }
	for k, w in pairs(W.t) do
		local f = m[k]
		if f and d[f] ~= nil and w.set then w.set(d[f]) end
	end
	if d.spd then F.spd(d.spd) end
	if d.jmp then F.jmp(d.jmp) end
	if d.fov and W.s["FOV radius"] then A.fov = d.fov W.s["FOV radius"].set(d.fov) end
	note("loaded")
end)
local c15 = card(px)
hdr(c15, "runtime")
local dbg = lbl(c15, "ready", 34)

local c16 = card(ps)
hdr(c16, "session")
btn(c16, "Rejoin", function() TS:Teleport(game.PlaceId, PLR) end)
btn(c16, "Copy JobId", function()
	if EX.clip then pcall(EX.clip, game.JobId) note("copied") else note("no clipboard") end
end)
btn(c16, "Unload", function() pcall(ENV.__K_UNLOAD) end, C.warn)
local c17 = card(ps)
hdr(c17, "info")
lbl(c17, ("executor %s | hook %s | draw %s | io %s"):format(
	tostring(EX.who or "?"), EX.hook and "y" or "n", EX.draw and "y" or "n", IO.ok and "y" or "n"), 24)
lbl(c17, "silent aim and wallbang only matter in client-authoritative games", 24)
print("[K] ui built")

--==========================================================
-- loops
--==========================================================
S.cn.key = bind(UIS.InputBegan, function(i, gp)
	if gp or not gui.Parent then return end
	if i.KeyCode == Enum.KeyCode.RightShift then
		gui.Enabled = not gui.Enabled
	elseif i.KeyCode == Enum.KeyCode.End then
		pcall(ENV.__K_UNLOAD)
	elseif i.KeyCode == Enum.KeyCode.Home then
		gui.Enabled = true
		pick("c")
	end
end)
S.cn.char = bind(PLR.CharacterAdded, function()
	task.wait(.6)
	if S.dead then return end
	if S.fly then F.fly(false) F.fly(true) end
	applyMove()
end)

do
	local _, _, hum = parts()
	if hum then
		S.bSpd = hum.WalkSpeed
		S.bJmp = hum.JumpPower > 0 and hum.JumpPower or 50
	end
	S.bFov = CAM.FieldOfView
end

task.spawn(function()
	local fps, acc, fr = 0, 0, 0
	local roster = ""
	while not S.dead and gui.Parent do
		local dt = RunService.RenderStepped:Wait()
		fr += 1
		acc += dt
		if acc >= .5 then
			fps = math.floor(fr / acc)
			acc, fr = 0, 0
		end
		local ping = try(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
		foot.Text = ("%d fps | %s ms | aim %s | flood %s"):format(
			fps, ping and tostring(ping) or "-",
			A.on and (A.silent and "silent" or "camera") or "off", FL.run and "run" or "idle")
		tgtLbl.Text = A.target and (A.target.Name .. " | " .. math.floor(A.fov) .. "px") or "none"
		flLbl.TextColor3 = FL.run and C.on or C.dim
		flLbl.Text = FL.run and ("RUN %d fires | %d/%d parts"):format(FL.fires, FL.made, FL.budget)
			or ("idle | %s | %s"):format(FL.sel and FL.sel.obj.Name or "no remote", FL.variant)
		local sig = ""
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= PLR then
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				sig ..= p.Name .. (hum and math.floor(hum.Health) or "-") .. "|"
			end
		end
		if sig ~= roster then
			roster = sig
			fillPlayers()
		end
	end
end)

ENV.__K_UNLOAD = function()
	if S.dead then return end
	S.dead = true
	for _, c in pairs(S.cn) do pcall(function() c:Disconnect() end) end
	S.cn = {}
	hookOff()
	if circle then pcall(function() circle:Remove() end) circle = nil end
	for p, set in pairs(ESP) do
		for _, o in pairs(set) do pcall(function() o:Destroy() end) end
		ESP[p] = nil
	end
	for p, h in pairs(HB) do
		pcall(function() h:Destroy() end)
		HB[p] = nil
	end
	if S.flyParts then for _, o in ipairs(S.flyParts) do pcall(function() o:Destroy() end) end end
	if S.light then for k, v in pairs(S.light) do Lighting[k] = v end end
	FL.run = false
	if FL.cn then FL.cn:Disconnect() end
	if spam then spam:Destroy() end
	if EX.fps then pcall(EX.fps, 60) end
	CAM.FieldOfView = S.bFov
	local _, _, hum = parts()
	if hum then
		hum.WalkSpeed = S.bSpd
		if S.bJmp > 0 then
			hum.UseJumpPower = true
			hum.JumpPower = S.bJmp
		end
	end
	gui:Destroy()
	ENV.__K_LOADED = nil
	ENV.__K_UNLOAD = nil
	note("unloaded", 2)
end
ENV.__K_LOADED = true

if EX.draw then
	circle = try(function() return Drawing.new("Circle") end)
	if circle then
		circle.Thickness = 1.5
		circle.NumSides = 64
		circle.Filled = false
		circle.Transparency = .8
		circle.Visible = false
	end
end

F.loadWps()
F.renderWps()
F.renderRemotes()
applyMove()
dbg.Text = ("hook %s | draw %s | io %s | exec %s"):format(
	EX.hook and "y" or "n", EX.draw and "y" or "n", IO.ok and "y" or "n", tostring(EX.who or "?"))
note("KAYSER ready | RSHIFT ui | END unload", 4)
print("[K] READY size", win.AbsoluteSize, "parent", gui.Parent and gui.Parent:GetFullName() or "NIL")

end, function(e)
	return tostring(e) .. "\n" .. debug.traceback()
end)

if not ok0 then warn("[K] FATAL: " .. tostring(err0)) end
print("[K] end")
