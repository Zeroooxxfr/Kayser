-- !nolint
--[[ =============================================================
  KAYSER 2.6  |  full-stack executor suite (single file, Luau)
  RIGHT SHIFT = toggle UI     END = unload + restore world

  Changelog 2.6 (sur 2.5) :
    - fusion backend telavivpanel (sauf TP)
    - Config.Keys + keybind system
    - FastMod (patch NumberValue/attributs/ModuleScript + AutoFire)
    - Orbit / SpinBot / Swim / Jump (additif)
    - Camlock / Aimbot cursor fallback / View / Kills / NextbotSpam
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
	local ReplicatedStorage   = game:GetService("ReplicatedStorage")
	local ReplicatedFirst     = game:GetService("ReplicatedFirst")
	local ScriptContext       = game:GetService("ScriptContext")

	local player = Players.LocalPlayer
	local CAM = workspace.CurrentCamera

	local function try(fn, ...)
		local ok, a, b, c = pcall(fn, ...)
		if ok then return a, b, c end
	end

	local ENV
	do
		local ok, fn = pcall(function() return getgenv end)
		ENV = (ok and type(fn) == "function") and fn() or _G
	end
	if ENV.__KAYSER_LOADED then try(ENV.__KAYSER_UNLOAD) end

	local EX = {
		hook     = (function() local ok, v = pcall(function() return hookmetamethod end) return ok and type(v) == "function" and v or nil end)(),
		namecall = (function() local ok, v = pcall(function() return getnamecallmethod end) return ok and type(v) == "function" and v or nil end)(),
		rawmt    = try(getrawmetatable),
		input    = try(mouse1click),
		clip     = try(setclipboard),
		fps      = try(setfpscap),
		draw     = try(function() return typeof(Drawing) == "table" and Drawing or nil end),
		hint     = try(identifyexecutor),
		hookfn   = try(function() return hookfunction end),
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

	local Bypass = {
		enabled = true,
		savedprops = {},
		hooked_index = false,
		hooked_namecall = false,
		hooked_fireserver = false,
		detections_blocked = 0,
		conns = {},
	}

	local function spoof_humanoid(hum)
		if not hum or not hum:IsA("Humanoid") then return end
		if Bypass.savedprops[hum] then return end
		Bypass.savedprops[hum] = {
			WalkSpeed = hum.WalkSpeed,
			JumpPower = hum.JumpPower,
			HipHeight = hum.HipHeight,
		}
	end

	local function restore_humanoid(hum)
		local saved = Bypass.savedprops[hum]
		if not saved then return end
		pcall(function()
			hum.WalkSpeed = saved.WalkSpeed
			hum.JumpPower = saved.JumpPower
			hum.HipHeight = saved.HipHeight
		end)
		Bypass.savedprops[hum] = nil
	end

	if EX.hook then
		local old_index
		local ok = pcall(function()
			old_index = EX.hook(game, "__index", function(self, key)
				if Bypass.enabled and typeof(self) == "Instance" and self:IsA("Humanoid") then
					if key == "WalkSpeed" or key == "JumpPower" then
						Bypass.detections_blocked += 1
						local saved = Bypass.savedprops[self]
						if saved then return saved[key] end
						return 16
					end
				end
				return old_index(self, key)
			end)
		end)
		Bypass.hooked_index = ok and old_index ~= nil
	end

	local AC_PATTERNS = {
		"iac%-respond", "anticheat", "anti%-cheat", "ac%-", "ac_",
		"detect", "ban", "kick", "report", "violation", "flag",
		"exploit", "cheat", "sus", "moderat",
	}

	local function is_ac_name(name)
		local n = name:lower()
		for _, pat in ipairs(AC_PATTERNS) do
			if n:find(pat) then return true end
		end
		return false
	end

	if EX.hook and EX.namecall then
		local old_namecall
		local ok = pcall(function()
			old_namecall = EX.hook(game, "__namecall", function(self, ...)
				local method = EX.namecall()
				if Bypass.enabled and method then
					local m = method:lower()
					if m == "kick" or m == "fire" or m == "invoke" or m == "fireserver" or m == "invokeserver" then
						if typeof(self) == "Instance" and is_ac_name(self.Name) then
							Bypass.detections_blocked += 1
							return
						end
					end
				end
				return old_namecall(self, ...)
			end)
		end)
		Bypass.hooked_namecall = ok and old_namecall ~= nil
	end

	if EX.hookfn then
		local ok = pcall(function()
			local orig
			orig = EX.hookfn(Instance.new("RemoteEvent").FireServer, function(self, ...)
				if Bypass.enabled and typeof(self) == "Instance" and is_ac_name(self.Name) then
					Bypass.detections_blocked += 1
					return
				end
				return orig(self, ...)
			end)
			Bypass.hooked_fireserver = orig ~= nil
		end)
	end

	local function neutralize_ac_remotes()
		local function scan(parent)
			for _, child in ipairs(parent:GetDescendants()) do
				if (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) and is_ac_name(child.Name) then
					if EX.hookfn then
						pcall(function()
							if child:IsA("RemoteEvent") then
								EX.hookfn(child.FireServer, function() end)
							else
								EX.hookfn(child.InvokeServer, function() return nil end)
							end
						end)
					end
				end
			end
		end
		pcall(scan, ReplicatedStorage)
		pcall(scan, ReplicatedFirst)
		table.insert(Bypass.conns, ReplicatedStorage.ChildAdded:Connect(function(child)
			if (child:IsA("RemoteEvent") or child:IsA("RemoteFunction")) and is_ac_name(child.Name) then
				if EX.hookfn then
					pcall(function()
						if child:IsA("RemoteEvent") then
							EX.hookfn(child.FireServer, function() end)
						else
							EX.hookfn(child.InvokeServer, function() return nil end)
						end
					end)
				end
			end
		end))
	end

	neutralize_ac_remotes()

	local function kill_ac_threads()
		local ok, gc = pcall(function() return getgc(true) end)
		if ok and type(gc) == "table" then
			for _, obj in ipairs(gc) do
				if type(obj) == "table" then
					for k, v in pairs(obj) do
						if type(k) == "string" then
							local lk = k:lower()
							if (lk:find("detect") or lk:find("ban") or lk:find("kick") or lk:find("report"))
								and type(v) == "function" then
								pcall(function() obj[k] = function() end end)
								Bypass.detections_blocked += 1
							end
						end
					end
				end
			end
		end
		local okc, conns = pcall(function() return getconnections(ScriptContext.Error) end)
		if okc and type(conns) == "table" then
			for _, c in ipairs(conns) do
				pcall(function() c:Disable() end)
			end
		end
	end

	local function sanitize_character(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			spoof_humanoid(hum)
			table.insert(Bypass.conns, hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if Bypass.enabled then
					local saved = Bypass.savedprops[hum]
					if saved then saved.WalkSpeed = hum.WalkSpeed end
				end
			end))
		end
	end

	if player.Character then sanitize_character(player.Character) end
	table.insert(Bypass.conns, player.CharacterAdded:Connect(sanitize_character))

	task.defer(kill_ac_threads)

	task.spawn(function()
		while Bypass.enabled do
			task.wait(5)
			kill_ac_threads()
		end
	end)

	ENV.__KAYSER_BYPASS = Bypass

	local State = {
		esp = false, fullbright = false, noclip = false, fly = false,
		infJump = false, antiVoid = false, voidY = -60, safeCF = nil,
		baseSpeed = 16, baseJump = 50, baseFov = 70, addSpeed = 0, addJump = 0,
		waypoints = {}, conns = {}, flyParts = nil, light = nil, killed = false,
		spectating = nil,
		baseSwim = 60,
		orbitEnabled = false, spinBotEnabled = false, camlockEnabled = false,
	}

	local Config = {
		Keys = {
			Fly           = Enum.KeyCode.F,
			Noclip        = Enum.KeyCode.N,
			Aimbot        = Enum.KeyCode.G,
			SilentAim     = Enum.KeyCode.I,
			Camlock       = Enum.KeyCode.C,
			RapidFire     = Enum.KeyCode.U,
			ESP           = Enum.KeyCode.H,
			WalkFling     = Enum.KeyCode.T,
			ToggleMenu    = Enum.KeyCode.RightShift,
			Unload        = Enum.KeyCode.End,
			Home          = Enum.KeyCode.Home,
		},
		Fly = { Enabled = false, Speed = 60, Step = 10, Mode = "Camera" },
		Walk = { Enabled = false, Speed = 16, Step = 4 },
		Jump = { Enabled = false, Power = 50, Step = 10 },
		Swim = { Enabled = false, Speed = 60, Step = 10 },
		Orbit = { Enabled = false, Speed = 3, Radius = 10, Height = 2, Target = "" },
		SpinBot = { Enabled = false, Speed = 20 },
		Camlock = {
			Enabled = false, TargetPart = "Head", Smoothness = 1,
			Prediction = true, PredictionFactor = 0.12, WallCheck = false,
			TeamCheck = true, Sticky = true, FOV = 100000, MaxDistance = math.huge,
		},
		Aimbot = {
			Enabled = false, FOV = 260, Smoothness = .35, TargetPart = "Head",
			TeamCheck = true, WallCheck = true, Prediction = false, PredictionFactor = .12,
			MaxDistance = 1200, HoldToAim = false, AimMode = "Camera",
		},
		RapidFire = { Enabled = false, Rate = 30, HoldOnly = true, MaxPerFrame = 60, ForceEnabled = true, Deactivate = true },
		FastMod = {
			Enabled = false, Delay = 0.01, RateValue = 100, ForceToolEnabled = true,
			PatchBackpack = true, RefreshInterval = 0.25, AutoFire = false, AutoFireDelay = 0.05,
			PatchModules = true, Watch = true, AnimBoost = false, AnimSpeed = 2,
			DelayKeywords = { "cooldown", "delay", "reload", "firerate", "firedelay", "shootdelay", "attackdelay", "interval", "recoiltime", "debounce", "equiptime", "windup", "chargetime" },
			RateKeywords = { "rpm", "persecond", "attackspeed", "firespeed", "rateoffire", "shotspersecond" },
		},
		NextbotSpam = { Active = false, Speed = 20 },
		Kills = { Enabled = true, Window = 6 },
		View = { Enabled = false, Target = "" },
		FOVCircle = { Show = true, Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5 },
		AimTracer = { Enabled = false, Color = Color3.fromRGB(255, 80, 80), Thickness = 1, FromCenter = false, FadeEnd = true, ShowDot = true },
		Wallbang = { Enabled = false },
		WalkFling = {
			Enabled = false, Power = 5e4, Spin = false, TriggerRange = 10,
			OnlyNearPlayers = true, HeavyBody = false, SafeReturn = true, SafeReturnDistance = 50,
		},
		CarFling = { Enabled = false, Power = 5e4, Speed = 100 },
	}

	local Widgets = { toggles = {}, sliders = {} }
	local ESP, Hitboxes = {}, {}
	local Features = {}
	local spawnedNextbots = {}
	local nextbotSpeed = 20

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
		local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
		if pg then table.insert(hosts, pg) end
		table.insert(hosts, function() return try(gethui) end)
		table.insert(hosts, function() return game:GetService("CoreGui") end)
		for _, h in ipairs(hosts) do
			local host = type(h) == "function" and try(h) or h
			if host then
				local ok = pcall(function() o.Parent = host end)
				if ok then return true end
			end
		end
		task.delay(2, function() if not o.Parent then attach(o) end end)
		return false
	end
	attach(Gui)

	local win = new("Frame", {
		Size = UDim2.fromOffset(660, 430), Position = UDim2.fromScale(.5, .5),
		AnchorPoint = Vector2.new(.5, .5), BackgroundColor3 = C.bg,
		BorderSizePixel = 0, Parent = Gui,
	})
	local menuFrameRef = win
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
	local function getChar()
		local ch = player.Character
		return ch, ch and ch:FindFirstChildOfClass("Humanoid"), ch and ch:FindFirstChild("HumanoidRootPart")
	end

	local rawRaycast = workspace.Raycast
	local mouse = try(function() return player:GetMouse() end)

	local function applyMovement()
		local _, hum = getChar()
		if not hum then return end
		hum.WalkSpeed = math.max(1, State.baseSpeed + State.addSpeed)
		hum.UseJumpPower = true
		hum.JumpPower = math.max(1, State.baseJump + State.addJump)
	end

	--==========================================================
	-- FastMod (telavivpanel)
	--==========================================================
	local fastPatchAll, restoreFastMod
	do
		local originals = setmetatable({}, { __mode = "k" })
		local watchConns = setmetatable({}, { __mode = "k" })
		local patchedModules = setmetatable({}, { __mode = "k" })
		local hookedTools = setmetatable({}, { __mode = "k" })

		local function nameMatches(name, list)
			local n = name:lower()
			for _, kw in ipairs(list) do
				if n:find(kw, 1, true) then return true end
			end
			return false
		end

		local function remember(obj, key, value)
			local t = originals[obj]
			if not t then t = {}; originals[obj] = t end
			if t[key] == nil then t[key] = value end
		end

		local function patchedNumber(name, val)
			local fm = Config.FastMod
			if nameMatches(name, fm.DelayKeywords) then
				if val > fm.Delay then return fm.Delay end
			elseif nameMatches(name, fm.RateKeywords) then
				if val < fm.RateValue then return fm.RateValue end
			end
			return nil
		end

		local function addConn(inst, key, conn)
			local c = watchConns[inst]
			if not c then c = {}; watchConns[inst] = c end
			c[key] = conn
		end

		local function hasConn(inst, key)
			local c = watchConns[inst]
			return c and c[key] ~= nil
		end

		local function patchValue(inst)
			local fm = Config.FastMod
			local nv = patchedNumber(inst.Name, inst.Value)
			if nv ~= nil then
				remember(inst, "Value", inst.Value)
				inst.Value = nv
			end
			if fm.Watch and not hasConn(inst, "Value")
				and (nameMatches(inst.Name, fm.DelayKeywords) or nameMatches(inst.Name, fm.RateKeywords)) then
				addConn(inst, "Value", inst:GetPropertyChangedSignal("Value"):Connect(function()
					if not Config.FastMod.Enabled then return end
					local fixed = patchedNumber(inst.Name, inst.Value)
					if fixed ~= nil then
						remember(inst, "Value", inst.Value)
						inst.Value = fixed
					end
				end))
			end
		end

		local function patchAttributes(inst)
			local fm = Config.FastMod
			for name, val in pairs(inst:GetAttributes()) do
				if type(val) == "number" then
					local nv = patchedNumber(name, val)
					if nv ~= nil then
						remember(inst, "@" .. name, val)
						inst:SetAttribute(name, nv)
					end
					local key = "@" .. name
					if fm.Watch and not hasConn(inst, key)
						and (nameMatches(name, fm.DelayKeywords) or nameMatches(name, fm.RateKeywords)) then
						addConn(inst, key, inst:GetAttributeChangedSignal(name):Connect(function()
							if not Config.FastMod.Enabled then return end
							local cur = inst:GetAttribute(name)
							if type(cur) == "number" then
								local fixed = patchedNumber(name, cur)
								if fixed ~= nil then
									remember(inst, key, cur)
									inst:SetAttribute(name, fixed)
								end
							end
						end))
					end
				end
			end
		end

		local function patchTable(tbl, depth)
			if depth > 3 then return end
			for k, v in pairs(tbl) do
				if type(k) == "string" then
					if type(v) == "number" then
						local nv = patchedNumber(k, v)
						if nv ~= nil then
							remember(tbl, k, v)
							pcall(function() tbl[k] = nv end)
						end
					elseif type(v) == "table" then
						patchTable(v, depth + 1)
					end
				end
			end
		end

		local function patchModule(mod)
			local cached = patchedModules[mod]
			if cached == false then return end
			if cached == nil then
				local ok, res = pcall(require, mod)
				if not ok or type(res) ~= "table" then
					patchedModules[mod] = false
					return
				end
				patchedModules[mod] = res
				cached = res
			end
			patchTable(cached, 0)
		end

		local function patchInstance(inst)
			if inst:IsA("NumberValue") or inst:IsA("IntValue") then
				patchValue(inst)
			end
			patchAttributes(inst)
			if Config.FastMod.PatchModules and inst:IsA("ModuleScript") then
				patchModule(inst)
			end
		end

		local function patchTool(tool)
			patchInstance(tool)
			for _, d in ipairs(tool:GetDescendants()) do
				patchInstance(d)
			end
		end

		local function hookTool(tool)
			if hookedTools[tool] then return end
			hookedTools[tool] = true
			tool.DescendantAdded:Connect(function(d)
				if Config.FastMod.Enabled then patchInstance(d) end
			end)
		end

		function fastPatchAll()
			local fm = Config.FastMod
			local char = player.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			if tool then hookTool(tool); patchTool(tool) end
			if fm.PatchBackpack then
				local bp = player:FindFirstChildOfClass("Backpack")
				if bp then
					for _, t in ipairs(bp:GetChildren()) do
						if t:IsA("Tool") then hookTool(t); patchTool(t) end
					end
				end
			end
		end

		function restoreFastMod()
			for _, conns in pairs(watchConns) do
				for _, c in pairs(conns) do c:Disconnect() end
			end
			table.clear(watchConns)
			for obj, saved in pairs(originals) do
				if type(obj) == "table" then
					for key, val in pairs(saved) do
						pcall(function() obj[key] = val end)
					end
				elseif obj.Parent then
					for key, val in pairs(saved) do
						if key == "Value" then
							obj.Value = val
						elseif key:sub(1, 1) == "@" then
							obj:SetAttribute(key:sub(2), val)
						end
					end
				end
			end
			table.clear(originals)
		end

		local fastAccum = 0
		RunService.Heartbeat:Connect(function(dt)
			local fm = Config.FastMod
			if not fm.Enabled then return end
			local char = player.Character
			if not char then return end
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and fm.ForceToolEnabled and not tool.Enabled then
				tool.Enabled = true
			end
			fastAccum += dt
			if fastAccum >= fm.RefreshInterval then
				fastAccum = 0
				fastPatchAll()
			end
		end)

		local autoTimer = 0
		RunService.Heartbeat:Connect(function(dt)
			local fm = Config.FastMod
			if not (fm.Enabled and fm.AutoFire) or Config.RapidFire.Enabled then autoTimer = 0; return end
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then autoTimer = 0; return end
			if UserInputService:GetFocusedTextBox() then return end
			local char = player.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			if not tool then return end
			autoTimer += dt
			if autoTimer >= fm.AutoFireDelay then
				autoTimer = 0
				tool:Activate()
			end
		end)
	end

	--==========================================================
	-- Nextbot spam (telavivpanel)
	--==========================================================
	local function spawnLocalNextbot()
		local _, _, root = getChar()
		if not root then return end
		local nextbot = Instance.new("Part")
		nextbot.Name = "KayserNextbot"
		nextbot.Size = Vector3.new(4, 5, 2)
		local angle = math.random() * math.pi * 2
		local distance = math.random(15, 30)
		nextbot.Position = root.Position + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
		nextbot.CanCollide = false
		nextbot.Anchored = false
		nextbot.BrickColor = BrickColor.random()
		nextbot.Material = Enum.Material.Neon
		nextbot.Parent = workspace
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local _, _, currentRoot = getChar()
			if not nextbot.Parent or not currentRoot then
				nextbot:Destroy()
				connection:Disconnect()
				return
			end
			local direction = (currentRoot.Position - nextbot.Position)
			if direction.Magnitude > 2 then
				nextbot.AssemblyLinearVelocity = direction.Unit * Config.NextbotSpam.Speed
				nextbot.CFrame = CFrame.lookAt(nextbot.Position, currentRoot.Position)
			else
				nextbot:Destroy()
				connection:Disconnect()
			end
		end)
		table.insert(spawnedNextbots, nextbot)
		nextbot.Destroying:Connect(function()
			local i = table.find(spawnedNextbots, nextbot)
			if i then table.remove(spawnedNextbots, i) end
		end)
	end

	--==========================================================
	-- Combat engine (KAYSER core, enrichi avec Camlock/Aimbot cursor)
	--==========================================================
	local Aim = {
		on = false, silent = false, wallbang = false, hitbox = false, autoFire = false,
		fov = 260, silentFov = 260, smooth = .35, maxDist = 1200, ignoreTeam = true, wallCheck = true,
		target = nil, headPos = nil,
		silentOffsetX = 0, silentOffsetY = 0, showFov = true, hitChance = 100,
		fovColorR = 124, fovColorG = 152, fovColorB = 255,
		silentColorR = 255, silentColorG = 180, silentColorB = 60,
		mode = "Camera",
	}

	local Rapid = { on = false, rate = 0.01, acc = 0, aimFire = false }
	local SkidFlingAll = { on = false }

	local flingVel = Vector3.zero
	local flingAng = Vector3.zero
	local flingActive = false
	local flingSavedProps = {}
	local flingMassOn = false
	local flingChar = nil
	local lastSafeCF = nil
	local flingSeeded = false

	local function setFlingMass(on)
		if on then
			local char = player.Character
			if flingChar ~= char then
				table.clear(flingSavedProps)
				flingChar = char
			end
			if char then
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then
						if flingSavedProps[p] == nil then
							flingSavedProps[p] = p.CustomPhysicalProperties or false
						end
						p.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
					end
				end
			end
			flingMassOn = true
		else
			for p, saved in pairs(flingSavedProps) do
				if p.Parent then p.CustomPhysicalProperties = saved or nil end
			end
			table.clear(flingSavedProps)
			flingMassOn = false
		end
	end

	local function nearOtherPlayer(root, range)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - root.Position).Magnitude <= range then
					return true
				end
			end
		end
		return false
	end

	RunService.Heartbeat:Connect(function()
		local wf = Config.WalkFling
		local active = wf.Enabled and not Config.Fly.Enabled
		if not active then
			if flingMassOn then setFlingMass(false) end
			flingSeeded = false
			lastSafeCF = nil
			return
		end
		local char, _, root = getChar()
		if not root then return end
		if wf.HeavyBody and (not flingMassOn or flingChar ~= player.Character) then
			setFlingMass(true)
		end
		if wf.SafeReturn and lastSafeCF
			and (root.Position - lastSafeCF.Position).Magnitude > wf.SafeReturnDistance then
			char:PivotTo(lastSafeCF)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			flingSeeded = false
			return
		end
		if wf.OnlyNearPlayers and not nearOtherPlayer(root, wf.TriggerRange) then
			if wf.SafeReturn then lastSafeCF = root.CFrame end
			flingSeeded = false
			return
		end
		if not flingSeeded then
			local base = root.AssemblyLinearVelocity
			if Vector3.new(base.X, 0, base.Z).Magnitude < 1 then
				base = root.CFrame.LookVector * 16
			end
			flingVel = base * wf.Power + Vector3.new(0, wf.Power, 0)
			flingAng = wf.Spin and Vector3.new(0, wf.Power, 0) or Vector3.zero
			flingSeeded = true
		end
		flingActive = true
		root.AssemblyLinearVelocity = flingVel
		root.AssemblyAngularVelocity = flingAng
	end)

	RunService.Heartbeat:Connect(function()
		local cfCfg = Config.CarFling
		if not cfCfg.Enabled then return end
		local char = player.Character
		local seat = char and char:FindFirstChildOfClass("Humanoid") and char.Humanoid.SeatPart
		if not seat then
			for _, v in ipairs(workspace:GetDescendants()) do
				if v:IsA("VehicleSeat") and v.Occupant and v.Occupant.Parent == char then
					seat = v
					break
				end
			end
		end
		if seat and seat.Parent then
			local vehicleModel = seat.Parent
			if not vehicleModel:IsA("Model") then vehicleModel = vehicleModel.Parent end
			if vehicleModel and vehicleModel:IsA("Model") then
				for _, part in ipairs(vehicleModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity = part.CFrame.LookVector * cfCfg.Speed + Vector3.new(0, cfCfg.Power * 0.001, 0)
						part.AssemblyAngularVelocity = Vector3.new(0, cfCfg.Power * 0.001, 0)
					end
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not flingActive then return end
		local _, _, root = getChar()
		if root then
			root.AssemblyLinearVelocity = flingVel
			root.AssemblyAngularVelocity = flingAng
		end
	end)

	RunService.Stepped:Connect(function()
		if not flingActive then return end
		flingActive = false
		local _, _, root = getChar()
		if root then
			root.AssemblyLinearVelocity = flingVel + Vector3.new(0, 0.1, 0)
			root.AssemblyAngularVelocity = flingAng
		end
	end)

	local Hooks = { on = false, origIndex = nil }
	local fovCircleFrame    = nil
	local silentCircleFrame = nil

	local Whitelist = {}
	local function IsWhitelisted(p)
		local nameLower = p.Name:lower()
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

	local silentCache = { part = nil, pos = nil, plr = nil }
	local silentRoll, silentRollT = true, 0
	Hooks.silentConn = nil

	local function silentTick()
		if not (Aim.on and Aim.silent) then
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
			return
		end
		local now = os.clock()
		if now - silentRollT > 0.1 then
			silentRollT = now
			silentRoll = math.random(1, 100) <= Aim.hitChance
		end
		if not silentRoll then
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
			return
		end
		local ok, t, h = pcall(acquire)
		if ok and t and h then
			local ch = t.Character
			local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
			silentCache.part = part
			silentCache.pos  = h
			silentCache.plr  = t
		else
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
		end
	end

	_G.DevTools = _G.DevTools or {}
	function _G.DevTools.GetAimPosition(defaultPos)
		return silentCache.pos or defaultPos
	end
	function _G.DevTools.GetAimTarget()
		return silentCache.part
	end
	function _G.DevTools.GetAimDirection(origin, defaultDir)
		local p = silentCache.pos
		if p and (p - origin).Magnitude > 0.01 then return (p - origin).Unit end
		return defaultDir
	end

	local function installHooks()
		if Hooks.on or not EX.hook then return false end
		if not Hooks.silentConn then
			Hooks.silentConn = RunService.RenderStepped:Connect(silentTick)
		end
		local okIndex, origIndex = pcall(function()
			return EX.hook(game, "__index", function(self, key)
				if Aim.silent and silentCache.pos and not checkcaller() then
					if self == mouse then
						if key == "Hit"    then return CFrame.new(silentCache.pos) end
						if key == "Target" then return silentCache.part end
						if key == "UnitRay" then
							local o = CAM.CFrame.Position
							return Ray.new(o, (silentCache.pos - o).Unit * 2000)
						end
					end
				end
				if Aim.wallbang and self == workspace and key == "Raycast" then
					return wallbangRaycast
				end
				return origIndex(self, key)
			end)
		end)
		if okIndex then
			Hooks.on = true
			Hooks.origIndex = origIndex
			return true
		end
		return false
	end

	local function removeHooks()
		if not Hooks.on or not EX.hook then return end
		if Hooks.origIndex then
			pcall(EX.hook, game, "__index", Hooks.origIndex)
		end
		if Hooks.silentConn then
			Hooks.silentConn:Disconnect()
			Hooks.silentConn = nil
		end
		silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
		Hooks.on = false
	end

	local UIS = UserInputService
	local camera = CAM
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local menuFrameRef2 = nil

	local function mouseOverMenu()
		if not (menuFrameRef2 and menuFrameRef2.Visible) then return false end
		local m = UIS:GetMouseLocation()
		local p, sz = menuFrameRef2.AbsolutePosition, menuFrameRef2.AbsoluteSize
		return m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y
	end

	local function isVisible(part)
		if Config.Wallbang and Config.Wallbang.Enabled then return true end
		local origin = camera.CFrame.Position
		local dir = part.Position - origin
		local ignore = { player.Character }
		for _ = 1, 8 do
			rayParams.FilterDescendantsInstances = ignore
			local res = workspace:Raycast(origin, dir, rayParams)
			if not res then return true end
			local inst = res.Instance
			if inst:IsDescendantOf(part.Parent) then return true end
			if inst.Transparency >= 0.95 or not inst.CanCollide then
				table.insert(ignore, inst)
			else
				return false
			end
		end
		return false
	end

	local function aimCenter(useMouse)
		if Aim.silent then
			local vp = camera.ViewportSize
			return Vector2.new(vp.X * .5 + Aim.silentOffsetX, vp.Y * .5 + Aim.silentOffsetY)
		end
		if useMouse and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			return UIS:GetMouseLocation()
		end
		return camera.ViewportSize / 2
	end

	local function resolveAimPart(char, partName)
		partName = partName or "Head"
		local part
		if partName == "Torso" or partName == "UpperTorso" then
			part = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		else
			part = char:FindFirstChild(partName)
		end
		return part or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	end

	local function getClosestTarget(s, partName, useMouse)
		local center = aimCenter(useMouse)
		local camPos = camera.CFrame.Position
		local bestScreen, bestWorld, bestPart, bestPlr, bestDist = nil, nil, nil, nil, s.FOV
		for _, other in ipairs(Players:GetPlayers()) do
			local char = other.Character
			if other == player or not char then continue end
			if s.TeamCheck and other.Team ~= nil and other.Team == player.Team then continue end
			local hum = char:FindFirstChildOfClass("Humanoid")
			local part = resolveAimPart(char, partName)
			if not hum or not part or hum.Health <= 0 then continue end
			if (part.Position - camPos).Magnitude > (s.MaxDistance or s.maxDist or 1200) then continue end
			local pos3D = part.Position
			if s.Prediction then
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then pos3D = pos3D + root.AssemblyLinearVelocity * (s.PredictionFactor or 0.12) end
			end
			local sp, onScrn = camera:WorldToViewportPoint(pos3D)
			if not onScrn or sp.Z <= 0 then continue end
			local v = Vector2.new(sp.X, sp.Y)
			local d = (v - center).Magnitude
			if d < bestDist and (not s.WallCheck or isVisible(part)) then
				bestScreen, bestWorld, bestPart, bestPlr, bestDist = v, pos3D, part, other, d
			end
		end
		return bestScreen, bestWorld, bestPart, bestPlr
	end

	local function acquire()
		local aimCfg = {
			FOV = Aim.silent and Aim.silentFov or Aim.fov,
			TeamCheck = Aim.ignoreTeam, MaxDistance = Aim.maxDist,
			Prediction = false, WallCheck = Aim.wallCheck,
		}
		local _, world, _, plr = getClosestTarget(aimCfg, "Head", false)
		return plr, world
	end

	local function triggerRapidFire()
		local ch = player.Character
		if not ch then return end
		local tool = ch:FindFirstChildOfClass("Tool")
		if tool then
			pcall(function()
				tool:Activate()
				for _, descendant in ipairs(tool:GetDescendants()) do
					if descendant:IsA("RemoteEvent") then
						pcall(function() descendant:FireServer() end)
					end
				end
			end)
		end
		if EX.input then pcall(EX.input) end
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end)
	end

	local function updateCircle()
		local vp = CAM.ViewportSize
		local activeCenter = Vector2.new(vp.X * .5 + Aim.silentOffsetX, vp.Y * .5 + Aim.silentOffsetY)
		local fc = Config.FOVCircle
		if fovCircleFrame then
			local showNormal = Aim.on and Aim.showFov and not Aim.silent and fc.Show
			fovCircleFrame.Visible = showNormal
			if showNormal then
				local r = Aim.fov
				local center = Vector2.new(vp.X * .5, vp.Y * .5)
				fovCircleFrame.Position = UDim2.fromOffset(center.X, center.Y)
				fovCircleFrame.Size = UDim2.fromOffset(r * 2, r * 2)
				local so = fovCircleFrame:FindFirstChildOfClass("UIStroke")
				if so then
					so.Color = Aim.target and C.on or Color3.fromRGB(Aim.fovColorR, Aim.fovColorG, Aim.fovColorB)
					so.Thickness = fc.Thickness
				end
			end
		end
		if silentCircleFrame then
			local showSilent = Aim.showFov and Aim.silent and fc.Show
			silentCircleFrame.Visible = showSilent
			if showSilent then
				local r = Aim.silentFov
				silentCircleFrame.Position = UDim2.fromOffset(activeCenter.X, activeCenter.Y)
				silentCircleFrame.Size = UDim2.fromOffset(r * 2, r * 2)
				local so = silentCircleFrame:FindFirstChildOfClass("UIStroke")
				if so then
					so.Color = Aim.target and C.on or Color3.fromRGB(Aim.silentColorR, Aim.silentColorG, Aim.silentColorB)
					so.Thickness = fc.Thickness
				end
			end
		end
	end

	local function ExecuteSkidFling(TargetPlayer)
		if not TargetPlayer or not TargetPlayer.Parent then return false end
		if IsPlayerSeated(TargetPlayer) then return false end
		local Character = player.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Humanoid and Humanoid.RootPart
		local TCharacter = TargetPlayer.Character
		local THumanoid = TCharacter and TCharacter:FindFirstChildOfClass("Humanoid")
		local TRootPart = THumanoid and THumanoid.RootPart
		local THead = TCharacter and TCharacter:FindFirstChild("Head")
		if not (Character and Humanoid and RootPart) then return false end
		local oldPos = RootPart.CFrame
		if THead then workspace.CurrentCamera.CameraSubject = THead end
		local function FPos(BasePart, Pos, Ang)
			if not BasePart or not BasePart.Parent or not RootPart then return end
			RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
			Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
			RootPart.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
			RootPart.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
		end
		local function SFBasePart(BasePart)
			local Time = tick()
			local Angle = 0
			repeat
				if RootPart and THumanoid then
					Angle = Angle + 100
					FPos(BasePart, CFrame.new(0, 1.5, 0), CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
					FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
				else break end
			until BasePart.AssemblyLinearVelocity.Magnitude > 500
				or BasePart.Parent ~= TargetPlayer.Character
				or tick() > Time + 1.5
		end
		local fpdh = workspace.FallenPartsDestroyHeight
		workspace.FallenPartsDestroyHeight = 0/0
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		if TRootPart then SFBasePart(TRootPart) elseif THead then SFBasePart(THead) end
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
		workspace.CurrentCamera.CameraSubject = Humanoid
		repeat
			if not RootPart then break end
			RootPart.CFrame = oldPos
			Character:SetPrimaryPartCFrame(oldPos)
			Humanoid:ChangeState("GettingUp")
			task.wait()
		until (RootPart.Position - oldPos.p).Magnitude < 25
		workspace.FallenPartsDestroyHeight = fpdh
		return true
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
			if Aim.target and Aim.headPos and not Aim.silent then
				local goal = CFrame.lookAt(CAM.CFrame.Position, Aim.headPos)
				CAM.CFrame = Aim.smooth <= 0 and goal or CAM.CFrame:Lerp(goal, math.clamp(1 - Aim.smooth, .04, 1))
			end
		end
		updateCircle()
		Rapid.aimFire = Aim.on and Aim.autoFire and Aim.target ~= nil
		if Rapid.on or Rapid.aimFire then
			Rapid.acc += dt
			if Rapid.acc >= Rapid.rate then
				Rapid.acc = 0
				task.spawn(triggerRapidFire)
			end
		end
		if State.spectating then
			local targetPlr = Players:FindFirstChild(State.spectating)
			local ch = targetPlr and targetPlr.Character
			local head = ch and ch:FindFirstChild("Head")
			if head then CAM.CameraSubject = head
			else CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid") end
		end
	end

	local function ensureCombat()
		local wantCombat = Aim.on or Aim.silent or Aim.wallbang or Aim.hitbox
			or Rapid.on or SkidFlingAll.on or Config.WalkFling.Enabled
			or Config.CarFling.Enabled or State.spectating
			or Config.Camlock.Enabled or Config.Orbit.Enabled or Config.SpinBot.Enabled
		if wantCombat then
			if not State.conns.combat then
				State.conns.combat = hook(RunService.RenderStepped, combatTick)
			end
		else
			if State.conns.combat then
				State.conns.combat:Disconnect()
				State.conns.combat = nil
			end
			Aim.target, Aim.headPos = nil, nil
			updateCircle()
		end
		if Aim.on or Aim.silent or Aim.wallbang then
			installHooks()
		else
			removeHooks()
		end
	end

	--==========================================================
	-- Camlock (telavivpanel)
	--==========================================================
	local camTarget = nil
	local function camValid(plr, c)
		local char = plr and plr.Parent and plr.Character
		if not char then return nil end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local part = resolveAimPart(char, c.TargetPart)
		if not hum or not part or hum.Health <= 0 then return nil end
		return part, char
	end
	local function camPick(c)
		local viewport = camera.ViewportSize
		local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local best, bestDist = nil, c.FOV
		for _, other in ipairs(Players:GetPlayers()) do
			if other == player then continue end
			if c.TeamCheck and other.Team ~= nil and other.Team == player.Team then continue end
			local part = camValid(other, c)
			if not part then continue end
			if (part.Position - camera.CFrame.Position).Magnitude > c.MaxDistance then continue end
			if c.WallCheck and not isVisible(part) then continue end
			local sp = camera:WorldToViewportPoint(part.Position)
			local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
			if d < bestDist then best, bestDist = other, d end
		end
		return best
	end
	pcall(function() RunService:UnbindFromRenderStep("KayserCamlock") end)
	RunService:BindToRenderStep("KayserCamlock", Enum.RenderPriority.Camera.Value + 2, function()
		local c = Config.Camlock
		if not c.Enabled then camTarget = nil return end
		if not (c.Sticky and camTarget and camValid(camTarget, c)) then
			camTarget = camPick(c)
		end
		if not camTarget then return end
		local part, char = camValid(camTarget, c)
		if not part then return end
		local pos = part.Position
		if c.Prediction then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then pos = pos + root.AssemblyLinearVelocity * c.PredictionFactor end
		end
		local camPos = camera.CFrame.Position
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPos, pos), math.clamp(c.Smoothness, 0.01, 1))
	end)

	--==========================================================
	-- Orbit (telavivpanel)
	--==========================================================
	do
		local angle, target, nextPick = 0, nil, 0
		local function valid(p)
			local c = p and p.Parent and p.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			return h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
		end
		RunService.Heartbeat:Connect(function(dt)
			local o = Config.Orbit
			if not o.Enabled then target = nil return end
			local _, hum, root = getChar()
			if not (hum and root and hum.Health > 0) then return end
			if o.Target ~= "" then
				local q, found = o.Target:lower(), nil
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and (p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
						found = p
						break
					end
				end
				target = found
			elseif not valid(target) or os.clock() > nextPick then
				nextPick = os.clock() + 1
				local best, bd = nil, math.huge
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and valid(p) then
						local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
						if d < bd then best, bd = p, d end
					end
				end
				target = best
			end
			if not valid(target) then return end
			local tr = target.Character.HumanoidRootPart
			angle = (angle + o.Speed * dt) % (math.pi * 2)
			local pos = tr.Position + Vector3.new(math.cos(angle) * o.Radius, o.Height, math.sin(angle) * o.Radius)
			hum.AutoRotate = false
			root.CFrame = CFrame.lookAt(pos, tr.Position)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	--==========================================================
	-- SpinBot (telavivpanel)
	--==========================================================
	do
		local spinning = false
		RunService.Heartbeat:Connect(function(dt)
			local _, hum, root = getChar()
			local on = Config.SpinBot.Enabled and not Config.Fly.Enabled and not Config.Orbit.Enabled
				and hum and root and hum.Health > 0
			if not on then
				if spinning then
					spinning = false
					if hum then hum.AutoRotate = true end
				end
				return
			end
			spinning = true
			hum.AutoRotate = false
			local rot = math.rad(360 * math.max(Config.SpinBot.Speed, 0)) * dt
			root.CFrame = root.CFrame * CFrame.Angles(0, rot, 0)
		end)
	end

	--==========================================================
	-- Swim / Jump / Walk state (telavivpanel)
	--==========================================================
	local terrain = workspace.Terrain
	local waterT, waterCache = 0, false
	local function inWater(root, hum)
		if hum:GetState() == Enum.HumanoidStateType.Swimming then return true end
		local now = os.clock()
		if now - waterT < 0.1 then return waterCache end
		waterT = now
		waterCache = false
		local pos = root.Position
		local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
		local ok, materials, occupancy = pcall(function() return terrain:ReadVoxels(region, 4) end)
		if ok and materials then
			local size = materials.Size
			for x = 1, size.X do
				for y = 1, size.Y do
					for z = 1, size.Z do
						if materials[x][y][z] == Enum.Material.Water and occupancy[x][y][z] > 0.5 then
							waterCache = true
						end
					end
				end
			end
		end
		return waterCache
	end

	local origSwim = nil
	RunService.RenderStepped:Connect(function()
		local _, hum, root = getChar()
		if not hum then return end
		local swim = Config.Swim
		local swimming = swim.Enabled and not Config.Fly.Enabled and inWater(root, hum)
		if swimming then
			if origSwim == nil then origSwim = hum.WalkSpeed end
			hum.WalkSpeed = swim.Speed
			if not UIS:GetFocusedTextBox() then
				local cf = camera.CFrame
				local dir = Vector3.zero
				if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
				if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
				if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
				if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
				if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
				if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
				if dir.Magnitude > 0 then
					root.AssemblyLinearVelocity = dir.Unit * swim.Speed
				end
			end
		elseif origSwim ~= nil then
			hum.WalkSpeed = origSwim
			origSwim = nil
		end
	end)

	--==========================================================
	-- Features (KAYSER + telavivpanel)
	--==========================================================
	local function dropHitbox(p)
		local hb = Hitboxes[p]
		if hb then pcall(function() hb:Destroy() end) end
		Hitboxes[p] = nil
	end

	local function makeHitbox(p)
		if Hitboxes[p] or p == player then return end
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
			State.conns.hitRefresh = hook(RunService.Heartbeat, function()
				for _, p in ipairs(Players:GetPlayers()) do makeHitbox(p) end
			end)
		elseif not on and State.conns.hitRefresh then
			State.conns.hitRefresh:Disconnect()
			State.conns.hitRefresh = nil
		end
		ensureCombat()
		notify("hitbox " .. (on and "on" or "off"))
	end

	function Features.esp(on)
		State.esp = on
		local function build(p)
			if p == player or ESP[p] then return end
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
			State.conns.espRefresh = hook(RunService.Heartbeat, function()
				local _, _, root = getChar()
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
				local ch = player.Character
				if not ch then return end
				for _, p in ipairs(ch:GetDescendants()) do
					if p:IsA("BasePart") then p.CanCollide = false end
				end
			end)
		end
	end

	function Features.fly(on)
		State.fly = on
		Config.Fly.Enabled = on
		local _, _, hrp = getChar()
		if on then
			if not hrp then
				State.fly = false
				Config.Fly.Enabled = false
				return notify("no character")
			end
			State.flyParts = {
				new("BodyVelocity", { Name = "KAYSER_V", MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = hrp }),
				new("BodyGyro", { Name = "KAYSER_G", MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2000, D = 60, Parent = hrp }),
			}
			State.conns.fly = hook(RunService.RenderStepped, function()
				local _, _, root = getChar()
				if not root or not State.flyParts or not State.flyParts[1].Parent then return end
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
				local _, hum = getChar()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		end
	end

	function Features.antiVoid(on)
		State.antiVoid = on
		if State.conns.void then State.conns.void:Disconnect() State.conns.void = nil end
		if on then
			State.conns.void = hook(RunService.Heartbeat, function()
				local ch, _, root = getChar()
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

	function Features.spectatePlayer(name)
		if name == "" or name == State.spectating then
			State.spectating = nil
			CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
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
		local _, _, hrp = getChar()
		if not hrp or name == "" then return notify("invalid waypoint") end
		State.waypoints[name] = hrp.CFrame
		persistWaypoints()
		notify("saved " .. name)
	end
	local function getChar()
		local ch = player.Character
		return ch, ch and ch:FindFirstChildOfClass("Humanoid"), ch and ch:FindFirstChild("HumanoidRootPart")
	end

	local rawRaycast = workspace.Raycast
	local mouse = try(function() return player:GetMouse() end)

	local function applyMovement()
		local _, hum = getChar()
		if not hum then return end
		hum.WalkSpeed = math.max(1, State.baseSpeed + State.addSpeed)
		hum.UseJumpPower = true
		hum.JumpPower = math.max(1, State.baseJump + State.addJump)
	end

	--==========================================================
	-- FastMod (telavivpanel)
	--==========================================================
	local fastPatchAll, restoreFastMod
	do
		local originals = setmetatable({}, { __mode = "k" })
		local watchConns = setmetatable({}, { __mode = "k" })
		local patchedModules = setmetatable({}, { __mode = "k" })
		local hookedTools = setmetatable({}, { __mode = "k" })

		local function nameMatches(name, list)
			local n = name:lower()
			for _, kw in ipairs(list) do
				if n:find(kw, 1, true) then return true end
			end
			return false
		end

		local function remember(obj, key, value)
			local t = originals[obj]
			if not t then t = {}; originals[obj] = t end
			if t[key] == nil then t[key] = value end
		end

		local function patchedNumber(name, val)
			local fm = Config.FastMod
			if nameMatches(name, fm.DelayKeywords) then
				if val > fm.Delay then return fm.Delay end
			elseif nameMatches(name, fm.RateKeywords) then
				if val < fm.RateValue then return fm.RateValue end
			end
			return nil
		end

		local function addConn(inst, key, conn)
			local c = watchConns[inst]
			if not c then c = {}; watchConns[inst] = c end
			c[key] = conn
		end

		local function hasConn(inst, key)
			local c = watchConns[inst]
			return c and c[key] ~= nil
		end

		local function patchValue(inst)
			local fm = Config.FastMod
			local nv = patchedNumber(inst.Name, inst.Value)
			if nv ~= nil then
				remember(inst, "Value", inst.Value)
				inst.Value = nv
			end
			if fm.Watch and not hasConn(inst, "Value")
				and (nameMatches(inst.Name, fm.DelayKeywords) or nameMatches(inst.Name, fm.RateKeywords)) then
				addConn(inst, "Value", inst:GetPropertyChangedSignal("Value"):Connect(function()
					if not Config.FastMod.Enabled then return end
					local fixed = patchedNumber(inst.Name, inst.Value)
					if fixed ~= nil then
						remember(inst, "Value", inst.Value)
						inst.Value = fixed
					end
				end))
			end
		end

		local function patchAttributes(inst)
			local fm = Config.FastMod
			for name, val in pairs(inst:GetAttributes()) do
				if type(val) == "number" then
					local nv = patchedNumber(name, val)
					if nv ~= nil then
						remember(inst, "@" .. name, val)
						inst:SetAttribute(name, nv)
					end
					local key = "@" .. name
					if fm.Watch and not hasConn(inst, key)
						and (nameMatches(name, fm.DelayKeywords) or nameMatches(name, fm.RateKeywords)) then
						addConn(inst, key, inst:GetAttributeChangedSignal(name):Connect(function()
							if not Config.FastMod.Enabled then return end
							local cur = inst:GetAttribute(name)
							if type(cur) == "number" then
								local fixed = patchedNumber(name, cur)
								if fixed ~= nil then
									remember(inst, key, cur)
									inst:SetAttribute(name, fixed)
								end
							end
						end))
					end
				end
			end
		end

		local function patchTable(tbl, depth)
			if depth > 3 then return end
			for k, v in pairs(tbl) do
				if type(k) == "string" then
					if type(v) == "number" then
						local nv = patchedNumber(k, v)
						if nv ~= nil then
							remember(tbl, k, v)
							pcall(function() tbl[k] = nv end)
						end
					elseif type(v) == "table" then
						patchTable(v, depth + 1)
					end
				end
			end
		end

		local function patchModule(mod)
			local cached = patchedModules[mod]
			if cached == false then return end
			if cached == nil then
				local ok, res = pcall(require, mod)
				if not ok or type(res) ~= "table" then
					patchedModules[mod] = false
					return
				end
				patchedModules[mod] = res
				cached = res
			end
			patchTable(cached, 0)
		end

		local function patchInstance(inst)
			if inst:IsA("NumberValue") or inst:IsA("IntValue") then
				patchValue(inst)
			end
			patchAttributes(inst)
			if Config.FastMod.PatchModules and inst:IsA("ModuleScript") then
				patchModule(inst)
			end
		end

		local function patchTool(tool)
			patchInstance(tool)
			for _, d in ipairs(tool:GetDescendants()) do
				patchInstance(d)
			end
		end

		local function hookTool(tool)
			if hookedTools[tool] then return end
			hookedTools[tool] = true
			tool.DescendantAdded:Connect(function(d)
				if Config.FastMod.Enabled then patchInstance(d) end
			end)
		end

		function fastPatchAll()
			local fm = Config.FastMod
			local char = player.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			if tool then hookTool(tool); patchTool(tool) end
			if fm.PatchBackpack then
				local bp = player:FindFirstChildOfClass("Backpack")
				if bp then
					for _, t in ipairs(bp:GetChildren()) do
						if t:IsA("Tool") then hookTool(t); patchTool(t) end
					end
				end
			end
		end

		function restoreFastMod()
			for _, conns in pairs(watchConns) do
				for _, c in pairs(conns) do c:Disconnect() end
			end
			table.clear(watchConns)
			for obj, saved in pairs(originals) do
				if type(obj) == "table" then
					for key, val in pairs(saved) do
						pcall(function() obj[key] = val end)
					end
				elseif obj.Parent then
					for key, val in pairs(saved) do
						if key == "Value" then
							obj.Value = val
						elseif key:sub(1, 1) == "@" then
							obj:SetAttribute(key:sub(2), val)
						end
					end
				end
			end
			table.clear(originals)
		end

		local fastAccum = 0
		RunService.Heartbeat:Connect(function(dt)
			local fm = Config.FastMod
			if not fm.Enabled then return end
			local char = player.Character
			if not char then return end
			local tool = char:FindFirstChildOfClass("Tool")
			if tool and fm.ForceToolEnabled and not tool.Enabled then
				tool.Enabled = true
			end
			fastAccum += dt
			if fastAccum >= fm.RefreshInterval then
				fastAccum = 0
				fastPatchAll()
			end
		end)

		local autoTimer = 0
		RunService.Heartbeat:Connect(function(dt)
			local fm = Config.FastMod
			if not (fm.Enabled and fm.AutoFire) or Config.RapidFire.Enabled then autoTimer = 0; return end
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then autoTimer = 0; return end
			if UserInputService:GetFocusedTextBox() then return end
			local char = player.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			if not tool then return end
			autoTimer += dt
			if autoTimer >= fm.AutoFireDelay then
				autoTimer = 0
				tool:Activate()
			end
		end)
	end

	--==========================================================
	-- Nextbot spam (telavivpanel)
	--==========================================================
	local function spawnLocalNextbot()
		local _, _, root = getChar()
		if not root then return end
		local nextbot = Instance.new("Part")
		nextbot.Name = "KayserNextbot"
		nextbot.Size = Vector3.new(4, 5, 2)
		local angle = math.random() * math.pi * 2
		local distance = math.random(15, 30)
		nextbot.Position = root.Position + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
		nextbot.CanCollide = false
		nextbot.Anchored = false
		nextbot.BrickColor = BrickColor.random()
		nextbot.Material = Enum.Material.Neon
		nextbot.Parent = workspace
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local _, _, currentRoot = getChar()
			if not nextbot.Parent or not currentRoot then
				nextbot:Destroy()
				connection:Disconnect()
				return
			end
			local direction = (currentRoot.Position - nextbot.Position)
			if direction.Magnitude > 2 then
				nextbot.AssemblyLinearVelocity = direction.Unit * Config.NextbotSpam.Speed
				nextbot.CFrame = CFrame.lookAt(nextbot.Position, currentRoot.Position)
			else
				nextbot:Destroy()
				connection:Disconnect()
			end
		end)
		table.insert(spawnedNextbots, nextbot)
		nextbot.Destroying:Connect(function()
			local i = table.find(spawnedNextbots, nextbot)
			if i then table.remove(spawnedNextbots, i) end
		end)
	end

	--==========================================================
	-- Combat engine (KAYSER core, enrichi avec Camlock/Aimbot cursor)
	--==========================================================
	local Aim = {
		on = false, silent = false, wallbang = false, hitbox = false, autoFire = false,
		fov = 260, silentFov = 260, smooth = .35, maxDist = 1200, ignoreTeam = true, wallCheck = true,
		target = nil, headPos = nil,
		silentOffsetX = 0, silentOffsetY = 0, showFov = true, hitChance = 100,
		fovColorR = 124, fovColorG = 152, fovColorB = 255,
		silentColorR = 255, silentColorG = 180, silentColorB = 60,
		mode = "Camera",
	}

	local Rapid = { on = false, rate = 0.01, acc = 0, aimFire = false }
	local SkidFlingAll = { on = false }

	local flingVel = Vector3.zero
	local flingAng = Vector3.zero
	local flingActive = false
	local flingSavedProps = {}
	local flingMassOn = false
	local flingChar = nil
	local lastSafeCF = nil
	local flingSeeded = false

	local function setFlingMass(on)
		if on then
			local char = player.Character
			if flingChar ~= char then
				table.clear(flingSavedProps)
				flingChar = char
			end
			if char then
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then
						if flingSavedProps[p] == nil then
							flingSavedProps[p] = p.CustomPhysicalProperties or false
						end
						p.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5, 1, 1)
					end
				end
			end
			flingMassOn = true
		else
			for p, saved in pairs(flingSavedProps) do
				if p.Parent then p.CustomPhysicalProperties = saved or nil end
			end
			table.clear(flingSavedProps)
			flingMassOn = false
		end
	end

	local function nearOtherPlayer(root, range)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - root.Position).Magnitude <= range then
					return true
				end
			end
		end
		return false
	end

	RunService.Heartbeat:Connect(function()
		local wf = Config.WalkFling
		local active = wf.Enabled and not Config.Fly.Enabled
		if not active then
			if flingMassOn then setFlingMass(false) end
			flingSeeded = false
			lastSafeCF = nil
			return
		end
		local char, _, root = getChar()
		if not root then return end
		if wf.HeavyBody and (not flingMassOn or flingChar ~= player.Character) then
			setFlingMass(true)
		end
		if wf.SafeReturn and lastSafeCF
			and (root.Position - lastSafeCF.Position).Magnitude > wf.SafeReturnDistance then
			char:PivotTo(lastSafeCF)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			flingSeeded = false
			return
		end
		if wf.OnlyNearPlayers and not nearOtherPlayer(root, wf.TriggerRange) then
			if wf.SafeReturn then lastSafeCF = root.CFrame end
			flingSeeded = false
			return
		end
		if not flingSeeded then
			local base = root.AssemblyLinearVelocity
			if Vector3.new(base.X, 0, base.Z).Magnitude < 1 then
				base = root.CFrame.LookVector * 16
			end
			flingVel = base * wf.Power + Vector3.new(0, wf.Power, 0)
			flingAng = wf.Spin and Vector3.new(0, wf.Power, 0) or Vector3.zero
			flingSeeded = true
		end
		flingActive = true
		root.AssemblyLinearVelocity = flingVel
		root.AssemblyAngularVelocity = flingAng
	end)

	RunService.Heartbeat:Connect(function()
		local cfCfg = Config.CarFling
		if not cfCfg.Enabled then return end
		local char = player.Character
		local seat = char and char:FindFirstChildOfClass("Humanoid") and char.Humanoid.SeatPart
		if not seat then
			for _, v in ipairs(workspace:GetDescendants()) do
				if v:IsA("VehicleSeat") and v.Occupant and v.Occupant.Parent == char then
					seat = v
					break
				end
			end
		end
		if seat and seat.Parent then
			local vehicleModel = seat.Parent
			if not vehicleModel:IsA("Model") then vehicleModel = vehicleModel.Parent end
			if vehicleModel and vehicleModel:IsA("Model") then
				for _, part in ipairs(vehicleModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity = part.CFrame.LookVector * cfCfg.Speed + Vector3.new(0, cfCfg.Power * 0.001, 0)
						part.AssemblyAngularVelocity = Vector3.new(0, cfCfg.Power * 0.001, 0)
					end
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not flingActive then return end
		local _, _, root = getChar()
		if root then
			root.AssemblyLinearVelocity = flingVel
			root.AssemblyAngularVelocity = flingAng
		end
	end)

	RunService.Stepped:Connect(function()
		if not flingActive then return end
		flingActive = false
		local _, _, root = getChar()
		if root then
			root.AssemblyLinearVelocity = flingVel + Vector3.new(0, 0.1, 0)
			root.AssemblyAngularVelocity = flingAng
		end
	end)

	local Hooks = { on = false, origIndex = nil }
	local fovCircleFrame    = nil
	local silentCircleFrame = nil

	local Whitelist = {}
	local function IsWhitelisted(p)
		local nameLower = p.Name:lower()
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

	local silentCache = { part = nil, pos = nil, plr = nil }
	local silentRoll, silentRollT = true, 0
	Hooks.silentConn = nil

	local function silentTick()
		if not (Aim.on and Aim.silent) then
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
			return
		end
		local now = os.clock()
		if now - silentRollT > 0.1 then
			silentRollT = now
			silentRoll = math.random(1, 100) <= Aim.hitChance
		end
		if not silentRoll then
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
			return
		end
		local ok, t, h = pcall(acquire)
		if ok and t and h then
			local ch = t.Character
			local part = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
			silentCache.part = part
			silentCache.pos  = h
			silentCache.plr  = t
		else
			silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
		end
	end

	_G.DevTools = _G.DevTools or {}
	function _G.DevTools.GetAimPosition(defaultPos)
		return silentCache.pos or defaultPos
	end
	function _G.DevTools.GetAimTarget()
		return silentCache.part
	end
	function _G.DevTools.GetAimDirection(origin, defaultDir)
		local p = silentCache.pos
		if p and (p - origin).Magnitude > 0.01 then return (p - origin).Unit end
		return defaultDir
	end

	local function installHooks()
		if Hooks.on or not EX.hook then return false end
		if not Hooks.silentConn then
			Hooks.silentConn = RunService.RenderStepped:Connect(silentTick)
		end
		local okIndex, origIndex = pcall(function()
			return EX.hook(game, "__index", function(self, key)
				if Aim.silent and silentCache.pos and not checkcaller() then
					if self == mouse then
						if key == "Hit"    then return CFrame.new(silentCache.pos) end
						if key == "Target" then return silentCache.part end
						if key == "UnitRay" then
							local o = CAM.CFrame.Position
							return Ray.new(o, (silentCache.pos - o).Unit * 2000)
						end
					end
				end
				if Aim.wallbang and self == workspace and key == "Raycast" then
					return wallbangRaycast
				end
				return origIndex(self, key)
			end)
		end)
		if okIndex then
			Hooks.on = true
			Hooks.origIndex = origIndex
			return true
		end
		return false
	end

	local function removeHooks()
		if not Hooks.on or not EX.hook then return end
		if Hooks.origIndex then
			pcall(EX.hook, game, "__index", Hooks.origIndex)
		end
		if Hooks.silentConn then
			Hooks.silentConn:Disconnect()
			Hooks.silentConn = nil
		end
		silentCache.part, silentCache.pos, silentCache.plr = nil, nil, nil
		Hooks.on = false
	end

	local UIS = UserInputService
	local camera = CAM
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local menuFrameRef2 = nil

	local function mouseOverMenu()
		if not (menuFrameRef2 and menuFrameRef2.Visible) then return false end
		local m = UIS:GetMouseLocation()
		local p, sz = menuFrameRef2.AbsolutePosition, menuFrameRef2.AbsoluteSize
		return m.X >= p.X and m.X <= p.X + sz.X and m.Y >= p.Y and m.Y <= p.Y + sz.Y
	end

	local function isVisible(part)
		if Config.Wallbang and Config.Wallbang.Enabled then return true end
		local origin = camera.CFrame.Position
		local dir = part.Position - origin
		local ignore = { player.Character }
		for _ = 1, 8 do
			rayParams.FilterDescendantsInstances = ignore
			local res = workspace:Raycast(origin, dir, rayParams)
			if not res then return true end
			local inst = res.Instance
			if inst:IsDescendantOf(part.Parent) then return true end
			if inst.Transparency >= 0.95 or not inst.CanCollide then
				table.insert(ignore, inst)
			else
				return false
			end
		end
		return false
	end

	local function aimCenter(useMouse)
		if Aim.silent then
			local vp = camera.ViewportSize
			return Vector2.new(vp.X * .5 + Aim.silentOffsetX, vp.Y * .5 + Aim.silentOffsetY)
		end
		if useMouse and UIS.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			return UIS:GetMouseLocation()
		end
		return camera.ViewportSize / 2
	end

	local function resolveAimPart(char, partName)
		partName = partName or "Head"
		local part
		if partName == "Torso" or partName == "UpperTorso" then
			part = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		else
			part = char:FindFirstChild(partName)
		end
		return part or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
	end

	local function getClosestTarget(s, partName, useMouse)
		local center = aimCenter(useMouse)
		local camPos = camera.CFrame.Position
		local bestScreen, bestWorld, bestPart, bestPlr, bestDist = nil, nil, nil, nil, s.FOV
		for _, other in ipairs(Players:GetPlayers()) do
			local char = other.Character
			if other == player or not char then continue end
			if s.TeamCheck and other.Team ~= nil and other.Team == player.Team then continue end
			local hum = char:FindFirstChildOfClass("Humanoid")
			local part = resolveAimPart(char, partName)
			if not hum or not part or hum.Health <= 0 then continue end
			if (part.Position - camPos).Magnitude > (s.MaxDistance or s.maxDist or 1200) then continue end
			local pos3D = part.Position
			if s.Prediction then
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then pos3D = pos3D + root.AssemblyLinearVelocity * (s.PredictionFactor or 0.12) end
			end
			local sp, onScrn = camera:WorldToViewportPoint(pos3D)
			if not onScrn or sp.Z <= 0 then continue end
			local v = Vector2.new(sp.X, sp.Y)
			local d = (v - center).Magnitude
			if d < bestDist and (not s.WallCheck or isVisible(part)) then
				bestScreen, bestWorld, bestPart, bestPlr, bestDist = v, pos3D, part, other, d
			end
		end
		return bestScreen, bestWorld, bestPart, bestPlr
	end

	local function acquire()
		local aimCfg = {
			FOV = Aim.silent and Aim.silentFov or Aim.fov,
			TeamCheck = Aim.ignoreTeam, MaxDistance = Aim.maxDist,
			Prediction = false, WallCheck = Aim.wallCheck,
		}
		local _, world, _, plr = getClosestTarget(aimCfg, "Head", false)
		return plr, world
	end

	local function triggerRapidFire()
		local ch = player.Character
		if not ch then return end
		local tool = ch:FindFirstChildOfClass("Tool")
		if tool then
			pcall(function()
				tool:Activate()
				for _, descendant in ipairs(tool:GetDescendants()) do
					if descendant:IsA("RemoteEvent") then
						pcall(function() descendant:FireServer() end)
					end
				end
			end)
		end
		if EX.input then pcall(EX.input) end
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
			VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
		end)
	end

	local function updateCircle()
		local vp = CAM.ViewportSize
		local activeCenter = Vector2.new(vp.X * .5 + Aim.silentOffsetX, vp.Y * .5 + Aim.silentOffsetY)
		local fc = Config.FOVCircle
		if fovCircleFrame then
			local showNormal = Aim.on and Aim.showFov and not Aim.silent and fc.Show
			fovCircleFrame.Visible = showNormal
			if showNormal then
				local r = Aim.fov
				local center = Vector2.new(vp.X * .5, vp.Y * .5)
				fovCircleFrame.Position = UDim2.fromOffset(center.X, center.Y)
				fovCircleFrame.Size = UDim2.fromOffset(r * 2, r * 2)
				local so = fovCircleFrame:FindFirstChildOfClass("UIStroke")
				if so then
					so.Color = Aim.target and C.on or Color3.fromRGB(Aim.fovColorR, Aim.fovColorG, Aim.fovColorB)
					so.Thickness = fc.Thickness
				end
			end
		end
		if silentCircleFrame then
			local showSilent = Aim.showFov and Aim.silent and fc.Show
			silentCircleFrame.Visible = showSilent
			if showSilent then
				local r = Aim.silentFov
				silentCircleFrame.Position = UDim2.fromOffset(activeCenter.X, activeCenter.Y)
				silentCircleFrame.Size = UDim2.fromOffset(r * 2, r * 2)
				local so = silentCircleFrame:FindFirstChildOfClass("UIStroke")
				if so then
					so.Color = Aim.target and C.on or Color3.fromRGB(Aim.silentColorR, Aim.silentColorG, Aim.silentColorB)
					so.Thickness = fc.Thickness
				end
			end
		end
	end

	local function ExecuteSkidFling(TargetPlayer)
		if not TargetPlayer or not TargetPlayer.Parent then return false end
		if IsPlayerSeated(TargetPlayer) then return false end
		local Character = player.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Humanoid and Humanoid.RootPart
		local TCharacter = TargetPlayer.Character
		local THumanoid = TCharacter and TCharacter:FindFirstChildOfClass("Humanoid")
		local TRootPart = THumanoid and THumanoid.RootPart
		local THead = TCharacter and TCharacter:FindFirstChild("Head")
		if not (Character and Humanoid and RootPart) then return false end
		local oldPos = RootPart.CFrame
		if THead then workspace.CurrentCamera.CameraSubject = THead end
		local function FPos(BasePart, Pos, Ang)
			if not BasePart or not BasePart.Parent or not RootPart then return end
			RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
			Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
			RootPart.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
			RootPart.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
		end
		local function SFBasePart(BasePart)
			local Time = tick()
			local Angle = 0
			repeat
				if RootPart and THumanoid then
					Angle = Angle + 100
					FPos(BasePart, CFrame.new(0, 1.5, 0), CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
					FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(Angle), 0, 0)); task.wait()
				else break end
			until BasePart.AssemblyLinearVelocity.Magnitude > 500
				or BasePart.Parent ~= TargetPlayer.Character
				or tick() > Time + 1.5
		end
		local fpdh = workspace.FallenPartsDestroyHeight
		workspace.FallenPartsDestroyHeight = 0/0
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		if TRootPart then SFBasePart(TRootPart) elseif THead then SFBasePart(THead) end
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
		workspace.CurrentCamera.CameraSubject = Humanoid
		repeat
			if not RootPart then break end
			RootPart.CFrame = oldPos
			Character:SetPrimaryPartCFrame(oldPos)
			Humanoid:ChangeState("GettingUp")
			task.wait()
		until (RootPart.Position - oldPos.p).Magnitude < 25
		workspace.FallenPartsDestroyHeight = fpdh
		return true
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
			if Aim.target and Aim.headPos and not Aim.silent then
				local goal = CFrame.lookAt(CAM.CFrame.Position, Aim.headPos)
				CAM.CFrame = Aim.smooth <= 0 and goal or CAM.CFrame:Lerp(goal, math.clamp(1 - Aim.smooth, .04, 1))
			end
		end
		updateCircle()
		Rapid.aimFire = Aim.on and Aim.autoFire and Aim.target ~= nil
		if Rapid.on or Rapid.aimFire then
			Rapid.acc += dt
			if Rapid.acc >= Rapid.rate then
				Rapid.acc = 0
				task.spawn(triggerRapidFire)
			end
		end
		if State.spectating then
			local targetPlr = Players:FindFirstChild(State.spectating)
			local ch = targetPlr and targetPlr.Character
			local head = ch and ch:FindFirstChild("Head")
			if head then CAM.CameraSubject = head
			else CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid") end
		end
	end

	local function ensureCombat()
		local wantCombat = Aim.on or Aim.silent or Aim.wallbang or Aim.hitbox
			or Rapid.on or SkidFlingAll.on or Config.WalkFling.Enabled
			or Config.CarFling.Enabled or State.spectating
			or Config.Camlock.Enabled or Config.Orbit.Enabled or Config.SpinBot.Enabled
		if wantCombat then
			if not State.conns.combat then
				State.conns.combat = hook(RunService.RenderStepped, combatTick)
			end
		else
			if State.conns.combat then
				State.conns.combat:Disconnect()
				State.conns.combat = nil
			end
			Aim.target, Aim.headPos = nil, nil
			updateCircle()
		end
		if Aim.on or Aim.silent or Aim.wallbang then
			installHooks()
		else
			removeHooks()
		end
	end

	--==========================================================
	-- Camlock (telavivpanel)
	--==========================================================
	local camTarget = nil
	local function camValid(plr, c)
		local char = plr and plr.Parent and plr.Character
		if not char then return nil end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local part = resolveAimPart(char, c.TargetPart)
		if not hum or not part or hum.Health <= 0 then return nil end
		return part, char
	end
	local function camPick(c)
		local viewport = camera.ViewportSize
		local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local best, bestDist = nil, c.FOV
		for _, other in ipairs(Players:GetPlayers()) do
			if other == player then continue end
			if c.TeamCheck and other.Team ~= nil and other.Team == player.Team then continue end
			local part = camValid(other, c)
			if not part then continue end
			if (part.Position - camera.CFrame.Position).Magnitude > c.MaxDistance then continue end
			if c.WallCheck and not isVisible(part) then continue end
			local sp = camera:WorldToViewportPoint(part.Position)
			local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
			if d < bestDist then best, bestDist = other, d end
		end
		return best
	end
	pcall(function() RunService:UnbindFromRenderStep("KayserCamlock") end)
	RunService:BindToRenderStep("KayserCamlock", Enum.RenderPriority.Camera.Value + 2, function()
		local c = Config.Camlock
		if not c.Enabled then camTarget = nil return end
		if not (c.Sticky and camTarget and camValid(camTarget, c)) then
			camTarget = camPick(c)
		end
		if not camTarget then return end
		local part, char = camValid(camTarget, c)
		if not part then return end
		local pos = part.Position
		if c.Prediction then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then pos = pos + root.AssemblyLinearVelocity * c.PredictionFactor end
		end
		local camPos = camera.CFrame.Position
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPos, pos), math.clamp(c.Smoothness, 0.01, 1))
	end)

	--==========================================================
	-- Orbit (telavivpanel)
	--==========================================================
	do
		local angle, target, nextPick = 0, nil, 0
		local function valid(p)
			local c = p and p.Parent and p.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			return h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
		end
		RunService.Heartbeat:Connect(function(dt)
			local o = Config.Orbit
			if not o.Enabled then target = nil return end
			local _, hum, root = getChar()
			if not (hum and root and hum.Health > 0) then return end
			if o.Target ~= "" then
				local q, found = o.Target:lower(), nil
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and (p.Name:lower():find(q, 1, true) or p.DisplayName:lower():find(q, 1, true)) then
						found = p
						break
					end
				end
				target = found
			elseif not valid(target) or os.clock() > nextPick then
				nextPick = os.clock() + 1
				local best, bd = nil, math.huge
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= player and valid(p) then
						local d = (p.Character.HumanoidRootPart.Position - root.Position).Magnitude
						if d < bd then best, bd = p, d end
					end
				end
				target = best
			end
			if not valid(target) then return end
			local tr = target.Character.HumanoidRootPart
			angle = (angle + o.Speed * dt) % (math.pi * 2)
			local pos = tr.Position + Vector3.new(math.cos(angle) * o.Radius, o.Height, math.sin(angle) * o.Radius)
			hum.AutoRotate = false
			root.CFrame = CFrame.lookAt(pos, tr.Position)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
	end

	--==========================================================
	-- SpinBot (telavivpanel)
	--==========================================================
	do
		local spinning = false
		RunService.Heartbeat:Connect(function(dt)
			local _, hum, root = getChar()
			local on = Config.SpinBot.Enabled and not Config.Fly.Enabled and not Config.Orbit.Enabled
				and hum and root and hum.Health > 0
			if not on then
				if spinning then
					spinning = false
					if hum then hum.AutoRotate = true end
				end
				return
			end
			spinning = true
			hum.AutoRotate = false
			local rot = math.rad(360 * math.max(Config.SpinBot.Speed, 0)) * dt
			root.CFrame = root.CFrame * CFrame.Angles(0, rot, 0)
		end)
	end

	--==========================================================
	-- Swim / Jump / Walk state (telavivpanel)
	--==========================================================
	local terrain = workspace.Terrain
	local waterT, waterCache = 0, false
	local function inWater(root, hum)
		if hum:GetState() == Enum.HumanoidStateType.Swimming then return true end
		local now = os.clock()
		if now - waterT < 0.1 then return waterCache end
		waterT = now
		waterCache = false
		local pos = root.Position
		local region = Region3.new(pos - Vector3.new(2, 2, 2), pos + Vector3.new(2, 2, 2)):ExpandToGrid(4)
		local ok, materials, occupancy = pcall(function() return terrain:ReadVoxels(region, 4) end)
		if ok and materials then
			local size = materials.Size
			for x = 1, size.X do
				for y = 1, size.Y do
					for z = 1, size.Z do
						if materials[x][y][z] == Enum.Material.Water and occupancy[x][y][z] > 0.5 then
							waterCache = true
						end
					end
				end
			end
		end
		return waterCache
	end

	local origSwim = nil
	RunService.RenderStepped:Connect(function()
		local _, hum, root = getChar()
		if not hum then return end
		local swim = Config.Swim
		local swimming = swim.Enabled and not Config.Fly.Enabled and inWater(root, hum)
		if swimming then
			if origSwim == nil then origSwim = hum.WalkSpeed end
			hum.WalkSpeed = swim.Speed
			if not UIS:GetFocusedTextBox() then
				local cf = camera.CFrame
				local dir = Vector3.zero
				if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
				if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
				if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
				if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
				if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
				if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
				if dir.Magnitude > 0 then
					root.AssemblyLinearVelocity = dir.Unit * swim.Speed
				end
			end
		elseif origSwim ~= nil then
			hum.WalkSpeed = origSwim
			origSwim = nil
		end
	end)

	--==========================================================
	-- Features (KAYSER + telavivpanel)
	--==========================================================
	local function dropHitbox(p)
		local hb = Hitboxes[p]
		if hb then pcall(function() hb:Destroy() end) end
		Hitboxes[p] = nil
	end

	local function makeHitbox(p)
		if Hitboxes[p] or p == player then return end
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
			State.conns.hitRefresh = hook(RunService.Heartbeat, function()
				for _, p in ipairs(Players:GetPlayers()) do makeHitbox(p) end
			end)
		elseif not on and State.conns.hitRefresh then
			State.conns.hitRefresh:Disconnect()
			State.conns.hitRefresh = nil
		end
		ensureCombat()
		notify("hitbox " .. (on and "on" or "off"))
	end

	function Features.esp(on)
		State.esp = on
		local function build(p)
			if p == player or ESP[p] then return end
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
			State.conns.espRefresh = hook(RunService.Heartbeat, function()
				local _, _, root = getChar()
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
				local ch = player.Character
				if not ch then return end
				for _, p in ipairs(ch:GetDescendants()) do
					if p:IsA("BasePart") then p.CanCollide = false end
				end
			end)
		end
	end

	function Features.fly(on)
		State.fly = on
		Config.Fly.Enabled = on
		local _, _, hrp = getChar()
		if on then
			if not hrp then
				State.fly = false
				Config.Fly.Enabled = false
				return notify("no character")
			end
			State.flyParts = {
				new("BodyVelocity", { Name = "KAYSER_V", MaxForce = Vector3.new(1e5, 1e5, 1e5), Velocity = Vector3.zero, Parent = hrp }),
				new("BodyGyro", { Name = "KAYSER_G", MaxTorque = Vector3.new(1e5, 1e5, 1e5), P = 2000, D = 60, Parent = hrp }),
			}
			State.conns.fly = hook(RunService.RenderStepped, function()
				local _, _, root = getChar()
				if not root or not State.flyParts or not State.flyParts[1].Parent then return end
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
				local _, hum = getChar()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		end
	end

	function Features.antiVoid(on)
		State.antiVoid = on
		if State.conns.void then State.conns.void:Disconnect() State.conns.void = nil end
		if on then
			State.conns.void = hook(RunService.Heartbeat, function()
				local ch, _, root = getChar()
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

	function Features.spectatePlayer(name)
		if name == "" or name == State.spectating then
			State.spectating = nil
			CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
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
		local _, _, hrp = getChar()
		if not hrp or name == "" then return notify("invalid waypoint") end
		State.waypoints[name] = hrp.CFrame
		persistWaypoints()
		notify("saved " .. name)
	end
