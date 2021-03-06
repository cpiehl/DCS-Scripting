-- DO SCRIPT FILE on mission start
-- place pairs of pylons named like "GateLeft #001" and "GateRight #001"
-- F10 menu to show leaderboard and restart lap attempt

-- TODO
-- on leave event, iterate all players and remove nonexistant
-- support more than Airshow_Cone

local gateDepth = 30 -- meters
local timerHiResDist2 = 50^2 -- high resolution timer distance in meters squared
local timerMedResDist2 = 200^2 -- medium resolution timer distance in meters squared

local upvec = {
	['x'] = 0,
	['y'] = 1,
	['z'] = 0
}
local gates = {}
local players = {}
local playersLapTime = {}
local playersPenaltyTime = {}
local playersNextGate = {}
local leaderboard = {}
local timerIDs = {}
local playerJoinEventHandler = {}
local totalGates = 0

-- returns distance squared, sqrt() later if you really need it
function getDistance2(a, b)
	local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
	return x*x + y*y + z*z
end

-- magnitude
function vec3mag(a)
	return math.sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
end

-- midpoint between two points
function midpoint(a, b)
	return {
		['x'] = (a.x+b.x)/2,
		['y'] = (a.y+b.y)/2,
		['z'] = (a.z+b.z)/2
	}
end

-- Subtract vector b from vector a
function vec3sub(a, b)
	return {
		["x"] = a.x-b.x,
		["y"] = a.y-b.y,
		["z"] = a.z-b.z
	}
end

-- Multiply vector a by scalar b
function vec3mul(a, b)
	return {
		["x"] = a.x*b,
		["y"] = a.y*b,
		["z"] = a.z*b
	}
end

-- Divide vector a by scalar b
function vec3div(a, b)
	return {
		["x"] = a.x/b,
		["y"] = a.y/b,
		["z"] = a.z/b
	}
end

-- a cross b
function vec3cross(a, b)
	return {
		['x'] = a.y * b.z - b.y * a.z,
		['y'] = b.x * a.z - a.x * b.z,
		['z'] = a.x * b.y - b.x * a.y
	}
end

function vec3norm(a)
	return vec3div(a, vec3mag(a))
end

function outputStartLap(playerName)
	local gID = players[playerName]:getGroup():getID()
	trigger.action.outTextForGroup(gID, playerName .. " Lap Start!", 1, false)
end

function outputLeaderboard(playerName)
	local gID = players[playerName]:getGroup():getID()
	local a = {}
	for n,t in pairs(leaderboard) do
		table.insert(a, {n, t})
	end
	table.sort(a, function(a, b)
		return a[2] < b[2]
	end)
	local output = "Leaderboard:\n"
	for i,n in ipairs(a) do
		output = output .. string.format(
			"%d. %s %3.2f\n",
			i,
			n[1],
			n[2]
		)
--~ 		if i > 3 then
--~ 			break
--~ 		end
	end
	trigger.action.outTextForGroup(gID, output, 10, false)
end

function outputEndLap(playerName)
	local gID = players[playerName]:getGroup():getID()
	local newrecord = ""
	local laptime = timer.getTime() - playersLapTime[playerName] + playersPenaltyTime[playerName]
	if leaderboard[playerName] == nil or leaderboard[playerName] > laptime then
		leaderboard[playerName] = laptime
		newrecord = "NEW Record!"
	end
	trigger.action.outText(string.format(
		"%s Time (Penalty): %3.2f (%+ds) %s",
		playerName,
		laptime,
		playersPenaltyTime[playerName],
		newrecord
	), 5, false)
	outputLeaderboard(playerName)
end

function outputGatePassed(playerName, nextGateNum)
	local gID = players[playerName]:getGroup():getID()
	trigger.action.outTextForGroup(gID, playerName .. " passed Gate #" .. nextGateNum, 1, false)
end

function outputGatePenalty(playerName, nextGateNum)
	local gID = players[playerName]:getGroup():getID()
	trigger.action.outTextForGroup(gID, playerName .. " +2s penalty Gate #" .. nextGateNum, 1, false)
end

function inGateBounds(playerName, nextGateNum)
	local f, r, l, b, n, pos
	n = nextGateNum
	pos = players[playerName]:getPoint()

	f = vec3cross(vec3sub(pos, gates[n].left), gates[n].fvec)
	r = vec3cross(vec3sub(pos, gates[n].right), gates[n].rvec)
	b = vec3cross(vec3sub(pos, gates[n].br), gates[n].bvec)
	l = vec3cross(vec3sub(pos, gates[n].bl), gates[n].lvec)

	-- are all cross products the same sign?
	if (f.y > 0 and r.y > 0 and l.y > 0 and b.y > 0) then -- or (f.y < 0 and r.y < 0 and l.y < 0 and b.y < 0) then
		if (gates[n].y < pos.y) then
			return 1 -- passed with penalty
		end
		return 2 -- passed without penalty
	end
	return 0
end

