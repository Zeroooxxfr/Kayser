-- !nolint
--[[ =============================================================
  KAYSER 2.2  |  full-stack executor suite (single file, Luau)
  RIGHT SHIFT = toggle UI     END = unload + restore world
============================================================= ]]

local function main()
	if not game:IsLoaded() then game.Loaded:Wait() end

	local Players             = game:GetService("Players")
	local RunService          = game:GetService("RunService")
	local UserInputService    = game:GetService("UserInputService")
	local Lighting            = game:GetService("Lighting")
	local TweenService        = game:GetService("TweenService")
	local StarterGui          = game:GetService("StarterGui")
	local HttpService         = game:GetService("HttpService")
	local VirtualInputManager = game:GetService("VirtualInputManager")

	local PLR = Players.LocalPlayer
	local CAM = workspace.CurrentCamera

	local function try(fn, ...)
		local ok, a, b, c = pcall(fn, ...)
		if ok then return a, b, c end
	end

	local ENV = try(getgenv) or _G
	if ENV.__KAYSER_LOADED then try(ENV.__KAYSER_UNLOAD) end

	--==========================================================
	-- 1. executor abstraction
	--==========================================================
	local EX = {
		hook  = (function() local ok, v = pcall(function() return hookmetamethod end) return ok and type(v) == "function" and v or nil end)(),
		rawmt = try(getrawmetatable),
		input = try(mouse1click),
		clip  = try(setclipboard),
		fps   = try(setfpscap),
		draw  = try(function() return typeof(Drawing) == "table" and Drawing or nil end),
		hint  = try(identifyexecutor),
	}

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

	--==========================================================
	-- 2. state
	--==========================================================
	local State = {
		esp = false, fullbright = false, noclip = false, fly = false,
		infJump = false, antiVoid = false, voidY = -60, safeCF = nil,
		baseSpeed = 16, baseJump = 50, baseFov = 70, addSpeed = 0, addJump = 0,
		waypoints = {}, conns = {}, flyParts = nil, light = nil, killed = false,
		spectating = nil,
	}
	local Widgets = { toggles = {}, sliders = {} }
	local ESP, Hitboxes = {}, {}
	local Features = {}

	--==========================================================
	-- 3. widget kit
	--==========================================================
	local C = {
		bg = Color3.fromRGB(13, 14, 19), side = Color3.fromRGB(18, 20, 26),
		panel = Color3.fromRGB(26, 29, 37), card = Color3.fromRGB(22, 24, 31),
		stroke = Color3.fromRGB(44, 48, 60), text = Color3.fromRGB(236, 238, 244),
		dim = Color3.fromRGB(138, 145, 160), accent = Color3.fromRGB(124, 152, 255),
		on = Color3.fromRGB(74, 222, 158), off = Color3.fromRGB(58, 63, 76),
		warn = Color3.fromRGB(251, 176, 74),
	}

	local function new(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end
	local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end
	local function stroke(o, col, w) return new("UIStroke", { Color = col or C.stroke, Thickness = w or 1 }, o) end

	local Gui = new("ScreenGui", {
		Name = "Kayser", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 1e6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local function attach(o)
		local hosts = {}
		local pg = PLR:FindFirstChildOfClass("PlayerGui") or PLR:WaitForChild("PlayerGui", 10)
		if pg then table.insert(hosts, pg) end
		table.insert(hosts, function() return try(gethui) end)
		table.insert(hosts, function() return game:GetService("CoreGui") end)
		for _, h in ipairs(hosts) do
			local host = type(h) == "function" and try(h) or h
			if host then
				local ok = pcall(function() o.Parent = host end)
				if ok then
					task.wait(.1)
					if o.Parent then
						print("[K] attached to " .. o.Parent:GetFullName())
						return true
					end
				end
			end
		end
		return false
	end
	if not attach(Gui) then warn("[K] attach failed — no renderable host") end

	local win = new("Frame", {
		Size = UDim2.fromOffset(660, 430), Position = UDim2.fromScale(.5, .5),
		AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = C.bg,
		BorderSizePixel = 0, Parent = Gui,
	})
	corner(win, 12)
	stroke(win)

	local titlebar = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.side, BorderSizePixel = 0, Parent = win })
	corner(titlebar, 12)

	new("TextLabel", {
		Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(16, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "KAYSER", Parent = titlebar,
	})
	new("TextLabel", {
		Size = UDim2.fromOffset(120, 12), Position = UDim2.new(1, -132, .5, 0), AnchorPoint = Vector2.new(0, .5),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 10,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right,
		Text = "RIGHT SHIFT · END", Parent = titlebar,
	})

	local toastLbl = new("TextLabel", {
		Size = UDim2.new(1, -32, 0, 22), Position = UDim2.new(0, 16, 1, -30), BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, Parent = win,
	})
	function Toast(text)
		toastLbl.Text = text
		TweenService:Create(toastLbl, TweenInfo.new(.12), { TextTransparency = 0 }):Play()
		task.delay(2.4, function()
			TweenService:Create(toastLbl, TweenInfo.new(.4), { TextTransparency = 1 }):Play()
		end)
	end

	do
		local dragging, pos0, frame0
		titlebar.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				win.Position = UDim2.fromOffset(win.AbsolutePosition.X, win.AbsolutePosition.Y)
				pos0, frame0 = i.Position, win.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(i)
			if not dragging then return end
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
				local d = i.Position - pos0
				win.Position = UDim2.fromOffset(frame0.X.Offset + d.X, frame0.Y.Offset + d.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	local nav = new("Frame", { Position = UDim2.fromOffset(8, 46), Size = UDim2.new(0, 112, 1, -112), BackgroundTransparency = 1, Parent = win })
	new("UIListLayout", { Padding = UDim.new(0, 3) }, nav)
	local contentHost = new("Frame", { Position = UDim2.fromOffset(126, 46), Size = UDim2.new(1, -136, 1, -80), BackgroundTransparency = 1, Parent = win })

	local footer = new("Frame", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 1, -26), BackgroundTransparency = 1, Parent = win })
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 10,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "booting", Name = "status", Parent = footer,
	})

	local navButtons, pages = {}, {}
	local selectPage

	local function page(name, label)
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.panel, BackgroundTransparency = .45,
			BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "   " .. label, Parent = nav,
		})
		corner(b, 7)
		local stripe = new("Frame", {
			Size = UDim2.new(0, 3, .55, 0), Position = UDim2.new(0, 0, .5, 0), AnchorPoint = Vector2.new(0, .5),
			BackgroundColor3 = C.accent, BorderSizePixel = 0, Visible = false, Parent = b,
		})
		corner(stripe, 2)

		local f = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = C.stroke,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = contentHost,
		})
		new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		new("UIPadding", { PaddingBottom = UDim.new(0, 24) }, f)

		pages[name], navButtons[name] = f, { btn = b, stripe = stripe }
		b.MouseButton1Click:Connect(function() selectPage(name) end)
		return f
	end

	selectPage = function(name)
		for n, f in pairs(pages) do f.Visible = (n == name) end
		for n, v in pairs(navButtons) do
			local active = (n == name)
			v.btn.TextColor3 = active and C.text or C.dim
			v.btn.BackgroundTransparency = active and 0 or .45
			v.stripe.Visible = active
		end
	end

	local function card(p, height)
		local c = new("Frame", {
			Size = UDim2.new(1, 0, 0, height or 0),
			AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
			BackgroundColor3 = C.card, BorderSizePixel = 0, Parent = p,
		})
		corner(c, 8)
		stroke(c, C.stroke)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		}, c)
		new("UIListLayout", { Padding = UDim.new(0, 6) }, c)
		return c
	end

	local function header(p, text)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextSize = 11, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left,
			Text = text:upper(), Parent = p,
		})
	end

	local function toggle(p, label, default, cb, hint)
		local c = new("Frame", { Size = UDim2.new(1, 0, 0, hint and 40 or 30), BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = p })
		corner(c, 6)
		if hint then
			new("TextLabel", {
				Size = UDim2.new(1, -56, 0, 12), Position = UDim2.fromOffset(9, 17), BackgroundTransparency = 1,
				Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = C.dim,
				TextXAlignment = Enum.TextXAlignment.Left, Text = hint, Parent = c,
			})
		end
		new("TextLabel", {
			Size = UDim2.new(1, -56, 0, 18), Position = UDim2.fromOffset(9, hint and 3 or 6), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
			TextXAlignment = Enum.TextXAlignment.Left, Text = label, Parent = c,
		})
		local pill = new("TextButton", {
			Size = UDim2.fromOffset(34, 18), Position = UDim2.new(1, -43, .5, 0), AnchorPoint = Vector2.new(0, .5),
			BackgroundColor3 = C.off, BorderSizePixel = 0, Text = "", Parent = c,
		})
		corner(pill, 9)
		local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.text, BorderSizePixel = 0, Parent = pill })
		corner(knob, 7)
		local on = default
		local function render()
			pill.BackgroundColor3 = on and C.on or C.off
			knob.Position = UDim2.fromOffset(on and 18 or 2, 2)
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
		local c = new("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = p })
		corner(c, 6)
		new("TextLabel", {
			Size = UDim2.new(1, -70, 0, 16), Position = UDim2.fromOffset(9, 4), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Left, Text = label, Parent = c,
		})
		local out = new("TextLabel", {
			Size = UDim2.fromOffset(50, 16), Position = UDim2.new(1, -59, 0, 4), BackgroundTransparency = 1,
			Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.accent,
			TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(default), Parent = c,
		})
		local track = new("Frame", {
			Size = UDim2.new(1, -18, 0, 4), Position = UDim2.fromOffset(9, 30),
			BackgroundColor3 = C.off, BorderSizePixel = 0, Parent = c,
		})
		corner(track, 2)
		local fillBar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = track })
		corner(fillBar, 2)
		local val, dragging = default, false
		local function render()
			fillBar.Size = UDim2.fromScale(math.clamp((val - min) / (max - min), 0, 1), 1)
			out.Text = tostring(val)
		end
		local function apply(x)
			local f = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			local raw = min + f * (max - min)
			val = (max - min) >= 20 and math.round(raw) or math.floor(raw * 100 + .5) / 100
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

	local function button(p, label, cb, tone)
		local b = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = tone or C.panel, BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium, TextSize = 12, Text = label,
			TextColor3 = tone and C.bg or C.text, Parent = p,
		})
		corner(b, 6)
		stroke(b, C.stroke)
		b.MouseButton1Click:Connect(function() task.spawn(cb) end)
		return b
	end

	local function row(p)
		local r = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = p })
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, r)
		return r
	end

	local function mini(p, label, w, cb, tone)
		local b = new("TextButton", {
			Size = UDim2.fromOffset(w or 34, 26), BackgroundColor3 = tone or C.off, BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 11, Text = label,
			TextColor3 = tone and C.bg or C.text, Parent = p,
		})
		corner(b, 5)
		b.MouseButton1Click:Connect(function() task.spawn(cb) end)
		return b
	end

	local function box(p, placeholder, onDone)
		local b = new("TextBox", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.panel, BorderSizePixel = 0,
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.text,
			PlaceholderText = placeholder, Text = "", ClearTextOnFocus = false, Parent = p,
		})
		corner(b, 5)
		if onDone then b.FocusLost:Connect(function() onDone(b.Text) end) end
		return b
	end

	local function label(p, text, h)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, h or 18), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
			TextSize = 10, TextColor3 = C.dim, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = p,
		})
	end

	--==========================================================
	-- 4. core helpers
	--==========================================================
	local function charPart()
		local ch = PLR.Character
		return ch, ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
	end

	local rawRaycast = workspace.Raycast
	local mouse = try(function() return PLR:GetMouse() end)

	local function applyMovement()
		local _, _, hum = charPart()
		if not hum then return end
		hum.WalkSpeed = math.max(1, State.baseSpeed + State.addSpeed)
		hum.UseJumpPower = true
		hum.JumpPower = math.max(1, State.baseJump + State.addJump)
	end

	--==========================================================
	-- 5. combat engine, skidfling, walkfling, anti-fling & spectate
	--==========================================================
	local Aim = {
		on = false, silent = false, wallbang = false, hitbox = false, autoFire = false,
		fov = 260, silentFov = 260, smooth = .35, maxDist = 1200, ignoreTeam = true, wallCheck = true,
		target = nil, headPos = nil,
		silentOffsetX = 0, silentOffsetY = 0, draggingCircle = false,
		showFov = true,
		fovColorR = 124, fovColorG = 152, fovColorB = 255,
		silentColorR = 255, silentColorG = 180, silentColorB = 60,
	}
	local Rapid = { on = false, rate = .05, acc = 0, aimFire = false }
	script_key = "Kayser_AntiFling_Bypass"
	local SkidFlingAll = { on = false }
	
	-- Enhanced WalkFling (Pass-by proximity trigger & velocity spike without freezing self)
	local WalkFling = {
		on = false,
		range = 10,
		power = 9e7,
	}

	-- Anti-Fling / Anti-Freeze State
	local AntiFling = {
		on = false,
	}

	local Hooks = { on = false, orig = nil }
	local fovCircle = nil
	local silentCircle = nil

	local Whitelist = {}
	local function IsWhitelisted(player)
		local nameLower = player.Name:lower()
		for _, wl in ipairs(Whitelist) do
			if wl:lower() == nameLower then return true end
		end
		return false
	end

	local function IsPlayerSeated(target)
		if not target or not target.Parent then return false end
		local char = target.Character
		if not char then return false end
		local hum = char:FindFirstChildOfClass("Humanoid")
		return hum and hum.Sit or false
	end

	local function wallbangRaycast(self, origin, direction, params)
		if params == nil then return rawRaycast(self, origin, direction, params) end
		local o, d, steps = origin, direction, 0
		while steps < 24 do
			steps += 1
			local res = rawRaycast(self, o, d, params)
			if not res then return nil end
			local inst = res.Instance
			local hum = inst and (inst:FindFirstChildOfClass("Humanoid")
				or (inst.Parent and inst.Parent:FindFirstChildOfClass("Humanoid")))
			if hum then return res end
			local travelled = (res.Position - o).Magnitude
			if travelled >= d.Magnitude - .5 then return res end
			o = res.Position + d.Unit * .8
			d = d.Unit * math.max(d.Magnitude - travelled - .8, .5)
		end
		return nil
	end

	local function installHooks()
		if Hooks.on or not (EX.hook and EX.rawmt) then return false end
		local ok, orig = pcall(EX.hook, game, "__index", function(self, key)
			if self == mouse and Aim.silent and Aim.headPos then
				if key == "Hit" then return CFrame.new(Aim.headPos) end
				if key == "Target" then return Aim.target and Aim.target.Character end
				if key == "UnitRay" then
					local o = CAM.CFrame.Position
					return Ray.new(o, (Aim.headPos - o).Unit * 2000)
				end
			end
			if self == workspace and key == "Raycast" and Aim.wallbang then
				return wallbangRaycast
			end
			return orig(self, key)
		end)
		if not ok then return false end
		Hooks.on, Hooks.orig = true, orig
		return true
	end

	local function removeHooks()
		if not Hooks.on or not EX.hook then return end
		pcall(EX.hook, game, "__index", Hooks.orig)
		Hooks.on = false
	end

	local function bodyOf(p)
		local ch = p.Character
		if not ch then return end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		return ch, hum, ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
	end

	local function onScreen(pos)
		local sp, vis = CAM:WorldToViewportPoint(pos)
		if sp.Z <= 0 then return nil end
		local vp = CAM.ViewportSize
		local center = Vector2.new(vp.X * .5, vp.Y * .5)
		local screenPos = Vector2.new(sp.X, sp.Y)
		local activeCenter = center + Vector2.new(Aim.silentOffsetX, Aim.silentOffsetY)
		if Aim.silent then
			local d = (screenPos - activeCenter).Magnitude
			if d > Aim.silentFov then return nil end
			return d
		else
			local d = (screenPos - activeCenter).Magnitude
			if d > Aim.fov then return nil end
			return d
		end
	end

	local function canSee(ch, pos)
		if not Aim.wallCheck then return true end
		local camPos = CAM.CFrame.Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ch }
		return rawRaycast(workspace, camPos, pos - camPos, params) ~= nil
	end

	local function acquire()
		local best, bestScore, bestPos
		local _, myRoot = charPart()
		for _, p in ipairs(Players:GetPlayers()) do
			local skipTeam = Aim.ignoreTeam and PLR.Team ~= nil and p.Team == PLR.Team
			if p ~= PLR and not skipTeam then
				local ch, _, head = bodyOf(p)
				if ch and head then
					local dist = myRoot and (head.Position - myRoot.Position).Magnitude or 0
					if dist <= Aim.maxDist then
						local score = onScreen(head.Position)
						if score and (bestScore == nil or score < bestScore) and canSee(ch, head.Position) then
							best, bestScore, bestPos = p, score, head.Position
						end
					end
				end
			end
		end
		return best, bestPos
	end

	local function pressFire()
		local ch = PLR.Character
		local tool = ch and ch:FindFirstChildOfClass("Tool")
		if tool then
			pcall(function() tool:Activate() end)
			return
		end
		if EX.input then
			pcall(EX.input)
			return
		end
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end)
	end

	local function updateCircle()
		if not EX.draw then return end
		local vp = CAM.ViewportSize
		local center = Vector2.new(vp.X * .5, vp.Y * .5)
		local activeCenter = center + Vector2.new(Aim.silentOffsetX, Aim.silentOffsetY)

		if fovCircle then
			local showNormal = Aim.on and Aim.showFov and not Aim.silent
			fovCircle.Visible = showNormal
			if showNormal then
				fovCircle.Position = activeCenter
				fovCircle.Radius = Aim.fov
				fovCircle.Color = Aim.target and C.on or Color3.fromRGB(Aim.fovColorR, Aim.fovColorG, Aim.fovColorB)
			end
		end

		if silentCircle then
			local showSilent = Aim.on and Aim.showFov and Aim.silent
			silentCircle.Visible = showSilent
			if showSilent then
				silentCircle.Position = activeCenter
				silentCircle.Radius = Aim.silentFov
				silentCircle.Color = Aim.target and C.on or Color3.fromRGB(Aim.silentColorR, Aim.silentColorG, Aim.silentColorB)
			end
		end
	end

	-- Integrated SkidFling Routine (Targeted Fling)
	local function ExecuteSkidFling(TargetPlayer)
		if not TargetPlayer or not TargetPlayer.Parent then return false end
		if IsPlayerSeated(TargetPlayer) then return false end

		local Character = PLR.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Humanoid and Humanoid.RootPart

		local TCharacter = TargetPlayer.Character
		local THumanoid = TCharacter and TCharacter:FindFirstChildOfClass("Humanoid")
		local TRootPart = THumanoid and THumanoid.RootPart
		local THead = TCharacter and TCharacter:FindFirstChild("Head")
		local Accessory = TCharacter and TCharacter:FindFirstChildOfClass("Accessory")
		local Handle = Accessory and Accessory:FindFirstChild("Handle")

		if not (Character and Humanoid and RootPart) then return false end

		local oldPos = RootPart.CFrame
		if RootPart.Velocity.Magnitude < 50 then
			oldPos = RootPart.CFrame
		end

		if THead then
			workspace.CurrentCamera.CameraSubject = THead
		elseif Handle then
			workspace.CurrentCamera.CameraSubject = Handle
		elseif THumanoid and TRootPart then
			workspace.CurrentCamera.CameraSubject = THumanoid
		end

		if not TCharacter:FindFirstChildWhichIsA("BasePart") then return false end

		local function FPos(BasePart, Pos, Ang)
			if not BasePart or not BasePart.Parent then return end
			if not RootPart or not RootPart.Parent then return end
			if not Character or not Character.Parent then return end

			RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
			Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
			RootPart.Velocity = Vector3.new(9e7, 9e8, 9e7)
			RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
		end

		local function SFBasePart(BasePart)
			local Time = tick()
			local Angle = 0

			repeat
				if RootPart and THumanoid then
					if BasePart.Velocity.Magnitude < 50 then
						Angle = Angle + 100
						FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
						FPos(BasePart, CGrade.new(0, 1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection, CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
					else
						FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude/1.25), CFrame.Angles(math.rad(90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, -TRootPart.Velocity.Magnitude/1.25), CFrame.Angles(0, 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude/1.25), CFrame.Angles(math.rad(90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(-90), 0, 0)); task.wait()
						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0)); task.wait()
					end
				else
					break
				end
			until BasePart.Velocity.Magnitude > 500
				or BasePart.Parent ~= TargetPlayer.Character
				or TargetPlayer.Parent ~= Players
				or THumanoid.Sit
				or Humanoid.Health <= 0
				or tick() > Time + 2
		end

		local fpdh = workspace.FallenPartsDestroyHeight
		workspace.FallenPartsDestroyHeight = 0/0
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

		if TRootPart and THead then
			if (TRootPart.CFrame.p - THead.CFrame.p).Magnitude > 5 then
				SFBasePart(THead)
			else
				SFBasePart(TRootPart)
			end
		elseif TRootPart and not THead then
			SFBasePart(TRootPart)
		elseif not TRootPart and THead then
			SFBasePart(THead)
		elseif Accessory and Handle then
			SFBasePart(Handle)
		end

		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
		workspace.CurrentCamera.CameraSubject = Humanoid

		repeat
			if not RootPart or not RootPart.Parent then break end
			if not Character or not Character.Parent then break end
			RootPart.CFrame = oldPos * CFrame.new(0, .5, 0)
			Character:SetPrimaryPartCFrame(oldPos * CFrame.new(0, .5, 0))
			Humanoid:ChangeState("GettingUp")
			for _, x in ipairs(Character:GetChildren()) do
				if x:IsA("BasePart") then
					x.Velocity = Vector3.new()
					x.RotVelocity = Vector3.new()
				end
			end
			task.wait()
		until (RootPart.Position - oldPos.p).Magnitude < 25

		workspace.FallenPartsDestroyHeight = fpdh
		return true
	end

	-- Pass-by / Touch WalkFling implementation (flings players in front/near without anchoring or freezing self)
	local function walkFlingTick()
		if not WalkFling.on then return end
		local ch, root, hum = charPart()
		if not root or not hum then return end

		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= PLR and not IsWhitelisted(p) then
				local pch, _, phrp = bodyOf(p)
				if phrp then
					local dist = (phrp.Position - root.Position).Magnitude
					-- Check if player is within range or directly passing in front/near
					if dist <= WalkFling.range then
						pcall(function()
							phrp.AssemblyLinearVelocity = Vector3.new(WalkFling.power, WalkFling.power, WalkFling.power)
							phrp.AssemblyRotVelocity = Vector3.new(WalkFling.power, WalkFling.power, WalkFling.power)
						end)
					end
				end
			end
		end
	end

	-- Anti-Fling & Anti-Freeze Loop (Nullifies extreme incoming velocities and clears rotational locks)
	local function antiFlingTick()
		if not AntiFling.on then return end
		local ch, root, hum = charPart()
		if not root then return end

		pcall(function()
			if root.AssemblyLinearVelocity.Magnitude > 300 or root.AssemblyRotVelocity.Magnitude > 300 then
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				root.AssemblyRotVelocity = Vector3.new(0, 0, 0)
			end
			for _, part in ipairs(ch:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0, 1, 1)
					if part.Velocity.Magnitude > 300 then
						part.Velocity = Vector3.new(0, 0, 0)
					end
				end
			end
		end)
	end

	local acquireAcc = 0
	local function combatTick(dt)
		if Aim.on then
			acquireAcc += dt
			if acquireAcc >= 0.033 then
				acquireAcc = 0
				local ok, t, h = pcall(acquire)
				if ok then Aim.target, Aim.headPos = t, h end
			end
			updateCircle()
			if Aim.target and Aim.headPos and not Aim.silent then
				local goal = CFrame.lookAt(CAM.CFrame.Position, Aim.headPos)
				CAM.CFrame = Aim.smooth <= 0 and goal or CAM.CFrame:Lerp(goal, math.clamp(1 - Aim.smooth, .04, 1))
			end
		end
		Rapid.aimFire = Aim.on and Aim.autoFire and Aim.target ~= nil
		if Rapid.on or Rapid.aimFire then
			Rapid.acc += dt
			if Rapid.acc >= Rapid.rate then
				Rapid.acc = 0
				task.spawn(pressFire)
			end
		end

		if WalkFling.on then
			walkFlingTick()
		end

		if AntiFling.on then
			antiFlingTick()
		end

		if State.spectating then
			local targetPlr = Players:FindFirstChild(State.spectating)
			local ch = targetPlr and targetPlr.Character
			local head = ch and ch:FindFirstChild("Head")
			if head then
				CAM.CameraSubject = head
			else
				CAM.CameraSubject = PLR.Character and PLR.Character:FindFirstChildOfClass("Humanoid")
			end
		end
	end

	local function ensureCombat()
		if Aim.on or Rapid.on or SkidFlingAll.on or WalkFling.on or AntiFling.on or State.spectating then
			if not State.conns.combat then
				State.conns.combat = hook(RunService.RenderStepped, combatTick)
			end
		elseif State.conns.combat and not (Aim.on or Rapid.on or SkidFlingAll.on or WalkFling.on or AntiFling.on or State.spectating) then
			State.conns.combat:Disconnect()
			State.conns.combat = nil
			Aim.target, Aim.headPos = nil, nil
			updateCircle()
		end
		if Aim.on or Aim.wallbang then installHooks() else removeHooks() end
	end

	-- Auto SkidFling Loop Thread
	task.spawn(function()
		while true do
			if SkidFlingAll.on then
				local targets = {}
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= PLR and not IsWhitelisted(p) then
						table.insert(targets, p)
					end
				end

				if #targets == 0 then
					task.wait(1)
				else
					for _, target in ipairs(targets) do
						if not SkidFlingAll.on then break end
						if not target or not target.Parent then continue end
						if IsWhitelisted(target) then continue end

						local char = PLR.Character
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						if not char or not char.Parent or not hum or hum.Health <= 0 then
							repeat
								task.wait(0.5)
								char = PLR.Character
								hum = char and char:FindFirstChildOfClass("Humanoid")
							until char and char.Parent and hum and hum.Health > 0
							task.wait(1)
						end

						if IsPlayerSeated(target) then
							task.wait(0.2)
							continue
						end

						pcall(function()
							ExecuteSkidFling(target)
						end)

						task.wait(0.3)
					end
					task.wait(1)
				end
			else
				task.wait(0.5)
			end
		end
	end)

	local function dropHitbox(p)
		local hb = Hitboxes[p]
		if hb then pcall(function() hb:Destroy() end) end
		Hitboxes[p] = nil
	end

	local function makeHitbox(p)
		if Hitboxes[p] or p == PLR then return end
		local ch = p.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local hb = new("Part", {
			Name = "KAYSER_HITBOX", Size = Vector3.new(9, 9, 9), Transparency = .72,
			Color = C.accent, CanCollide = false, CanQuery = true, CanTouch = true,
			Massless = true, CastShadow = false, Parent = hrp,
		})
		new("WeldConstraint", { Part0 = hrp, Part1 = hb, Parent = hb })
		Hitboxes[p] = hb
	end

	function Features.hitbox(on)
		Aim.hitbox = on
		for _, p in ipairs(Players:GetPlayers()) do
			if on then makeHitbox(p) else dropHitbox(p) end
		end
		if on and not State.conns.hitRefresh then
			local acc = 0
			State.conns.hitRefresh = hook(RunService.Heartbeat, function(dt)
				acc += dt
				if acc < 1 then return end
				acc = 0
				for _, p in ipairs(Players:GetPlayers()) do makeHitbox(p) end
			end)
		elseif not on and State.conns.hitRefresh then
			State.conns.hitRefresh:Disconnect()
			State.conns.hitRefresh = nil
		end
		notify("hitbox " .. (on and "on" or "off"))
	end

	--==========================================================
	-- 6. movement / visuals / teleport / spectate
	--==========================================================
	function Features.esp(on)
		State.esp = on
		local function build(p)
			if p == PLR or ESP[p] then return end
			local ch = p.Character
			if not (ch and ch:FindFirstChild("Head")) then return end
			local set = {}
			set.hl = new("Highlight", {
				Name = "KAYSER_ESP", Adornee = ch, FillColor = C.accent, FillTransparency = .72,
				OutlineColor = Color3.new(1, 1, 1), DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Parent = ch,
			})
			set.gui = new("BillboardGui", {
				Name = "KAYSER_TAG", Adornee = ch.Head, Size = UDim2.fromOffset(200, 26),
				StudsOffset = Vector3.new(0, 2.3, 0), AlwaysOnTop = true, Parent = ch.Head,
			})
			set.txt = new("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
				TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = .35,
				Text = p.Name, Parent = set.gui,
			})
			ESP[p] = set
		end
		local function clear(p)
			local set = ESP[p]
			if not set then return end
			for _, o in pairs(set) do pcall(function() o:Destroy() end) end
			ESP[p] = nil
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if on then build(p) else clear(p) end
		end
		if on and not State.conns.espRefresh then
			local acc = 0
			State.conns.espRefresh = hook(RunService.Heartbeat, function(dt)
				acc += dt
				if acc < 1 then return end
				acc = 0
				local _, root = charPart()
				for p, set in pairs(ESP) do
					local ch = p.Character
					local head = ch and ch:FindFirstChild("Head")
					if head and root and set.txt then
						set.txt.Text = ("%s [%dm]"):format(p.Name, (head.Position - root.Position).Magnitude)
					end
				end
			end)
		elseif not on and State.conns.espRefresh then
			State.conns.espRefresh:Disconnect()
			State.conns.espRefresh = nil
		end
		notify("ESP " .. (on and "on" or "off"))
	end

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
			Lighting.FogEnd = 1e5
		elseif State.light then
			for k, v in pairs(State.light) do Lighting[k] = v end
			State.light = nil
		end
	end

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
		end
	end

	function Features.fly(on)
		State.fly = on
		local _, hrp = charPart()
		if on then
			if not hrp then
				State.fly = false
				return notify("no character")
			end
			State.flyParts = {
				new("BodyVelocity", { Name = "KAYSER_V", MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = hrp }),
				new("BodyGyro", { Name = "KAYSER_G", MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2000, D = 60, Parent = hrp }),
			}
			State.conns.fly = hook(RunService.RenderStepped, function()
				local _, root = charPart()
				if not root or not State.flyParts[1].Parent then return end
				local cf = CAM.CFrame
				local mv = Vector3.zero
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then mv += cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then mv -= cf.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then mv += cf.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then mv -= cf.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.Space) then mv += Vector3.yAxis end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then mv -= Vector3.yAxis end
				State.flyParts[1].Velocity = mv.Magnitude > 0
					and mv.Unit * ((State.baseSpeed + State.addSpeed) * 3) or Vector3.zero
				State.flyParts[2].CFrame = cf
			end)
		else
			if State.conns.fly then State.conns.fly:Disconnect() end
			if State.flyParts then
				for _, o in ipairs(State.flyParts) do pcall(function() o:Destroy() end) end
				State.flyParts = nil
			end
		end
	end

	function Features.infJump(on)
		State.infJump = on
		if State.conns.infJump then State.conns.infJump:Disconnect() end
		if on then
			State.conns.infJump = hook(UserInputService.JumpRequest, function()
				local _, _, hum = charPart()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		end
	end

	function Features.antiVoid(on)
		State.antiVoid = on
		if State.conns.void then
			State.conns.void:Disconnect()
			State.conns.void = nil
		end
		if on then
			State.conns.void = hook(RunService.Heartbeat, function()
				local ch, root = charPart()
				if not ch or not root then return end
				if root.Position.Y > State.voidY + 15 then
					State.safeCF = root.CFrame
				elseif root.Position.Y < State.voidY and State.safeCF then
					pcall(function() ch:PivotTo(State.safeCF) end)
					notify("anti-void pulled you back", 2)
				end
			end)
		end
	end

	function Features.speed(v)
		State.addSpeed = v
		if Widgets.sliders["+ WalkSpeed"] then Widgets.sliders["+ WalkSpeed"].set(v) end
		applyMovement()
	end

	function Features.jump(v)
		State.addJump = v
		if Widgets.sliders["+ JumpPower"] then Widgets.sliders["+ JumpPower"].set(v) end
		applyMovement()
	end

	function Features.teleport(cf)
		local ch = charPart()
		if not ch or not cf then return end
		pcall(function() ch:PivotTo(cf + Vector3.new(0, 3, 0)) end)
	end

	function Features.teleportMouse()
		local loc = UserInputService:GetMouseLocation()
		local ray = CAM:ViewportPointToRay(loc.X, loc.Y)
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

	function Features.spectatePlayer(name)
		if name == "" or name == State.spectating then
			State.spectating = nil
			CAM.CameraSubject = PLR.Character and PLR.Character:FindFirstChildOfClass("Humanoid")
			notify("spectate off")
		else
			State.spectating = name
			notify("spectating " .. name)
		end
		ensureCombat()
	end

	local function persistWaypoints()
		if not IO.ok then return end
		local out = {}
		for name, cf in pairs(State.waypoints) do out[name] = { cf:GetComponents() } end
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
		notify("saved " .. name)
	end

	--==========================================================
	-- 7. auto-flood engine
	--==========================================================
	local Flood = {
		running = false, busy = false, created = 0, fires = 0, inflight = 0,
		cands = {}, selected = nil, variant = "cframe", prefix = {},
		budget = 5000, rate = 450, localMode = false, anchored = true,
		conn = nil, target = "",
	}

	local old = workspace:FindFirstChild("KayserSpam")
	if old then old:Destroy() end
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
		"part", "build", "place", "spawn", "create", "add", "draw", "block", "brick",
		"make", "paint", "item", "object", "cube", "prop", "model", "plot", "emit", "mesh",
	}

	local function scoreName(name)
		local n = name:lower()
		local s = 0
		for _, k in ipairs(KEYWORDS) do if n:find(k, 1, true) then s += 10 end end
		if n:find("^r?f_") then s += 1 end
		if n:find("effect", 1, true) or n:find("vfx", 1, true) then s += 4 end
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
			(math.random() - .5) * spread, (math.random() - .5) * spread, (math.random() - .5) * spread
		) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
	end

	local function buildPayload(cf)
		local v = Flood.variant
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
		for i = 1, #Flood.prefix do args[#args + 1] = Flood.prefix[i] end
		local p1, p2 = buildPayload(cf)
		args[#args + 1] = p1
		if p2 ~= nil then args[#args + 1] = p2 end
		if o:IsA("RemoteEvent") then
			pcall(o.FireServer, o, table.unpack(args))
		else
			if Flood.inflight > 40 then return end
			Flood.inflight += 1
			task.spawn(function()
				pcall(o.InvokeServer, o, table.unpack(args))
				Flood.inflight -= 1
			end)
		end
		Flood.fires += 1
	end

	function Flood.stop(reason)
		if not Flood.running then return end
		Flood.running = false
		if Flood.conn then
			Flood.conn:Disconnect()
			Flood.conn = nil
		end
		notify(("stopped [%s] · %d fires · %d parts"):format(reason or "manual", Flood.fires, Flood.created), 4)
	end

	local function tryShape(cand, shape)
		Flood.variant = shape
		local hits = 0
		local conn = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") and not isOurs(d) then hits += 1 end
		end)
		pcall(fire, cand, targetCF(Flood.target))
		task.wait(.25)
		pcall(function() conn:Disconnect() end)
		return hits
	end

	function Flood.probe(cand)
		for _, shape in ipairs({ "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }) do
			local hits = tryShape(cand, shape)
			if hits > 0 then return shape, hits end
		end
		return nil, 0
	end

	function Flood.start(name)
		if Flood.running then return notify("already flooding") end
		if not Flood.selected and not Flood.localMode then return notify("no remote selected") end
		Flood.created, Flood.fires = 0, 0
		Flood.running = true
		local base = targetCF(name)
		local budget = Flood.budget
		Flood.conn = workspace.DescendantAdded:Connect(function(d)
			if not d:IsA("BasePart") or isOurs(d) then return end
			Flood.created += 1
			if Flood.created >= budget then Flood.stop("budget") end
		end)
		task.spawn(function()
			while Flood.running do
				if Flood.localMode then
					for _ = 1, Flood.rate do
						if not Flood.running then break end
						new("Part", {
							Name = "KayserPart", Anchored = Flood.anchored,
							CanCollide = not Flood.anchored, CanQuery = false, CanTouch = false,
							Size = Vector3.new(2, 2, 2), Color = Color3.fromHSV(math.random(), .8, 1),
							CFrame = jitter(base, 12), Parent = spamFolder,
						})
						Flood.created += 1
						if Flood.created >= budget then
							Flood.stop("budget")
							break
						end
					end
				else
					for _ = 1, Flood.rate do
						if not Flood.running then break end
						fire(Flood.selected, jitter(base, 8))
					end
				end
				task.wait(1)
			end
		end)
		notify(("flooding %s @ %d/s · cap %d"):format(name ~= "" and name or "server", Flood.rate, budget), 4)
	end

	function Flood.wipe()
		local n = #spamFolder:GetChildren()
		spamFolder:ClearAllChildren()
		notify(("wiped %d local parts"):format(n))
	end

	--==========================================================
	-- 8. pages
	--==========================================================
	local pCombat = page("combat", "Combat")
	local pVis    = page("visual", "Visual")
	local pMove   = page("move", "Movement")
	local pTp     = page("tp", "Teleport")
	local pFlood  = page("flood", "Part flood")
	local pCfg    = page("config", "Config")
	local pMain   = page("main", "Session")
	selectPage("combat")

	local cAim = card(pCombat)
	header(cAim, "aim")
	toggle(cAim, "Aimbot (camera)", false, function(v)
		Aim.on = v
		ensureCombat()
	end)
	toggle(cAim, "Silent aim", false, function(v)
		Aim.silent = v
		if v and not EX.hook then notify("silent aim needs hookmetamethod") end
		ensureCombat()
	end, "hooks Mouse.Hit / UnitRay")
	toggle(cAim, "Wallbang", false, function(v)
		Aim.wallbang = v
		ensureCombat()
	end, "raycast skips non-character hits")
	toggle(cAim, "Auto fire on target", false, function(v)
		Aim.autoFire = v
		ensureCombat()
	end)
	toggle(cAim, "Ignore teammates", true, function(v) Aim.ignoreTeam = v end)
	toggle(cAim, "Wall check", true, function(v) Aim.wallCheck = v end)
	toggle(cAim, "Show FOV circle", true, function(v)
		Aim.showFov = v
		updateCircle()
	end)
	slider(cAim, "FOV radius (px)", 40, 800, 260, function(v) Aim.fov = v end)
	slider(cAim, "Silent FOV radius (px)", 40, 800, 260, function(v) Aim.silentFov = v end)
	slider(cAim, "Silent FOV offset X", -600, 600, 0, function(v) Aim.silentOffsetX = v end)
	slider(cAim, "Silent FOV offset Y", -400, 400, 0, function(v) Aim.silentOffsetY = v end)
	local cFovColor = card(pCombat)
	header(cFovColor, "fov colors")
	slider(cFovColor, "FOV R", 0, 255, 124, function(v) Aim.fovColorR = v end)
	slider(cFovColor, "FOV G", 0, 255, 152, function(v) Aim.fovColorG = v end)
	slider(cFovColor, "FOV B", 0, 255, 255, function(v) Aim.fovColorB = v end)
	slider(cFovColor, "Silent R", 0, 255, 255, function(v) Aim.silentColorR = v end)
	slider(cFovColor, "Silent G", 0, 255, 180, function(v) Aim.silentColorG = v end)
	slider(cFovColor, "Silent B", 0, 255, 60,  function(v) Aim.silentColorB = v end)
	slider(cAim, "Smoothness", 0, 1, .35, function(v) Aim.smooth = v end)
	slider(cAim, "Max distance", 100, 5000, 1200, function(v) Aim.maxDist = v end)

	local cFire = card(pCombat)
	header(cFire, "fire & exploit")
	toggle(cFire, "Rapid fire", false, function(v)
		Rapid.on = v
		ensureCombat()
	end, "spams tool:Activate / mouse1")
	slider(cFire, "Fire interval (s)", .01, .5, .05, function(v) Rapid.rate = v end)
	toggle(cFire, "Hitbox expander", false, Features.hitbox, "9x9 local hitbox")
	toggle(cFire, "SkidFling All", false, function(v)
		SkidFlingAll.on = v
		ensureCombat()
		notify("skidfling all " .. (v and "on" or "off"))
	end, "loops through all targets with SkidFling")
	toggle(cFire, "WalkFling (Pass-by)", false, function(v)
		WalkFling.on = v
		ensureCombat()
		notify("walkfling " .. (v and "on" or "off"))
	end, "flings players when passing near/in front without self-freeze")
	slider(cFire, "WalkFling Range", 4, 30, 10, function(v) WalkFling.range = v end)
	slider(cFire, "WalkFling Power", 1e6, 5e8, 9e7, function(v) WalkFling.power = v end)
	toggle(cFire, "Anti-Fling / Anti-Freeze", false, function(v)
		AntiFling.on = v
		ensureCombat()
		notify("anti-fling " .. (v and "on" or "off"))
	end, "blocks incoming fling forces and unfreezes you")

	local cAimState = card(pCombat, 40)
	header(cAimState, "target")
	local aimLbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Code,
		TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "none", Parent = cAimState,
	})

	local cVis = card(pVis)
	header(cVis, "world")
	toggle(cVis, "Player ESP", false, Features.esp)
	toggle(cVis, "Fullbright", false, Features.fullbright)
	slider(cVis, "Camera FOV", 70, 140, 70, function(v) CAM.FieldOfView = v end)

	local cUnlock = card(pVis)
	header(cUnlock, "client")
	toggle(cUnlock, "Unlock FPS (240)", false, function(v)
		if EX.fps then pcall(EX.fps, v and 240 or 60) end
		notify(v and "fps cap released" or "fps cap restored")
	end)

	local cMove = card(pMove)
	header(cMove, "speed (additive)")
	slider(cMove, "+ WalkSpeed", -16, 500, 0, function(v) Features.speed(v) end)
	local sRow = row(cMove)
	mini(sRow, "-10", 46, function() Features.speed(math.max(-16, State.addSpeed - 10)) end)
	mini(sRow, "+10", 46, function() Features.speed(State.addSpeed + 10) end)
	mini(sRow, "+50", 46, function() Features.speed(State.addSpeed + 50) end)
	mini(sRow, "reset", 52, function() Features.speed(0) end, C.warn)

	header(cMove, "jump (additive)")
	slider(cMove, "+ JumpPower", -50, 500, 0, function(v) Features.jump(v) end)
	local jRow = row(cMove)
	mini(jRow, "-10", 46, function() Features.jump(math.max(-50, State.addJump - 10)) end)
	mini(jRow, "+10", 46, function() Features.jump(State.addJump + 10) end)
	mini(jRow, "+50", 46, function() Features.jump(State.addJump + 50) end)
	mini(jRow, "reset", 52, function() Features.jump(0) end, C.warn)

	local cMove2 = card(pMove)
	header(cMove2, "traversal")
	toggle(cMove2, "Noclip", false, Features.noclip)
	toggle(cMove2, "Infinite jump", false, Features.infJump)
	toggle(cMove2, "Fly (WASD / Space / LCTRL)", false, Features.fly)
	toggle(cMove2, "Anti-void", false, Features.antiVoid, "snaps back below threshold")
	slider(cMove2, "Void Y threshold", -500, 100, -60, function(v) State.voidY = v end)

	local cTp = card(pTp)
	header(cTp, "position")
	button(cTp, "Teleport to cursor", Features.teleportMouse)
	local wpRow = row(cTp)
	local wpHost = new("Frame", { Size = UDim2.new(1, -70, 1, 0), BackgroundTransparency = 1, Parent = wpRow })
	local wpBox = box(wpHost, "waypoint name", function(text)
		Features.saveWaypoint(text)
		Features.renderWaypoints()
	end)
	mini(wpRow, "save", 62, function()
		Features.saveWaypoint(wpBox.Text)
		Features.renderWaypoints()
	end, C.accent)
	local wpList = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = cTp })
	new("UIListLayout", { Padding = UDim.new(0, 4) }, wpList)

	function Features.renderWaypoints()
		for _, c in ipairs(wpList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for name, cf in pairs(State.waypoints) do
			local r = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = wpList })
			local go = new("TextButton", {
				Size = UDim2.new(1, -52, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0,
				Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.text,
				TextXAlignment = Enum.TextXAlignment.Left, Text = "  " .. name, Parent = r,
			})
			corner(go, 5)
			go.MouseButton1Click:Connect(function() Features.teleport(cf) end)
			local del = new("TextButton", {
				Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0, 0), BackgroundColor3 = C.off,
				BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.text,
				Text = "del", Parent = r,
			})
			corner(del, 5)
			del.MouseButton1Click:Connect(function()
				State.waypoints[name] = nil
				persistWaypoints()
				Features.renderWaypoints()
			end)
		end
	end

	local cPlr = card(pTp)
	header(cPlr, "players (click to tp / spectate)")
	local plrList = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = cPlr })
	new("UIListLayout", { Padding = UDim.new(0, 4) }, plrList)

	local function refreshPlayers()
		for _, c in ipairs(plrList:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= PLR then
				local ch = p.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				local r = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = plrList })
				local go = new("TextButton", {
					Size = UDim2.new(1, -98, 1, 0), BackgroundColor3 = C.panel, BorderSizePixel = 0,
					Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = C.text, Text = "  " .. p.Name, Parent = r,
				})
				corner(go, 5)
				go.MouseButton1Click:Connect(function() Features.teleportPlayer(p.Name) end)
				
				local spec = new("TextButton", {
					Size = UDim2.fromOffset(44, 24), Position = UDim2.new(1, -94, 0, 0), BackgroundColor3 = C.off,
					BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.text,
					Text = "spec", Parent = r,
				})
				corner(spec, 5)
				spec.MouseButton1Click:Connect(function() Features.spectatePlayer(p.Name) end)

				new("TextLabel", {
					Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0, 0), BackgroundColor3 = C.card,
					BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 10, TextColor3 = C.on,
					Text = hum and tostring(math.floor(hum.Health)) or "-", Parent = r,
				})
			end
		end
	end

	local roster = ""
	task.spawn(function()
		while not State.killed and Gui.Parent do
			local sig = ""
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= PLR then
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					sig ..= p.Name .. (hum and math.floor(hum.Health) or "-") .. "|"
				end
			end
			if sig ~= roster then
				roster = sig
				refreshPlayers()
			end
			task.wait(1)
		end
	end)

	local cTarget = card(pFlood)
	header(cTarget, "target")
	local tHost = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = cTarget })
	local targetBox = box(tHost, "player name (blank = server centre)")
	label(cTarget, "auto mode scores build-named remotes, probes them in order, floods the first that produces parts.")

	local cAuto = card(pFlood)
	header(cAuto, "auto")
	button(cAuto, "Auto find · probe · flood", function()
		if Flood.busy or Flood.running then return notify("engine busy") end
		Flood.busy = true
		Flood.target = targetBox.Text
		Flood.cands = pool()
		Flood.render()
		notify(("%d remotes · probing"):format(#Flood.cands), 4)
		local chosen, shape
		for i = 1, math.min(#Flood.cands, 6) do
			local cand = Flood.cands[i]
			Flood.selected = cand
			Flood.render()
			local s, hits = Flood.probe(cand)
			if s then
				chosen, shape = cand, s
				notify(("hit %s · %s · +%d"):format(cand.obj.Name, s, hits), 4)
				break
			end
		end
		Flood.busy = false
		if chosen then
			Flood.variant = shape
			Flood.start(Flood.target)
		else
			notify("no remote produced parts — manual pick needed", 5)
		end
	end, C.accent)
	toggle(cAuto, "Local mode (no remote)", false, function(v)
		Flood.localMode = v
		notify(v and "local only — your client" or "remote mode")
	end)

	local cRemotes = card(pFlood)
	header(cRemotes, "remotes")
	local filterHost = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = cRemotes })
	local filterBox = box(filterHost, "filter name…")
	local list = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 130), BackgroundColor3 = C.bg, BorderSizePixel = 0,
		ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = cRemotes,
	})
	corner(list, 5)
	new("UIListLayout", { Padding = UDim.new(0, 3) }, list)

	function Flood.render()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
		end
		local filter = filterBox.Text:lower()
		local shown = 0
		for _, entry in ipairs(Flood.cands) do
			local name = entry.obj:GetFullName()
			if filter == "" or name:lower():find(filter, 1, true) then
				shown += 1
				if shown > 60 then break end
				local sel = (Flood.selected == entry)
				local r = new("TextButton", {
					Size = UDim2.new(1, -6, 0, 21), BackgroundColor3 = sel and C.accent or C.panel,
					BorderSizePixel = 0, Font = Enum.Font.Code, TextSize = 10,
					TextColor3 = sel and C.bg or C.dim, TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Text = ("%s%s [%d]"):format(entry.obj:IsA("RemoteFunction") and "RF " or "RE ", name, entry.score),
					Parent = list,
				})
				corner(r, 4)
				r.MouseButton1Click:Connect(function()
					Flood.selected = entry
					Flood.render()
				end)
			end
		end
		if #Flood.cands == 0 then label(list, "  press search") end
	end
	filterBox:GetPropertyChangedSignal("Text"):Connect(function() Flood.render() end)

	local cManual = card(pFlood)
	header(cManual, "manual")
	local mRow1 = row(cManual)
	mini(mRow1, "search", 68, function()
		Flood.cands = pool()
		Flood.selected = nil
		Flood.render()
		notify(("%d remotes"):format(#Flood.cands))
	end)
	local shapeBtn = mini(mRow1, "shape: cframe", 110, function()
		local cycles = { "cframe", "pos", "table_cf", "cf_size", "name_cf", "table_full", "double" }
		for i, s in ipairs(cycles) do
			if s == Flood.variant then
				Flood.variant = cycles[(i % #cycles) + 1]
				break
			end
		end
		shapeBtn.Text = "shape: " .. Flood.variant
	end)
	mini(mRow1, "probe", 56, function()
		if Flood.busy or not Flood.selected then return notify("select a remote") end
		Flood.busy = true
		local s, hits = Flood.probe(Flood.selected)
		Flood.busy = false
		if s then notify(("hit %s · +%d"):format(s, hits), 4) else notify("no shape worked", 4) end
		Flood.render()
	end)
	local preHost = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = cManual })
	box(preHost, "prefix args (5,wood)", function(text)
		Flood.prefix = {}
		for piece in text:gmatch("[^,]+") do
			piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
			Flood.prefix[#Flood.prefix + 1] = tonumber(piece) or piece
		end
		notify(("%d prefix args"):format(#Flood.prefix))
	end)
	slider(cManual, "Rate per second", 50, 2000, 450, function(v) Flood.rate = v end)
	slider(cManual, "Part budget", 200, 40000, 5000, function(v) Flood.budget = math.floor(v) end)
	toggle(cManual, "Unanchored (violent)", false, function(v) Flood.anchored = not v end)
	button(cManual, "Flood target", function()
		Flood.target = targetBox.Text
		Flood.start(Flood.target)
	end)
	local mRow2 = row(cManual)
	mini(mRow2, "stop", 60, function() Flood.stop("manual") end, C.warn)
	mini(mRow2, "wipe local", 90, Flood.wipe)
	local floodLbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Code,
		TextSize = 10, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = "idle", Parent = cManual,
	})

	local cStore = card(pCfg)
	header(cStore, "preset store")
	local cfgGet = {
		esp = function() return State.esp end, fullbright = function() return State.fullbright end,
		noclip = function() return State.noclip end, fly = function() return State.fly end,
		infJump = function() return State.infJump end, antiVoid = function() return State.antiVoid end,
		silent = function() return Aim.silent end, wallbang = function() return Aim.wallbang end,
		autoFire = function() return Aim.autoFire end, hitbox = function() return Aim.hitbox end,
		addSpeed = function() return State.addSpeed end, addJump = function() return State.addJump end,
		fov = function() return Aim.fov end, smooth = function() return Aim.smooth end,
	}
	button(cStore, "Save settings", function()
		if not IO.ok then return notify("no filesystem") end
		local out = {}
		for k, get in pairs(cfgGet) do out[k] = get() end
		pcall(IO.write, IO.dir .. "/config.json", HttpService:JSONEncode(out))
		notify("saved")
	end)
	button(cStore, "Load settings", function()
		if not IO.ok then return notify("no filesystem") end
		local ok, raw = pcall(IO.read, IO.dir .. "/config.json")
		if not ok then return notify("no config") end
		local ok2, d = pcall(function() return HttpService:JSONDecode(raw) end)
		if not ok2 then return end
		local map = {
			["Player ESP"] = "esp", Fullbright = "fullbright", Noclip = "noclip",
			["Fly (WASD / Space / LCTRL)"] = "fly", ["Infinite jump"] = "infJump",
			["Anti-void"] = "antiVoid", ["Silent aim"] = "silent", Wallbang = "wallbang",
			["Auto fire on target"] = "autoFire", ["Hitbox expander"] = "hitbox",
		}
		for key, w in pairs(Widgets.toggles) do
			local f = map[key]
			if f and d[f] ~= nil and w.set then w.set(d[f]) end
		end
		if d.addSpeed then Features.speed(d.addSpeed) end
		if d.addJump then Features.jump(d.addJump) end
		if d.fov and Widgets.sliders["FOV radius (px)"] then
			Aim.fov = d.fov
			Widgets.sliders["FOV radius (px)"].set(d.fov)
		end
		notify("loaded")
	end)

	local cDebug = card(pCfg)
	header(cDebug, "runtime")
	local dbg = label(cDebug, "ready", 40)
	local function log(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		dbg.Text = table.concat(parts, " ")
	end

	local cSess = card(pMain)
	header(cSess, "session")
	button(cSess, "Rejoin", function() game:GetService("TeleportService"):Teleport(game.PlaceId, PLR) end)
	button(cSess, "Copy JobId", function()
		if EX.clip then
			pcall(EX.clip, game.JobId)
			notify("copied")
		else
			notify("no clipboard")
		end
	end)
	button(cSess, "Unload", function() try(ENV.__KAYSER_UNLOAD) end, C.warn)

	local cInfo = card(pMain)
	header(cInfo, "info")
	label(cInfo, ("executor: %s\nhook: %s · drawing: %s · filesystem: %s"):format(
		tostring(EX.hint or "unknown"), EX.hook and "yes" or "no",
		EX.draw and "yes" or "no", IO.ok and "yes" or "no"), 46)
	label(cInfo, "Silent aim and wallbang only bite in client-authoritative games. Hitboxes are local, so they only help where the client computes the hit.", 46)

	--==========================================================
	-- 9. lifecycle
	--==========================================================
	State.conns.uinput = UserInputService.InputBegan:Connect(function(i, processed)
		if processed or not Gui.Parent then return end
		if i.KeyCode == Enum.KeyCode.RightShift then
			Gui.Enabled = not Gui.Enabled
		elseif i.KeyCode == Enum.KeyCode.End then
			try(ENV.__KAYSER_UNLOAD)
		elseif i.KeyCode == Enum.KeyCode.Home then
			Gui.Enabled = true
			selectPage("combat")
		end
	end)

	State.conns.char = PLR.CharacterAdded:Connect(function()
		task.wait(.6)
		if State.killed then return end
		if State.fly then
			Features.fly(false)
			Features.fly(true)
		end
		applyMovement()
	end)

	do
		local _, _, hum = charPart()
		if hum then
			State.baseSpeed = hum.WalkSpeed
			State.baseJump = hum.JumpPower > 0 and hum.JumpPower or 50
		end
		State.baseFov = CAM.FieldOfView
	end

	task.spawn(function()
		local fps, acc, frames, uiAcc = 0, 0, 0, 0
		while not State.killed and Gui.Parent do
			local dt = RunService.RenderStepped:Wait()
			frames += 1
			acc += dt
			uiAcc += dt
			if acc >= .5 then
				fps = math.floor(frames / acc)
				acc, frames = 0, 0
			end
			if uiAcc < 0.1 then continue end
			uiAcc = 0
			pcall(function()
				local status = footer:FindFirstChild("status")
				if status then
					local ping = try(function()
						return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
					end)
					status.Text = ("%d fps · %s ms · combat %s · flood %s"):format(
						fps, ping and tostring(ping) or "-",
						Aim.on and (Aim.silent and "silent" or "aimbot") or "off",
						Flood.running and "run" or "idle")
				end
				aimLbl.Text = Aim.target and (Aim.target.Name .. " · " .. math.floor(Aim.silent and Aim.silentFov or Aim.fov) .. "px") or "none"
				floodLbl.TextColor3 = Flood.running and C.on or C.dim
				if Flood.running then
					floodLbl.Text = ("RUN %d fires · %d/%d parts"):format(Flood.fires, Flood.created, Flood.budget)
				else
					floodLbl.Text = ("idle · %s · %s"):format(
						Flood.selected and Flood.selected.obj.Name or "no remote", Flood.variant)
				end
			end)
		end
	end)

	ENV.__KAYSER_UNLOAD = function()
		if State.killed then return end
		State.killed = true
		for _, c in pairs(State.conns) do pcall(function() c:Disconnect() end) end
		State.conns = {}
		removeHooks()
		if fovCircle then
			pcall(function() fovCircle:Remove() end)
			fovCircle = nil
		end
		if silentCircle then pcall(function() silentCircle:Remove() end) silentCircle = nil end
		for p, set in pairs(ESP) do
			for _, o in pairs(set) do pcall(function() o:Destroy() end) end
			ESP[p] = nil
		end
		for p, hb in pairs(Hitboxes) do
			pcall(function() hb:Destroy() end)
			Hitboxes[p] = nil
		end
		if State.flyParts then
			for _, o in ipairs(State.flyParts) do pcall(function() o:Destroy() end) end
		end
		if State.light then for k, v in pairs(State.light) do Lighting[k] = v end end
		Flood.running = false
		if Flood.conn then Flood.conn:Disconnect() end
		spamFolder:Destroy()
		if EX.fps then pcall(EX.fps, 60) end
		CAM.FieldOfView = State.baseFov
		CAM.CameraSubject = PLR.Character and PLR.Character:FindFirstChildOfClass("Humanoid")
		local _, _, hum = charPart()
		if hum then
			hum.WalkSpeed = State.baseSpeed
			if State.baseJump > 0 then
				hum.UseJumpPower = true
				hum.JumpPower = State.baseJump
			end
		end
		Gui:Destroy()
		ENV.__KAYSER_LOADED = nil
		ENV.__KAYSER_UNLOAD = nil
		notify("unloaded", 2)
	end
	ENV.__KAYSER_LOADED = true

	--==========================================================
	-- 10. boot
	--==========================================================
	if EX.draw then
		fovCircle = try(function() return Drawing.new("Circle") end)
		if fovCircle then
			fovCircle.Thickness = 1.5
			fovCircle.Filled = false
			fovCircle.NumSides = 64
			fovCircle.Transparency = .8
			fovCircle.Visible = false
		end
		silentCircle = try(function() return Drawing.new("Circle") end)
		if silentCircle then
			silentCircle.Thickness = 1.5
			silentCircle.Filled = false
			silentCircle.NumSides = 64
			silentCircle.Transparency = .8
			silentCircle.Visible = false
		end
	end

	do
		local dragging = false
		local dragStart = nil
		local offsetStart = nil
		State.conns.fovDrag = UserInputService.InputBegan:Connect(function(i, processed)
			if processed then return end
			if i.UserInputType == Enum.UserInputType.MouseButton2 then
				local vp = CAM.ViewportSize
				local center = Vector2.new(vp.X * .5, vp.Y * .5)
				local circleCenter = center + Vector2.new(Aim.silentOffsetX, Aim.silentOffsetY)
				local mousePos = Vector2.new(i.Position.X, i.Position.Y)
				local activeRadius = Aim.silent and Aim.silentFov or Aim.fov
				if (mousePos - circleCenter).Magnitude <= activeRadius + 16 then
					dragging = true
					dragStart = mousePos
					offsetStart = Vector2.new(Aim.silentOffsetX, Aim.silentOffsetY)
				end
			end
		end)
		State.conns.fovDragMove = UserInputService.InputChanged:Connect(function(i)
			if not dragging then return end
			if i.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = Vector2.new(i.Position.X, i.Position.Y) - dragStart
				Aim.silentOffsetX = math.clamp(offsetStart.X + delta.X, -600, 600)
				Aim.silentOffsetY = math.clamp(offsetStart.Y + delta.Y, -400, 400)
				if Widgets.sliders["Silent FOV offset X"] then Widgets.sliders["Silent FOV offset X"].set(math.floor(Aim.silentOffsetX)) end
				if Widgets.sliders["Silent FOV offset Y"] then Widgets.sliders["Silent FOV offset Y"].set(math.floor(Aim.silentOffsetY)) end
			end
		end)
		State.conns.fovDragEnd = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton2 then
				dragging = false
			end
		end)
	end

	Features.loadWaypoints()
	Features.renderWaypoints()
	Flood.render()
	applyMovement()
	log("executor:", tostring(EX.hint or "unknown"), "| hook:", EX.hook and "yes" or "no",
		"| drawing:", EX.draw and "yes" or "no", "| io:", IO.ok and "yes" or "no")
	notify("KAYSER 2.2 loaded · RightShift UI · END unload", 4)
	if not EX.hook then notify("silent aim needs hookmetamethod — non supporté", 6) end

	print("[K] boot complete · gui:", Gui.Parent and Gui.Parent:GetFullName() or "NIL",
		"· enabled:", tostring(Gui.Enabled), "· size:", tostring(win.AbsoluteSize))
end

local ok, err = xpcall(main, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then warn("[K] FATAL " .. tostring(err)) end
