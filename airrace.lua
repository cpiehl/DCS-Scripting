-- DO SCRIPT FILE on mission start
-- place pairs of pylons named like "GateLeft01" and "GateRight01"

local gateDepth = 30 -- meters
local timerResDist2 = 200^2 -- meters squared

local upvec = {
	['x'] = 0,
	['y'] = 1,
	['z'] = 0
}

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

-- server init players (mostly for singleplayer)
local playersNextGate = {}
for key,value in pairs(coalition.getPlayers(2)) do -- blue
	playersNextGate[value:getName()] = 1
end

local playerGateEventHandler = {}
function playerGateEventHandler:onEvent(event)
	if event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
		trigger.action.outText(event.initiator:getName() .. " entered " .. event.initiator:getTypeName(), 1, false)
		playersNextGate[event.initiator:getName()] = 1
	elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
		playersNextGate[event.initiator:getName()] = nil
		trigger.action.outText(event.initiator:getName() .. " left " .. event.initiator:getTypeName(), 1, false)
	end
end
world.addEventHandler(playerGateEventHandler)

-- init gate locations
local staticObjects = coalition.getStaticObjects(2) -- blue
local gates = {}
local playersLapTime = {}
local playersPenaltyTime = {}
local name, gateNum

for i = 1, #staticObjects do
	if staticObjects[i]:getTypeName() == "Airshow_Cone" then
		name = staticObjects[i]:getName()
		gateNum = tonumber(name:sub(#name - 1))
		gateSide = name:sub(5, 5)
--~ 		trigger.action.outText(staticObjects[i]:getTypeName() .. " " .. name .. " " .. gateNum .. " " .. gateSide, 1, false)
		if gates[gateNum] == nil then
			gates[gateNum] = {}
			gates[gateNum].desc = staticObjects[i]:getDesc()
		end
		if gateSide == "R" then
			gates[gateNum]["right"] = staticObjects[i]:getPoint()
		else
			gates[gateNum]["left"] = staticObjects[i]:getPoint()
		end
	end
end

for i = 1, #gates do
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

--~ 	trigger.action.smoke(vec3sub(gates[i].pos, backvec), 1) -- red smoke
--~ 	trigger.action.smoke(gates[i].br, 1) -- red smoke
--~ 	trigger.action.smoke(gates[i].bl, 4) -- blue smoke
--~ 	trigger.action.smoke(gates[i].limitu, 0) -- red smoke
--~ 	trigger.action.outText("smoke " .. i, 1, false)
end

function outputStartLap(playerName)
	trigger.action.outText(playerName .. " Lap Start!", 1, false)
end

function outputEndLap(playerName)
	trigger.action.outText(string.format(
		"%s Time (Penalty): %3.1f (%d s)",
		playerName,
		timer.getTime() - playersLapTime[playerName] + playersPenaltyTime[playerName],
		playersPenaltyTime[playerName]
	), 5, false)
end

function outputGatePassed(playerName, nextGateNum)
	trigger.action.outText(playerName .. " passed Gate #" .. nextGateNum, 1, false)
end

function outputGatePenalty(playerName, nextGateNum)
	trigger.action.outText(playerName .. " +2s penalty Gate #" .. nextGateNum, 1, false)
end

function inGateBounds(playerName, nextGateNum)
	local f, r, l, b, n, pos
	n = nextGateNum
	pos = Unit.getByName(playerName):getPoint()

	f = vec3cross(vec3sub(pos, gates[n].left), gates[n].fvec)
	r = vec3cross(vec3sub(pos, gates[n].right), gates[n].rvec)
	b = vec3cross(vec3sub(pos, gates[n].br), gates[n].bvec)
	l = vec3cross(vec3sub(pos, gates[n].bl), gates[n].lvec)

	-- are all cross products the same sign?
	if (f.y > 0 and r.y > 0 and l.y > 0 and b.y > 0) or (f.y < 0 and r.y < 0 and l.y < 0 and b.y < 0) then
		if (gates[n].y < pos.y) then
			return 1 -- passed with penalty
		end
		return 2 -- passed without penalty
	end
	return 0

--~ 	return getDistance2(pos, gates[nextGateNum].pos) < gates[nextGateNum].rad2
end

function checkGates(params, time)
	local gateStatus, interval
	for playerName, nextGateNum in pairs(playersNextGate) do
		gateStatus = inGateBounds(playerName, nextGateNum)
		if gateStatus > 0 then
			if playersNextGate[playerName] == 1 and gateStatus == 2 then -- start lap
				playersLapTime[playerName] = timer.getTime()
				playersPenaltyTime[playerName] = 0
				outputStartLap(playerName)
			elseif gateStatus == 2 then -- passed without penalty
				outputGatePassed(playerName, nextGateNum)
			else -- passed with penalty
				outputGatePenalty(playerName, nextGateNum)
				playersPenaltyTime[playerName] = playersPenaltyTime[playerName] + 2
			end
			playersNextGate[playerName] = playersNextGate[playerName] + 1
			if playersNextGate[playerName] > #gates then
				playersNextGate[playerName] = 1 -- restart lap
				outputEndLap(playerName)
			end
		end
	end
--~ 	if getDistance2(Unit.getByName(playerName):getPoint(), gates[nextGateNum].pos) < timerResDist2 then
--~ 		trigger.action.outText("High Resolution Update Mode", 1, false)
--~ 		interval = 0.1
--~ 	else
--~ 		trigger.action.outText("Low Resolution Update Mode", 1, false)
--~ 		interval = 1
--~ 	end
--~ 	return time + interval
	return time + 0.1
end
timer.scheduleFunction(checkGates, 0, timer.getTime() + 1)