function checkGates(params, time)
	local playerName = params["playerName"]
	local gateStatus, interval
	local nextGateNum = playersNextGate[playerName]
	gateStatus = inGateBounds(playerName, nextGateNum)
	if gateStatus > 0 then
		if nextGateNum == 1 and gateStatus == 2 then -- start lap
			playersLapTime[playerName] = timer.getTime()
			playersPenaltyTime[playerName] = 0
			outputStartLap(playerName)
		elseif gateStatus == 2 then -- passed without penalty
			outputGatePassed(playerName, nextGateNum)
		else -- passed with penalty
			outputGatePenalty(playerName, nextGateNum)
			playersPenaltyTime[playerName] = playersPenaltyTime[playerName] + 2
		end
		playersNextGate[playerName] = nextGateNum + 1
		if playersNextGate[playerName] > totalGates then
			playersNextGate[playerName] = 1 -- restart lap
			outputEndLap(playerName)
		end
	end
	local dist2 = getDistance2(players[playerName]:getPoint(), gates[nextGateNum].pos)
	if
		dist2 < timerHiResDist2 and
		(playersNextGate[playerName] == 1 or
		playersNextGate[playerName] == totalGates)
	then
--~ 		trigger.action.outText("High Resolution Update Mode: " .. time, 1, false)
		interval = 0.01
	elseif dist2 < timerMedResDist2 then
--~ 		trigger.action.outText("Med Resolution Update Mode: " .. time, 1, false)
		interval = 0.1
	else
--~ 		trigger.action.outText(playerName .. " Low Resolution Update Mode: " .. time, 1, false)
		interval = 1
	end
	return time + interval
end

function restartLap(playerName)
	trigger.action.outText(playerName .. " DNF", 3, false)
	playersNextGate[playerName] = 1
end

function init()
	-- server init players (mostly for singleplayer)
	local playerName, gID
	for key,value in pairs(coalition.getPlayers(2)) do -- blue
		playerName = value:getPlayerName()
		trigger.action.outText(playerName .. " entered " .. value:getTypeName(), 1, false)
		players[playerName] = value
		playersNextGate[playerName] = 1
		timerIDs[playerName] = timer.scheduleFunction(
			checkGates,
			{
				["playerName"] = playerName
			},
			timer.getTime() + 1
		)
		gID = players[playerName]:getGroup():getID()
		missionCommands.addCommandForGroup(gID, "Leaderboard", nil, outputLeaderboard, playerName)
		missionCommands.addCommandForGroup(gID, "Restart Lap", nil, restartLap, playerName)
	end

	-- init any latecomers
	function playerJoinEventHandler:onEvent(event)
		local playerName, gID
		if event.id == world.event.S_EVENT_BIRTH then
			if event.initiator ~= nil then
				playerName = event.initiator:getPlayerName()
				trigger.action.outText(playerName .. " entered " .. event.initiator:getTypeName(), 1, false)
				players[playerName] = event.initiator
				playersNextGate[playerName] = 1
				timerIDs[playerName] = timer.scheduleFunction(
					checkGates,
					{
						["playerName"] = playerName
					},
					timer.getTime() + 1
				)
				gID = players[playerName]:getGroup():getID()
				missionCommands.addCommandForGroup(gID, "Leaderboard", nil, outputLeaderboard, playerName)
				missionCommands.addCommandForGroup(gID, "Restart Lap", nil, restartLap, playerName)
			end
		elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
			if event.initiator ~= nil then
				playerName = event.initiator:getPlayerName()
				trigger.action.outText(playerName .. " left " .. event.initiator:getTypeName(), 1, false)
				if timerIDs[playerName] ~= nil then
					timer.removeFunction(timerIDs[playerName])
				end
				playersNextGate[playerName] = nil
				timerIDs[playerName] = nil
			end
		end
	end
	world.addEventHandler(playerJoinEventHandler)

	-- init gate locations
	local staticObjects = coalition.getStaticObjects(2) -- blue
	local name, gateNum, gateName

	for i = 1, #staticObjects do
		if staticObjects[i]:getTypeName() == "Airshow_Cone" then
			name = staticObjects[i]:getName()
			gateName = name:sub(1, #name - 5)
			if gateName == "GateRight" or gateName == "GateLeft" then
				gateNum = tonumber(name:sub(#name - 2))
				if gates[gateNum] == nil then
					gates[gateNum] = {}
					gates[gateNum].desc = staticObjects[i]:getDesc()
				end
				if gateName == "GateRight" then
					gates[gateNum]["right"] = staticObjects[i]:getPoint()
				else -- gateName == "GateLeft"
					gates[gateNum]["left"] = staticObjects[i]:getPoint()
				end
			end
		end
	end

	totalGates = #gates -- just in case length is O(n)
	for i = 1, totalGates do
		gates[i].pos = midpoint(gates[i].left, gates[i].right)
		gates[i].rad2 = getDistance2(gates[i].left, gates[i].right) / 2

		local backvec = vec3mul(vec3norm(vec3cross(upvec, vec3sub(gates[i].left, gates[i].right))), gateDepth)
		gates[i].br = vec3sub(gates[i].right, backvec) -- back right
		gates[i].bl = vec3sub(gates[i].left, backvec) -- back left

		gates[i].y = gates[i].pos.y + gates[i].desc.box.max.y
		gates[i].fvec = vec3sub(gates[i].left, gates[i].right)
		gates[i].rvec = vec3sub(gates[i].right, gates[i].br)
		gates[i].bvec = vec3sub(gates[i].br, gates[i].bl)
		gates[i].lvec = vec3sub(gates[i].bl, gates[i].left)

--~ 		trigger.action.smoke(vec3sub(gates[i].pos, backvec), 1) -- red smoke
--~ 		trigger.action.smoke(gates[i].br, 1) -- red smoke
--~ 		trigger.action.smoke(gates[i].bl, 4) -- blue smoke
--~ 		trigger.action.smoke(gates[i].limitu, 0) -- red smoke
--~ 		trigger.action.outText("smoke " .. i, 1, false)
	end
end

init()
