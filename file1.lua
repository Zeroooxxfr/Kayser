-- !nolint
--[[ =============================================================
  KAYSER 2.5  |  full-stack executor suite (single file, Luau)
  RIGHT SHIFT = toggle UI     END = unload + restore world

  Changelog 2.5 (sur 2.4):
    [AC 1]  hook __namecall en plus de __index — FireServer/InvokeServer filtrés
    [AC 2]  hookfunction global sur RemoteEvent.FireServer — report AC avalé
    [AC 3]  AC remotes hookés en no-op, pas Destroy (moins visible serveur)
    [AC 4]  getconnections(ScriptContext.Error) désactivé en boucle
    [AC 5]  setfpscap laissé à 240 à l'unload (pas de flash frame drop)
    [AC 6]  WalkSpeed/JumpPower reset à la valeur capturée, pas 16
    [WF 1]  WalkFling Power max 5e4 (était 5e8) — sous le clamp serveur
    [WF 2]  Spin OFF par défaut (ragdoll soi-même)
    [WF 3]  HeavyBody OFF par défaut (détectable)
    [WF 4]  SafeReturn ON par défaut, 50 studs
    [WF 5]  TriggerRange 10 studs par défaut — fling uniquement si proche
    [WF 6]  seeding une fois, pas par frame
    [BF 1]  combatTick tourne pour silent/wallbang/hitbox/fling
    [BF 2]  acquire useMouse=false en silent
    [BF 3]  silent toggle force Aim.on
    [BF 4]  silent circle sans Aim.on
    [BF 5]  FOV circle utilise les couleurs custom
    [BF 6]  flood probe snapshot-diff 0.5s
    [BF 7]  flood rate math corrigée
    [BF 8]  flood détecte rejet serveur
    [BF 9]  SkidFling AssemblyLinearVelocity
    [BF 10] attach retry PlayerGui
    [BF 11] _G.DevTools cleared unload
    [BF 12] flingActive reset à la désactivation
    [BF 13] getgenv résolu correctement
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

	-- [BF 13] getgenv résolu correctement
	local ENV
	do
		local ok, fn = pcall(function() return getgenv end)
		ENV = (ok and type(fn) == "function") and fn() or _G
	end
	if ENV.__KAYSER_LOADED then try(ENV.__KAYSER_UNLOAD) end

	--==========================================================
	-- 1. executor abstraction
	--==========================================================
	local EX = {
		hook    = (function() local ok, v = pcall(function() return hookmetamethod end) return ok and type(v) == "function" and v or nil end)(),
		namecall = (function() local ok, v = pcall(function() return getnamecallmethod end) return ok and type(v) == "function" and v or nil end)(),
		rawmt   = try(getrawmetatable),
		input   = try(mouse1click),
		clip    = try(setclipboard),
		fps     = try(setfpscap),
		draw    = try(function() return typeof(Drawing) == "table" and Drawing or nil end),
		hint    = try(identifyexecutor),
		hookfn  = try(function() return hookfunction end),
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
	-- 1.5 anti-cheat bypass layer
	--==========================================================
	local Bypass = {
		enabled = true,
		savedprops = {},
		hooked_index = false,
		hooked_namecall = false,
		hooked_fireserver = false,
		detections_blocked = 0,
		conns = {},
	}

	-- [AC 6] sauvegarde les vraies valeurs, pas un fallback hardcodé
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

	-- [AC 1] __index : spoof WalkSpeed/JumpPower reads
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

	-- [AC 1] __namecall : filtre les namecalls AC-named avant qu'ils partent
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
					-- bloque les namecalls qui reportent / kick / ban
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

	-- [AC 2] hook global FireServer — avale tout report AC
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

	-- [AC 3] AC remotes : hook FireServer en no-op, pas Destroy
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

	-- [AC 4] désactive les connections d'erreur en boucle, pas une fois
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

	--==========================================================
	-- 2. state & config
	--==========================================================
	local State = {
		esp = false, fullbright = false, noclip = false, fly = false,
		infJump = false, antiVoid = false, voidY = -60, safeCF = nil,
		baseSpeed = 16, baseJump = 50, baseFov = 70, addSpeed = 0, addJump = 0,
		waypoints = {}, conns = {}, flyParts = nil, light = nil, killed = false,
		spectating = nil,
	}

	local Config = {
		Fly = { Enabled = false },
		FOVCircle = {
			Show      = true,
			Color     = Color3.fromRGB(255, 255, 255),
			Thickness = 1.5,
		},
		AimTracer = {
			Enabled    = false,
			Color      = Color3.fromRGB(255, 80, 80),
			Thickness  = 1,
			FromCenter = false,
			FadeEnd    = true,
			ShowDot    = true,
		},
		Wallbang = { Enabled = false },
		-- [WF 1-5] valeurs safe par défaut
		WalkFling = {
			Enabled = false,
			Power = 5e4,
			Spin = false,
			TriggerRange = 10,
			OnlyNearPlayers = true,
			HeavyBody = false,
			SafeReturn = true,
			SafeReturnDistance = 50,
		},
		CarFling = {
			Enabled = false,
			Power = 5e4,
			Speed = 100,
		}
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

	-- [BF 10] attach retry
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

	--==========================================================
	-- 4. core helpers
	--==========================================================
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
	-- 5. advanced combat engine & car/walk fling
	--==========================================================
	local Aim = {
		on = false, silent = false, wallbang = false, hitbox = false, autoFire = false,
		fov = 260, silentFov = 260, smooth = .35, maxDist = 1200, ignoreTeam = true, wallCheck = true,
		target = nil, headPos = nil,
		silentOffsetX = 0, silentOffsetY = 0,
		showFov = true,
		hitChance = 100,
		fovColorR = 124, fovColorG = 152, fovColorB = 255,
		silentColorR = 255, silentColorG = 180, silentColorB = 60,
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

	-- [WF 6] seeding une fois, pas par frame
	-- [WF 1-5] puissance réduite, spin off, heavy body off, safe return on
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

	----------------------------------------------------------------------
	-- Silent aim
	----------------------------------------------------------------------
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

	----------------------------------------------------------------------
	-- Target acquisition
	----------------------------------------------------------------------
	local UIS     = UserInputService
	local camera  = CAM

	local rayParams = RaycastParams.new()
	rayParams.FilterType  = Enum.RaycastFilterType.Exclude
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

	-- [BF 2] silent mode utilise le cercle offset, jamais la souris brute
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
		local bestScreen, bestWorld, bestPart, bestPlr, bestDist =
			nil, nil, nil, nil, s.FOV

		for _, other in ipairs(Players:GetPlayers()) do
			local char = other.Character
			if other == player or not char then continue end
			if s.TeamCheck and other.Team ~= nil and other.Team == player.Team then continue end

			local hum  = char:FindFirstChildOfClass("Humanoid")
			local part = resolveAimPart(char, partName)
			if not hum or not part or hum.Health <= 0 then continue end
			if (part.Position - camPos).Magnitude > (s.MaxDistance or s.maxDist or 1200) then continue end

			local pos3D = part.Position
			if s.Prediction then
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then
					pos3D = pos3D + root.AssemblyLinearVelocity * (s.PredictionFactor or 0.12)
				end
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
			FOV         = Aim.silent and Aim.silentFov or Aim.fov,
			TeamCheck   = Aim.ignoreTeam,
			MaxDistance = Aim.maxDist,
			Prediction  = false,
			WallCheck   = Aim.wallCheck,
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

	-- [BF 4] silent circle sans Aim.on
	-- [BF 5] FOV circle utilise les couleurs custom
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
				fovCircleFrame.Size     = UDim2.fromOffset(r * 2, r * 2)
				local strokeObj = fovCircleFrame:FindFirstChildOfClass("UIStroke")
				if strokeObj then
					strokeObj.Color     = Aim.target and C.on or Color3.fromRGB(Aim.fovColorR, Aim.fovColorG, Aim.fovColorB)
					strokeObj.Thickness = fc.Thickness
				end
			end
		end

		if silentCircleFrame then
			local showSilent = Aim.showFov and Aim.silent and fc.Show
			silentCircleFrame.Visible = showSilent
			if showSilent then
				local r = Aim.silentFov
				silentCircleFrame.Position = UDim2.fromOffset(activeCenter.X, activeCenter.Y)
				silentCircleFrame.Size     = UDim2.fromOffset(r * 2, r * 2)
				local strokeObj = silentCircleFrame:FindFirstChildOfClass("UIStroke")
				if strokeObj then
					strokeObj.Color     = Aim.target and C.on
						or Color3.fromRGB(Aim.silentColorR, Aim.silentColorG, Aim.silentColorB)
					strokeObj.Thickness = fc.Thickness
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
				else
					break
				end
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
			if head then
				CAM.CameraSubject = head
			else
				CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			end
		end
	end

	-- [BF 1] combatTick tourne pour toutes les features actives
	local function ensureCombat()
		local wantCombat = Aim.on or Aim.silent or Aim.wallbang or Aim.hitbox
			or Rapid.on or SkidFlingAll.on or Config.WalkFling.Enabled
			or Config.CarFling.Enabled or State.spectating

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

	task.spawn(function()
		while true do
			if SkidFlingAll.on then
				for _, target in ipairs(Players:GetPlayers()) do
					if target ~= player and not IsWhitelisted(target) then
						if not SkidFlingAll.on then break end
						if not IsPlayerSeated(target) then
							pcall(function() ExecuteSkidFling(target) end)
						end
					end
				end
				task.wait(0.5)
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

	--==========================================================
	-- 6. movement / visuals / teleport / spectate
	--==========================================================
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
		if State.conns.void then
			State.conns.void:Disconnect()
			State.conns.void = nil
		end
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

	function Features.teleport(cf)
		local _, _, ch = getChar()
		if not ch or not cf then return end
		pcall(function() ch:PivotTo(cf + Vector3.new(0, 3, 0)) end)
	end

	function Features.teleportMouse()
		local loc = UserInputService:GetMouseLocation()
		local ray = CAM:ViewportPointToRay(loc.X, loc.Y)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { player.Character }
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

	--==========================================================
	-- 1.6 unlimited mode
	--==========================================================
	local Unlimited = { on = false }

	local LIMITS = {
		flood = { rate = 450, budget = 5000, workers = 4, lag = 1 },
		move = { speed = 500, jump = 500 },
		aim = { fov = 260, maxDist = 1200, smooth = 0.35 },
		rapid = { rate = 0.01 },
	}

	function Unlimited.enable()
		Unlimited.on = true
		Flood.rate = 20000
		Flood.budget = 1e9
		Flood.workers = 64
		Flood.lag = 0
		if Widgets.sliders["Rate per second"] then Widgets.sliders["Rate per second"].set(20000) end
		if Widgets.sliders["Part budget"] then Widgets.sliders["Part budget"].set(1e9) end
		if Widgets.sliders["Workers"] then Widgets.sliders["Workers"].set(64) end
		if Widgets.sliders["Iteration delay (s)"] then Widgets.sliders["Iteration delay (s)"].set(0) end
		if Widgets.sliders["+ WalkSpeed"] then Widgets.sliders["+ WalkSpeed"].set(5000) end
		if Widgets.sliders["+ JumpPower"] then Widgets.sliders["+ JumpPower"].set(5000) end
		State.addSpeed = 5000
		State.addJump = 5000
		Aim.fov = 5000
		Aim.silentFov = 5000
		Aim.maxDist = 100000
		Aim.smooth = 0
		if Widgets.sliders["FOV radius (px)"] then Widgets.sliders["FOV radius (px)"].set(5000) end
		if Widgets.sliders["Silent FOV radius (px)"] then Widgets.sliders["Silent FOV radius (px)"].set(5000) end
		if Widgets.sliders["Max distance"] then Widgets.sliders["Max distance"].set(100000) end
		if Widgets.sliders["Smoothness"] then Widgets.sliders["Smoothness"].set(0) end
		Rapid.rate = 0.0001
		if Widgets.sliders["Fire interval (s)"] then Widgets.sliders["Fire interval (s)"].set(0.0001) end
		applyMovement()
		notify("limits retired", 3)
	end

	function Unlimited.disable()
		Unlimited.on = false
		Flood.rate = LIMITS.flood.rate
		Flood.budget = LIMITS.flood.budget
		Flood.workers = LIMITS.flood.workers
		Flood.lag = LIMITS.flood.lag
		if Widgets.sliders["Rate per second"] then Widgets.sliders["Rate per second"].set(LIMITS.flood.rate) end
		if Widgets.sliders["Part budget"] then Widgets.sliders["Part budget"].set(LIMITS.flood.budget) end
		if Widgets.sliders["Workers"] then Widgets.sliders["Workers"].set(LIMITS.flood.workers) end
		if Widgets.sliders["Iteration delay (s)"] then Widgets.sliders["Iteration delay (s)"].set(LIMITS.flood.lag) end
		if Widgets.sliders["+ WalkSpeed"] then Widgets.sliders["+ WalkSpeed"].set(0) end
		if Widgets.sliders["+ JumpPower"] then Widgets.sliders["+ JumpPower"].set(0) end
		State.addSpeed = 0
		State.addJump = 0
		Aim.fov = 260
		Aim.silentFov = 260
		Aim.maxDist = 1200
		Aim.smooth = 0.35
		if Widgets.sliders["FOV radius (px)"] then Widgets.sliders["FOV radius (px)"].set(260) end
		if Widgets.sliders["Silent FOV radius (px)"] then Widgets.sliders["Silent FOV radius (px)"].set(260) end
		if Widgets.sliders["Max distance"] then Widgets.sliders["Max distance"].set(1200) end
		if Widgets.sliders["Smoothness"] then Widgets.sliders["Smoothness"].set(0.35) end
		Rapid.rate = LIMITS.rapid.rate
		if Widgets.sliders["Fire interval (s)"] then Widgets.sliders["Fire interval (s)"].set(LIMITS.rapid.rate) end
		applyMovement()
		notify("limits restored", 3)
	end

	--==========================================================
	-- 7. flood engine v2
	--==========================================================
	local Flood = {
		running = false, busy = false, created = 0, fires = 0, inflight = 0,
		cands = {}, selected = nil, variant = "cframe", prefix = {},
		budget = 5000, rate = 450, localMode = false, anchored = true,
		conn = nil, target = "", workers = 4, lag = 1,
		templates = {},
	}

	local old = workspace:FindFirstChild("KayserSpam")
	if old then old:Destroy() end
	local spamFolder = new("Folder", { Name = "KayserSpam", Parent = workspace })

	local function isOurs(inst)
		local p = inst
		while p and p ~= workspace do
			if p == spamFolder or p == player.Character then return true end
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
		local out, seen = {}, {}
		for _, root in ipairs({ ReplicatedStorage, ReplicatedFirst }) do
			for _, d in ipairs(root:GetDescendants()) do
				if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and not seen[d] then
					seen[d] = true
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
		local _, _, mine = getChar()
		return mine and mine.CFrame or CFrame.new()
	end

	local function jitter(base, spread)
		return base * CFrame.new(
			(math.random() - .5) * spread, (math.random() - .5) * spread, (math.random() - .5) * spread
		) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
	end

	local Harvest = { on = false, conns = {}, seen = {} }

	local function shapeOf(v, depth)
		depth = depth or 0
		if depth > 3 then return "..." end
		local t = typeof(v)
		if t == "CFrame" then return "CFrame" end
		if t == "Vector3" then return "Vector3" end
		if t == "Vector2" then return "Vector2" end
		if t == "Color3" then return "Color3" end
		if t == "Instance" then return "Instance:" .. v.ClassName end
		if t == "table" then
			local parts = {}
			for k, val in pairs(v) do
				parts[#parts + 1] = tostring(k) .. "=" .. shapeOf(val, depth + 1)
				if #parts >= 6 then break end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		if t == "string" then return "string(" .. #v .. ")" end
		if t == "number" then return math.floor(v) == v and "int" or "float" end
		return tostring(t)
	end

	local function sigOf(args)
		local parts = {}
		for i = 1, #args do parts[i] = shapeOf(args[i]) end
		return table.concat(parts, "|")
	end

	local function harvestRemote(re)
		if Harvest.seen[re] then return end
		Harvest.seen[re] = true
		if not EX.hookfn then return end
		local ok, orig = pcall(EX.hookfn, re.FireServer, function(self, ...)
			local args = { ... }
			local sig = sigOf(args)
			local entry = Flood.templates[re]
			if not entry then
				entry = { sig = sig, count = 0, sample = args }
				Flood.templates[re] = entry
			elseif entry.sig == sig then
				entry.count += 1
			end
			return orig(self, ...)
		end)
		if ok then table.insert(Harvest.conns, { re = re, orig = orig }) end
	end

	function Harvest.start(dur)
		if Harvest.on or not EX.hookfn then return false end
		Harvest.on = true
		Flood.templates = {}
		Harvest.seen = {}
		for _, root in ipairs({ ReplicatedStorage, ReplicatedFirst }) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("RemoteEvent") then harvestRemote(d) end
			end
		end
		task.delay(dur or 15, Harvest.stop)
		notify("harvesting remotes for " .. (dur or 15) .. "s", 4)
		return true
	end

	function Harvest.stop()
		if not Harvest.on then return end
		Harvest.on = false
		for _, h in ipairs(Harvest.conns) do
			pcall(EX.hookfn, h.re.FireServer, h.orig)
		end
		Harvest.conns = {}
		local n = 0
		for _ in pairs(Flood.templates) do n += 1 end
		notify(("harvest done · %d remotes captured"):format(n), 4)
	end

	local function argsFromTemplate(re, cf)
		local t = Flood.templates[re]
		if not t then return nil end
		local args = {}
		for i, v in ipairs(t.sample) do
			local tv = typeof(v)
			if tv == "CFrame" then args[i] = cf
			elseif tv == "Vector3" then args[i] = cf.Position
			elseif tv == "table" then
				local copy = {}
				for k, val in pairs(v) do
					local tk = typeof(val)
					if tk == "CFrame" then copy[k] = cf
					elseif tk == "Vector3" then copy[k] = cf.Position
					else copy[k] = val end
				end
				args[i] = copy
			else args[i] = v end
		end
		return args
	end

	local function buildPayload(cf, shape)
		local v = shape
		if v == "cframe" then return { cf } end
		if v == "pos" then return { cf.Position } end
		if v == "table_cf" then return { { cframe = cf, CFrame = cf } } end
		if v == "cf_size" then return { cf, Vector3.new(2, 2, 2) } end
		if v == "name_cf" then return { "Part", cf } end
		if v == "double" then return { cf, cf } end
		if v == "int_pos" then return { 1, cf.Position } end
		if v == "pos_int_cf" then return { cf.Position, 1, cf } end
		if v == "lookvector" then return { cf.Position, cf.LookVector } end
		return { { name = "Part", cframe = cf, size = Vector3.new(2, 2, 2), Color = Color3.new(1, 0, 0) } }
	end

	local function fire(cand, cf, shape)
		local o = cand.obj
		local args
		local tpl = argsFromTemplate(o, cf)
		if tpl then
			args = tpl
			for i = 1, #Flood.prefix do table.insert(args, i, Flood.prefix[i]) end
		else
			args = {}
			for i = 1, #Flood.prefix do args[#args + 1] = Flood.prefix[i] end
			local payload = buildPayload(cf, shape)
			for _, v in ipairs(payload) do args[#args + 1] = v end
		end
		if o:IsA("RemoteEvent") then
			pcall(o.FireServer, o, table.unpack(args))
		else
			if Flood.inflight > 60 then return end
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

	local SHAPES = {
		"template", "cframe", "pos", "table_cf", "cf_size", "name_cf",
		"table_full", "double", "int_pos", "pos_int_cf", "lookvector",
	}

	-- [BF 6] probe snapshot-diff 0.5s
	local function snapshotParts()
		local set = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") then set[d] = true end
		end
		return set
	end

	local function diffParts(before)
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and not before[d] and not isOurs(d) then n += 1 end
		end
		return n
	end

	local function tryShape(cand, shape)
		local before = snapshotParts()
		pcall(fire, cand, targetCF(Flood.target), shape)
		task.wait(.5)
		return diffParts(before)
	end

	function Flood.probe(cand)
		if Flood.templates[cand.obj] then
			local hits = tryShape(cand, "template")
			if hits > 0 then return "template", hits end
		end
		for _, shape in ipairs(SHAPES) do
			if shape == "template" then continue end
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
		local shape = Flood.variant or "cframe"
		-- [BF 7] rate math
		local perWorker = math.max(1, math.floor(Flood.rate / (Flood.workers * math.max(Flood.lag, 0.01))))
		for w = 1, Flood.workers do
			task.spawn(function()
				while Flood.running do
					if Flood.localMode then
						for _ = 1, perWorker do
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
						for _ = 1, perWorker do
							if not Flood.running then break end
							fire(Flood.selected, jitter(base, 8), shape)
						end
					end
					task.wait(Flood.lag > 0 and Flood.lag or 0)
				end
			end)
		end
		-- [BF 8] détecte rejet serveur
		task.delay(2, function()
			if Flood.running and Flood.fires > 200 and Flood.created < 20 then
				notify("remote rejected flood — dead end", 4)
				Flood.stop("rejected")
			end
		end)
		notify(("flooding %s · %s · %d/s x %d · cap %d"):format(
			name ~= "" and name or "server", shape, Flood.rate, Flood.workers, budget), 4)
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
	-- [BF 3] silent toggle force Aim.on
	toggle(cAim, "Silent aim", false, function(v)
		Aim.silent = v
		if v and not Aim.on then
			Aim.on = true
			local w = Widgets.toggles["Aimbot (camera)"]
			if w then w.set(true) end
		end
		if v and not EX.hook then notify("silent aim needs hookmetamethod") end
		ensureCombat()
	end, "hooks Mouse properties / Raycast namecalls")
	toggle(cAim, "Wallbang", false, function(v)
		Aim.wallbang = v
		Config.Wallbang.Enabled = v
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
	slider(cAim, "Silent hit chance (%)", 1, 100, 100, function(v) Aim.hitChance = v end)
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
	toggle(cFire, "Rapid fire (burst mode)", false, function(v)
		Rapid.on = v
		ensureCombat()
	end, "bypasses tool cooldowns / instant burst fire")
	slider(cFire, "Fire interval (s)", .001, .1, .01, function(v) Rapid.rate = v end)
	toggle(cFire, "Hitbox expander", false, Features.hitbox, "9x9 local hitbox")
	toggle(cFire, "SkidFling All", false, function(v)
		SkidFlingAll.on = v
		ensureCombat()
		notify("skidfling all " .. (v and "on" or "off"))
	end, "loops through all targets")
	-- [WF 1-5] WalkFling safe
	toggle(cFire, "WalkFling (safe)", false, function(v)
		Config.WalkFling.Enabled = v
		if not v then
			flingActive = false
			flingSeeded = false
			flingVel = Vector3.zero
			flingAng = Vector3.zero
			if flingMassOn then setFlingMass(false) end
		end
		ensureCombat()
		notify("walkfling " .. (v and "on" or "off"))
	end, "trigger seulement si proche · safe return actif")
	slider(cFire, "WalkFling Power", 1e3, 5e4, 5e4, function(v) Config.WalkFling.Power = v end)
	toggle(cFire, "WalkFling Spin", false, function(v) Config.WalkFling.Spin = v end)
	toggle(cFire, "WalkFling HeavyBody", false, function(v) Config.WalkFling.HeavyBody = v end, "détectable")
	toggle(cFire, "WalkFling SafeReturn", true, function(v) Config.WalkFling.SafeReturn = v end)
	slider(cFire, "WalkFling SafeReturn dist", 10, 200, 50, function(v) Config.WalkFling.SafeReturnDistance = v end)
	slider(cFire, "WalkFling TriggerRange", 3, 100, 10, function(v) Config.WalkFling.TriggerRange = v end)

	toggle(cFire, "Car Fling", false, function(v)
		Config.CarFling.Enabled = v
		ensureCombat()
		notify("car fling " .. (v and "on" or "off"))
	end, "flings vehicles you drive")
	slider(cFire, "Car Speed", 50, 1000, 100, function(v) Config.CarFling.Speed = v end)
	slider(cFire, "Car Fling Power", 1e3, 5e4, 5e4, function(v) Config.CarFling.Power = v end)

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
		if EX.fps then pcall(EX.fps, v and 240 or 240) end
		notify(v and "fps cap released" or "fps cap kept at 240")
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
	local wpRow = row(pTp)
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
			if p ~= player then
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
				if p ~= player then
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
		if #Flood.cands == 0 then label(list, "no candidates") end
	end

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
		for i, s in ipairs(SHAPES) do
			if s == (Flood.variant or "cframe") then
				Flood.variant = SHAPES[(i % #SHAPES) + 1]
				break
			end
		end
		shapeBtn.Text = "shape: " .. (Flood.variant or "cframe")
	end)
	mini(mRow1, "probe", 56, function()
		if Flood.busy or not Flood.selected then return notify("select a remote") end
		Flood.busy = true
		local s, hits = Flood.probe(Flood.selected)
		Flood.busy = false
		if s then notify(("hit %s · +%d"):format(s, hits), 4) else notify("no shape worked", 4) end
		Flood.render()
	end)
	mini(mRow1, "harvest", 62, function() Harvest.start(15) end, C.accent)
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
	slider(cManual, "Workers", 1, 16, 4, function(v) Flood.workers = math.floor(v) end)
	slider(cManual, "Iteration delay (s)", 0, 2, 1, function(v) Flood.lag = v end)
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
	button(cSess, "Rejoin", function() game:GetService("TeleportService"):Teleport(game.PlaceId, player) end)
	button(cSess, "Copy JobId", function()
		if EX.clip then
			pcall(EX.clip, game.JobId)
			notify("copied")
		else
			notify("no clipboard")
		end
	end)
	toggle(cSess, "Retire all limits", false, function(v)
		if v then Unlimited.enable() else Unlimited.disable() end
	end, "no client-side caps · server still validates")
	button(cSess, "Unload", function() try(ENV.__KAYSER_UNLOAD) end, C.warn)

	local cInfo = card(pMain)
	header(cInfo, "info")
	label(cInfo, ("executor: %s\nhook: %s · namecall: %s · fs-hook: %s · drawing: %s · fs: %s"):format(
		tostring(EX.hint or "unknown"),
		Bypass.hooked_index and "yes" or "no",
		Bypass.hooked_namecall and "yes" or "no",
		Bypass.hooked_fireserver and "yes" or "no",
		EX.draw and "yes" or "no",
		IO.ok and "yes" or "no"), 60)
	label(cInfo, "Silent aim / wallbang : fonctionnent uniquement en client-authoritative. WalkFling : safe sous le clamp serveur.", 40)

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

	State.conns.char = player.CharacterAdded:Connect(function()
		task.wait(.6)
		if State.killed then return end
		if State.fly then
			Features.fly(false)
			Features.fly(true)
		end
		applyMovement()
	end)

	do
		local _, hum = getChar()
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
					status.Text = ("%d fps · %s ms · combat %s · flood %s · ac+%d%s"):format(
						fps, ping and tostring(ping) or "-",
						Aim.on and (Aim.silent and "silent" or "aimbot") or (Aim.silent and "silent" or "off"),
						Flood.running and "run" or "idle",
						Bypass.detections_blocked,
						Unlimited.on and " · ∞" or "")
				end
				aimLbl.Text = Aim.target and (Aim.target.Name .. " · " .. math.floor(Aim.silent and Aim.silentFov or Aim.fov) .. "px") or "none"
				floodLbl.TextColor3 = Flood.running and C.on or C.dim
				if Flood.running then
					floodLbl.Text = ("RUN %d fires · %d/%d parts"):format(Flood.fires, Flood.created, Flood.budget)
				else
					floodLbl.Text = ("idle · %s · %s"):format(
						Flood.selected and Flood.selected.obj.Name or "no remote", Flood.variant or "cframe")
				end
			end)
		end
	end)

	-- [AC 5] setfpscap laissé à 240 (pas de flash frame drop)
	-- [AC 6] WalkSpeed reset à la valeur capturée
	-- [BF 11] _G.DevTools cleared unload
	ENV.__KAYSER_UNLOAD = function()
		if State.killed then return end
		State.killed = true
		if Unlimited.on then Unlimited.disable() end
		Bypass.enabled = false
		for _, c in pairs(Bypass.conns) do pcall(function() c:Disconnect() end) end
		Bypass.conns = {}
		for hum, _ in pairs(Bypass.savedprops) do restore_humanoid(hum) end
		for _, c in pairs(State.conns) do pcall(function() c:Disconnect() end) end
		State.conns = {}
		removeHooks()
		if fovCircleFrame then
			pcall(function() fovCircleFrame:Destroy() end)
			fovCircleFrame = nil
		end
		if silentCircleFrame then
			pcall(function() silentCircleFrame:Destroy() end)
			silentCircleFrame = nil
		end
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
		if EX.fps then pcall(EX.fps, 240) end
		CAM.FieldOfView = State.baseFov
		CAM.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local _, hum = getChar()
		if hum then
			hum.WalkSpeed = State.baseSpeed
			if State.baseJump > 0 then
				hum.UseJumpPower = true
				hum.JumpPower = State.baseJump
			end
		end
		if _G.DevTools then
			_G.DevTools.GetAimPosition = nil
			_G.DevTools.GetAimTarget   = nil
			_G.DevTools.GetAimDirection = nil
		end
		Gui:Destroy()
		ENV.__KAYSER_LOADED = nil
		ENV.__KAYSER_UNLOAD = nil
		ENV.__KAYSER_BYPASS = nil
		notify("unloaded", 2)
	end
	ENV.__KAYSER_LOADED = true

	--==========================================================
	-- 10. boot
	--==========================================================
	do
		local fovGui = Instance.new("ScreenGui")
		fovGui.Name              = "KayserFOV"
		fovGui.ResetOnSpawn      = false
		fovGui.IgnoreGuiInset    = true
		fovGui.DisplayOrder      = 49
		fovGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling

		local function makeCircleFrame(parent)
			local f = Instance.new("Frame")
			f.AnchorPoint          = Vector2.new(0.5, 0.5)
			f.BackgroundTransparency = 1
			f.BorderSizePixel      = 0
			f.Active               = false
			f.Visible              = false
			f.Parent               = parent
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
			local s = Instance.new("UIStroke")
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Color           = Color3.fromRGB(255, 255, 255)
			s.Thickness       = 1.5
			s.Parent          = f
			return f
		end

		fovCircleFrame    = makeCircleFrame(fovGui)
		silentCircleFrame = makeCircleFrame(fovGui)

		local tracerHolder = Instance.new("Frame")
		tracerHolder.Name                 = "AimTracerHolder"
		tracerHolder.BackgroundTransparency = 1
		tracerHolder.Size                 = UDim2.fromScale(1, 1)
		tracerHolder.ZIndex               = 5
		tracerHolder.Parent               = fovGui

		local aimTracerLine = Instance.new("Frame")
		aimTracerLine.Name             = "AimTracer"
		aimTracerLine.AnchorPoint      = Vector2.new(0.5, 0.5)
		aimTracerLine.BorderSizePixel  = 0
		aimTracerLine.BackgroundColor3 = Config.AimTracer.Color
		aimTracerLine.Size             = UDim2.fromOffset(2, 2)
		aimTracerLine.Visible          = false
		aimTracerLine.ZIndex           = 5
		aimTracerLine.Parent           = tracerHolder
		local tracerGradient = Instance.new("UIGradient")
		tracerGradient.Parent = aimTracerLine

		local aimDot = Instance.new("Frame")
		aimDot.AnchorPoint      = Vector2.new(0.5, 0.5)
		aimDot.Size             = UDim2.fromOffset(8, 8)
		aimDot.BackgroundColor3 = Config.AimTracer.Color
		aimDot.BorderSizePixel  = 0
		aimDot.Visible          = false
		aimDot.ZIndex           = 6
		aimDot.Parent           = tracerHolder
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = aimDot
		local dotStroke = Instance.new("UIStroke")
		dotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		dotStroke.Color           = Color3.new(1, 1, 1)
		dotStroke.Thickness       = 1
		dotStroke.Parent          = aimDot

		RunService.RenderStepped:Connect(function()
			local cfg = Config.AimTracer
			if not cfg.Enabled then
				aimTracerLine.Visible = false
				aimDot.Visible = false
				return
			end
			local ok, t, h = pcall(acquire)
			if not (ok and h) then
				aimTracerLine.Visible = false
				aimDot.Visible = false
				return
			end
			local sp, onScrn = CAM:WorldToViewportPoint(h)
			if not onScrn or sp.Z <= 0 then
				aimTracerLine.Visible = false
				aimDot.Visible = false
				return
			end
			local screenPos = Vector2.new(sp.X, sp.Y)
			local vp       = CAM.ViewportSize
			local origin   = cfg.FromCenter
				and Vector2.new(vp.X * 0.5, vp.Y * 0.5)
				or  Vector2.new(vp.X * 0.5, vp.Y - 28)
			local delta = screenPos - origin
			local mid   = (origin + screenPos) / 2
			aimTracerLine.Position        = UDim2.fromOffset(mid.X, mid.Y)
			aimTracerLine.Size            = UDim2.fromOffset(delta.Magnitude, math.max(1, cfg.Thickness))
			aimTracerLine.Rotation        = math.deg(math.atan2(delta.Y, delta.X))
			aimTracerLine.BackgroundColor3 = cfg.Color
			if cfg.FadeEnd then
				tracerGradient.Color    = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.new(0.3, 0.3, 0.3)),
				})
				tracerGradient.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			else
				tracerGradient.Color = ColorSequence.new(Color3.new(1, 1, 1))
			end
			aimTracerLine.Visible = true
			aimDot.Position        = UDim2.fromOffset(screenPos.X, screenPos.Y)
			aimDot.BackgroundColor3 = cfg.Color
			aimDot.Size            = UDim2.fromOffset(8 + cfg.Thickness * 2, 8 + cfg.Thickness * 2)
			aimDot.Visible         = cfg.ShowDot
		end)

		task.spawn(function()
			local pg = player:WaitForChild("PlayerGui")
			local old = pg:FindFirstChild("KayserFOV")
			if old then old:Destroy() end
			fovGui.Parent = pg
		end)
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
	log("executor:", tostring(EX.hint or "unknown"),
		"| index:", Bypass.hooked_index and "y" or "n",
		"| namecall:", Bypass.hooked_namecall and "y" or "n",
		"| fs:", Bypass.hooked_fireserver and "y" or "n",
		"| io:", IO.ok and "y" or "n")
	notify("KAYSER 2.5 loaded · RightShift UI · END unload", 4)
	if not EX.hook then notify("silent aim needs hookmetamethod — not supported", 6) end
	if not EX.hookfn then notify("harvest/AC-hook unavailable — hookfunction missing", 6) end

	print("[K] boot complete · gui:", Gui.Parent and Gui.Parent:GetFullName() or "NIL",
		"· enabled:", tostring(Gui.Enabled), "· size:", tostring(win.AbsoluteSize))
end

local ok, err = xpcall(main, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then warn("[K] FATAL " .. tostring(err)) end
