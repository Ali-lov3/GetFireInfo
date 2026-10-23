local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local MUZZLE_KEYS = { "muzzle", "firepoint", "fireposition", "shootpoint", "bulletspawn", "barrel", "tip", "origin" }
local REMOTE_KEYS = { "fire", "shoot", "shot", "bullet", "gun", "weapon", "reload" }
local AMMO_KEYS = { "ammo", "clip", "magazine", "bullets" }

local lines = {}

local function matches(name, keys)
	local lowered = string.lower(name)
	for _, key in ipairs(keys) do
		if string.find(lowered, key, 1, true) then
			return true
		end
	end
	return false
end

local function fmt(value)
	local kind = typeof(value)
	if kind == "Vector3" then
		return string.format("Vector3(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
	end
	if kind == "CFrame" then
		local p = value.Position
		return string.format("CFrame(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
	end
	if kind == "Instance" then
		return value:GetFullName()
	end
	return tostring(value)
end

local function copy(text)
	if setclipboard then
		pcall(setclipboard, text)
	elseif toclipboard then
		pcall(toclipboard, text)
	end
end

local function emit(block)
	for _, line in ipairs(block) do
		table.insert(lines, line)
	end
	print(table.concat(block, "\n"))
	copy(table.concat(lines, "\n"))
end

local function copyOnly(block)
	for _, line in ipairs(block) do
		table.insert(lines, line)
	end
	copy(table.concat(lines, "\n"))
end

local function findMuzzle(tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if (descendant:IsA("Attachment") or descendant:IsA("BasePart")) and matches(descendant.Name, MUZZLE_KEYS) then
			return descendant
		end
	end
	return tool:FindFirstChild("Handle")
end

local function findRemotes(container)
	local found = {}
	for _, descendant in ipairs(container:GetDescendants()) do
		if (descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction")) and matches(descendant.Name, REMOTE_KEYS) then
			table.insert(found, descendant)
		end
	end
	return found
end

local function readAmmo(tool)
	local ammo = {}
	for name, value in pairs(tool:GetAttributes()) do
		if matches(name, AMMO_KEYS) then
			ammo[name] = value
		end
	end
	for _, descendant in ipairs(tool:GetDescendants()) do
		if (descendant:IsA("IntValue") or descendant:IsA("NumberValue")) and matches(descendant.Name, AMMO_KEYS) then
			ammo[descendant.Name] = descendant.Value
		end
	end
	return ammo
end

local function getPose(part)
	if not part then
		return nil, nil
	end
	if part:IsA("Attachment") then
		return part.WorldPosition, part.WorldCFrame.LookVector
	end
	return part.Position, part.CFrame.LookVector
end

local function analyze(tool)
	local handle = tool:FindFirstChild("Handle")
	local muzzle = findMuzzle(tool)
	local remotes = findRemotes(tool)
	local ammo = readAmmo(tool)
	local score = 0
	if muzzle and muzzle ~= handle then
		score += 1
	end
	if #remotes > 0 then
		score += 2
	end
	if next(ammo) ~= nil then
		score += 1
	end
	if matches(tool.Name, REMOTE_KEYS) then
		score += 1
	end
	local origin, direction = getPose(muzzle)
	return {
		Tool = tool,
		IsGun = score >= 2,
		Score = score,
		Muzzle = muzzle,
		Origin = origin,
		Direction = direction,
		Remotes = remotes,
		Ammo = ammo,
	}
end

local function getEquipped()
	local character = LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	return analyze(tool)
end

local function collectGuns()
	local results = {}
	local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }
	for index = 1, 2 do
		local container = containers[index]
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					local info = analyze(child)
					if info.IsGun then
						table.insert(results, info)
					end
				end
			end
		end
	end
	return results
end

local function describeGun(info)
	local block = {
		"[GUN] " .. info.Tool:GetFullName(),
		"  Score: " .. info.Score,
		"  Muzzle: " .. (info.Muzzle and info.Muzzle:GetFullName() or "none"),
		"  Origin: " .. (info.Origin and fmt(info.Origin) or "none"),
		"  Direction: " .. (info.Direction and fmt(info.Direction) or "none"),
	}
	for name, value in pairs(info.Ammo) do
		table.insert(block, "  Ammo " .. name .. ": " .. tostring(value))
	end
	for _, remote in ipairs(info.Remotes) do
		table.insert(block, "  Remote: " .. remote:GetFullName() .. " (" .. remote.ClassName .. ")")
	end
	return block
end

local header = { "=== GetFireInfo ===" }
local guns = collectGuns()
if #guns == 0 then
	table.insert(header, "No gun detected in Character or Backpack")
end
for _, info in ipairs(guns) do
	for _, line in ipairs(describeGun(info)) do
		table.insert(header, line)
	end
end
table.insert(header, "[GLOBAL REMOTES]")
for _, remote in ipairs(findRemotes(ReplicatedStorage)) do
	table.insert(header, "  " .. remote:GetFullName() .. " (" .. remote.ClassName .. ")")
end
emit(header)

local function extractVectors(args)
	local vectors = {}
	local function visit(value, depth)
		local kind = typeof(value)
		if kind == "Vector3" then
			table.insert(vectors, value)
		elseif kind == "CFrame" then
			table.insert(vectors, value.Position)
		elseif kind == "table" and depth < 2 then
			for _, inner in pairs(value) do
				visit(inner, depth + 1)
			end
		end
	end
	for index = 1, args.n do
		visit(args[index], 0)
	end
	return vectors
end

local function describeShot(remote, method, args)
	local vectors = extractVectors(args)
	local gun = getEquipped()
	local origin = vectors[1]
	local second = vectors[2]
	local direction = nil
	if second then
		if math.abs(second.Magnitude - 1) < 0.01 then
			direction = second
		elseif origin and (second - origin).Magnitude > 0.001 then
			direction = (second - origin).Unit
		end
	end
	if gun then
		origin = origin or gun.Origin
		direction = direction or gun.Direction
	end
	local isGunRemote = matches(remote.Name, REMOTE_KEYS)
	if gun and table.find(gun.Remotes, remote) then
		isGunRemote = true
	end
	if not isGunRemote then
		return nil
	end
	local block = {
		"[SHOT] " .. remote:GetFullName() .. " via " .. method,
		"  Tool: " .. (gun and gun.Tool.Name or "none"),
		"  Origin: " .. (origin and fmt(origin) or "none"),
		"  Direction: " .. (direction and fmt(direction) or "none"),
	}
	for index = 1, args.n do
		table.insert(block, "  Arg " .. index .. " (" .. typeof(args[index]) .. "): " .. fmt(args[index]))
	end
	return block
end

if hookmetamethod and getnamecallmethod then
	local wrap = newcclosure or function(fn)
		return fn
	end
	local original
	original = hookmetamethod(game, "__namecall", wrap(function(self, ...)
		local method = getnamecallmethod()
		if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and not (checkcaller and checkcaller()) then
			local args = table.pack(...)
			local remote = self
			task.spawn(function()
				local ok, block = pcall(describeShot, remote, method, args)
				if ok and block then
					emit(block)
				end
			end)
		end
		return original(self, ...)
	end))
	emit({ "[HOOK] Listening for shots. Fire a weapon to log it." })
else
	emit({ "[HOOK] hookmetamethod not available, shot logging disabled" })
end

local FUNCTION_KEYS = {
	"origin",
	"lookat",
	"lookvector",
	"direction",
	"raycast",
	"findpartonray",
	"muzzle",
	"firepoint",
	"bullet",
	"shoot",
	"fire",
}

local function safeConstants(fn)
	local ok, constants = pcall(debug.getconstants, fn)
	if ok and type(constants) == "table" then
		return constants
	end
	return {}
end

local function safeUpvalueCount(fn)
	local ok, upvalues = pcall(debug.getupvalues, fn)
	local count = 0
	if ok and type(upvalues) == "table" then
		for _ in pairs(upvalues) do
			count += 1
		end
	end
	return count
end

local function ownerOf(fn)
	local ok, env = pcall(getfenv, fn)
	if ok and type(env) == "table" then
		local owner = rawget(env, "script")
		if typeof(owner) == "Instance" then
			return owner:GetFullName()
		end
	end
	return "unknown"
end

local function infoOf(fn, what)
	local ok, value = pcall(debug.info, fn, what)
	if ok then
		return value
	end
	return nil
end

local function scriptOf(fn)
	local ok, env = pcall(getfenv, fn)
	if ok and type(env) == "table" then
		local owner = rawget(env, "script")
		if typeof(owner) == "Instance" then
			return owner
		end
	end
	return nil
end

local function describeValue(value)
	if type(value) == "table" then
		local parts = {}
		local count = 0
		for key, inner in pairs(value) do
			count += 1
			if count > 12 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. typeof(inner))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return fmt(value)
end

local function listConstants(fn)
	local constants = {}
	for index, constant in pairs(safeConstants(fn)) do
		table.insert(constants, tostring(index) .. "=" .. describeValue(constant))
	end
	return table.concat(constants, ", ")
end

local function dumpFunction(index, fn)
	local name = infoOf(fn, "n")
	if not name or name == "" then
		name = "anonymous"
	end
	local block = {
		"--- [" .. index .. "] " .. name .. " ---",
		"source: " .. tostring(infoOf(fn, "s")) .. " line: " .. tostring(infoOf(fn, "l")),
		"constants: " .. listConstants(fn),
	}
	local okUpvalues, upvalues = pcall(debug.getupvalues, fn)
	if okUpvalues and type(upvalues) == "table" then
		for upvalueIndex, value in pairs(upvalues) do
			table.insert(block, "upvalue " .. tostring(upvalueIndex) .. " (" .. typeof(value) .. "): " .. describeValue(value))
		end
	end
	local okProtos, protos = pcall(debug.getprotos, fn)
	if okProtos and type(protos) == "table" then
		for protoIndex, proto in pairs(protos) do
			table.insert(block, "proto " .. tostring(protoIndex) .. " constants: " .. listConstants(proto))
		end
	end
	return block
end

local function scanFunctions()
	if not (getgc and debug and debug.getconstants) then
		emit({ "[FUNCTIONS] getgc or debug.getconstants not available" })
		return
	end
	local found = {}
	local seen = 0
	for _, object in ipairs(getgc(true)) do
		seen += 1
		if seen % 3000 == 0 then
			task.wait()
		end
		if type(object) == "function"
			and not (isexecutorclosure and isexecutorclosure(object))
			and not (islclosure and not islclosure(object))
		then
			local matched = {}
			local count = 0
			for _, constant in pairs(safeConstants(object)) do
				if type(constant) == "string" and matches(constant, FUNCTION_KEYS) and not matched[constant] then
					matched[constant] = true
					count += 1
				end
			end
			if count >= 2 then
				table.insert(found, { Function = object, Matched = matched, Count = count })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.Count > b.Count
	end)
	local block = { "[FUNCTIONS] scanned " .. seen .. " objects, " .. #found .. " candidates" }
	for index = 1, math.min(#found, 40) do
		local entry = found[index]
		local fn = entry.Function
		local names = {}
		for constant in pairs(entry.Matched) do
			table.insert(names, constant)
		end
		table.sort(names)
		local name = infoOf(fn, "n")
		if not name or name == "" then
			name = "anonymous"
		end
		table.insert(
			block,
			string.format(
				"  [%d] %s | %s:%s | upvalues %d | %s",
				index,
				name,
				ownerOf(fn),
				tostring(infoOf(fn, "l")),
				safeUpvalueCount(fn),
				table.concat(names, ", ")
			)
		)
	end
	emit(block)
	local dump = { "=== FUNCTION DUMP ===" }
	local limit = math.min(#found, 40)
	for index = 1, limit do
		for _, line in ipairs(dumpFunction(index, found[index].Function)) do
			table.insert(dump, line)
		end
	end
	local decompiled = 0
	if decompile then
		local done = {}
		for index = 1, limit do
			local owner = scriptOf(found[index].Function)
			if owner and not done[owner] then
				done[owner] = true
				local ok, source = pcall(decompile, owner)
				table.insert(dump, "=== SOURCE " .. owner:GetFullName() .. " ===")
				if ok and source then
					decompiled += 1
					table.insert(dump, tostring(source))
				else
					table.insert(dump, "decompile failed")
				end
			end
		end
	else
		table.insert(dump, "decompile not available")
	end
	copyOnly(dump)
	print("[FUNCTIONS] copied dump of " .. limit .. " functions and " .. decompiled .. " scripts to clipboard")
end

task.spawn(scanFunctions)

