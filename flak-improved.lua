-- WW2 Flak Simulation Script by Chuzuki
--
-- Put this script in a "Mission Start" trigger
-- Create a trigger zone to barrage with flak, named eg. "FlakZone1"
-- This is intended to be used with the "Switched Condition" trigger,
--   with "Part of Coalition in Zone" to start and "All of Coalition Out of Zone"
--   to end, though any discrete start and end events will work.
-- Do not use with "Continuous Action" triggers; they will start more barrages
--   than you intend.
-- Rounds per minute is the combined fire rate of all simulated "guns"
--   A single 8.8cm Flak 36 had a fire rate of 15-20 rounds per minute,
--   so multiply accordingly, eg. 180 RPM is roughly equivalent to 12 Flak 36s
--
-- Start a barrage by calling:
--   startBarrage("FlakZone1", minAlt, maxAlt, roundsPerMinute)
--   minAlt and maxAlt are limits in meters
-- End the barrage by calling:
--   endBarrage("FlakZone1")
--
-- Start continuously pointed fire by calling:
--   startContinuous("FlakZone1", targetCoalition, skill, roundsPerMinute, [closestOnly])
--   targetCoalition is the team color to shoot at, eg. "red" or "blue"
--   skill determines accuracy, "low", "med", or "high"
--   closestOnly optional, set to true to fire continuously only at the closest target
--     leave blank or set to false to spread fire among all targets
-- End it manually by calling:
--   endContinuous("FlakZone1")
--
-- Start concentrated prediction fire by calling:
--   startConcentrated("FlakZone1", targetCoalition, skill, roundsPerBurst, delay)
--   targetCoalition is the team color to shoot at, eg. "red" or "blue"
--   skill determines accuracy, "low", "med", or "high"
--   roundsPerBurst is how many guns will shoot at the single target in one
--     concentrated burst
--   delay is seconds between bursts
-- End it manually by calling:
--   endConcentrated("FlakZone1")

local _debug = false
local debugText = nil
if _debug then
  debugText = trigger.action.outText
else
  debugText = function() end
end

muzzleVelocity = 820 -- m/s
minRange = 1000 -- minimum fusing distance
maxRange = 8000
shellStrength = 9 -- explosive power of flak shells

-- random deviation by skill in meters
lowDev = 40
medDev = 25
highDev = 15

local G = 9.81 -- m/s^2
local PI = math.pi
local random = math.random
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt

function explode(params, time)
  trigger.action.explosion(params["position"], shellStrength)
  return nil
end

function getDistance(a, b)
  local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
  return sqrt(x*x+y*y+z*z)
end

function vec3mag(a)
  return getDistance(a, {["x"] = 0, ["y"] = 0, ["z"] = 0})
end

-- Subtract vector b from vector a
function vec3sub(a, b)
  return {
    ["x"] = a.x-b.x,
    ["y"] = a.y-b.y,
    ["z"] = a.z-b.z
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

function leadPrediction(targetPos, targetVel, targetAcc, travelTime)
  local dx = travelTime * (targetVel.x + targetAcc.x * travelTime / 2)
  local dy = travelTime * (targetVel.y + targetAcc.y * travelTime / 2)
  local dz = travelTime * (targetVel.z + targetAcc.z * travelTime / 2)
  return {
    ["x"] = targetPos.x + dx,
    ["y"] = targetPos.y + dy,
    ["z"] = targetPos.z + dz
  }
end

function skillDeviation(firePos, targetDist, skill)
  if skill == "low" then
    dev = lowDev
  elseif skill == "med" then
    dev = medDev
  elseif skill == "high" then
    dev = highDev
  end

  dev = dev * (targetDist / maxRange)

  return {
    ["x"] = firePos.x + (dev * random(-dev, dev)),
    ["y"] = firePos.y + (dev * random(-dev, dev)),
    ["z"] = firePos.z + (dev * random(-dev, dev))
  }
end

-- Probably want to start this on a Switched Condition,
--   Part of Coalition in Zone
local concentratedIDs = {}
function startConcentrated(zoneName, targetCoalition, skill, roundsPerBurst, delay)
  if targetCoalition == "blue" then
    targetCoalition = 2
  elseif targetCoalition == "red" then
    targetCoalition = 1
  else -- neutral
    targetCoalition = 0
  end

  concentratedIDs[zoneName] = -1
  concentratedIDs[zoneName] = timer.scheduleFunction(
    concentrated_prediction,
    {
      ["zoneName"] = zoneName,
      ["targetCoalition"] = targetCoalition,
      ["skill"] = skill,
      ["roundsPerBurst"] = roundsPerBurst,
      ["delay"] = delay
    },
    timer.getTime() + 1
  )
  debugText(string.format(
    "Starting concentrated fire ID: %i in zone %s",
    concentratedIDs[zoneName],
    zoneName
  ), 5)
end

function endConcentrated(zoneName)
  if concentratedIDs[zoneName] ~= nil then
    debugText(string.format(
      "Ending concentrated fire ID: %i in zone %s",
      concentratedIDs[zoneName],
      zoneName
    ), 5)
    timer.removeFunction(concentratedIDs[zoneName])
    concentratedIDs[zoneName] = nil
  end
end

local conc_tgtLastVels = {} -- concentrated target last velocities
local conc_tgtLastTimes = {} -- concentrated target last velocity timestamps
function concentrated_prediction(params, time)
  local zoneName = params["zoneName"]
  local targetCoalition = params["targetCoalition"]
  local skill = params["skill"]
  local roundsPerBurst = params["roundsPerBurst"]
  local delay = params["delay"]

  local zone = trigger.misc.getZone(zoneName)
  local volS = {
    id = world.VolumeType.SPHERE,
    params = {
      point = zone.point,
      radius = zone.radius
    }
   }

  local target = nil
  local targetDist = math.huge
  local range = math.huge
  world.searchObjects(Object.Category.UNIT, volS, function(foundUnit, val)
    if foundUnit:getCoalition() == targetCoalition then
      if foundUnit:inAir() and foundUnit:getLife() > 1 then
        debugText("Found: " .. foundUnit:getName() .. " ID: " .. foundUnit:getID(), 3)
        if conc_tgtLastVels[foundUnit:getID()] == nil then
          conc_tgtLastVels[foundUnit:getID()] = foundUnit:getVelocity() -- init
          conc_tgtLastTimes[foundUnit:getID()] = timer.getTime() -- init
        end
        range = getDistance(foundUnit:getPoint(), zone.point)
        if range < targetDist then -- find closest target to shoot first
          targetDist = range
          target = foundUnit
        end
      end
    end
    return true
  end)
  if target ~= nil then
    local targetPos = target:getPoint()
    if targetDist > minRange and targetDist < maxRange then
      local targetID = target:getID()
      local deltaT = timer.getTime() - conc_tgtLastTimes[targetID]
      local targetVel = target:getVelocity()
      local targetAcc = vec3div(
        vec3sub(targetVel, conc_tgtLastVels[targetID]),
        deltaT
      )
      debugText(
        string.format("%s V: %3.2f kt A: %3.2f kt/s dT: %1.2fs",
          target:getName(),
          vec3mag(targetVel) * 1.94384, -- m/s to knots
          vec3mag(targetAcc) * 1.94384,
          deltaT
        ),
        1
      )
      conc_tgtLastVels[targetID] = targetVel
      conc_tgtLastTimes[targetID] = timer.getTime()
      local targetHeight = targetPos.y - zone.point.y
      -- technically muzzleVelocity - (sqrt(2 * G * targetHeight) / 2)
      -- go a little slower until we can estimate air resistance
      local averageShellVel =  muzzleVelocity - sqrt(2 * G * targetHeight)
      local travelTime = targetDist / averageShellVel
      local firePos = leadPrediction(targetPos, targetVel, targetAcc, travelTime)
      debugText(
        "Burst at " .. target:getName() .. " arriving in: " ..
        string.format("%2.2fs at %4.2f m/s", travelTime, averageShellVel)
        , 1)
      for i = 1, roundsPerBurst do
        timer.scheduleFunction(
          explode,
          {
            ["position"] = skillDeviation(firePos, targetDist, skill)
          },
          timer.getTime() + travelTime - 0.2 * random() -- more human-like
        )
      end
    end
    return time + delay
  else
    return nil -- no more targets, quit
  end
end

-- Probably want to start this on a Switched Condition,
--   Part of Coalition in Zone
local continuousIDs = {}
function startContinuous(zoneName, targetCoalition, skill, roundsPerMinute, closestOnly)
  if targetCoalition == "blue" then
    targetCoalition = 2
  elseif targetCoalition == "red" then
    targetCoalition = 1
  else -- neutral
    targetCoalition = 0
  end
  debugText(targetCoalition, 5)

  continuousIDs[zoneName] = -1
  continuousIDs[zoneName] = timer.scheduleFunction(
    continuously_pointed,
    {
      ["zoneName"] = zoneName,
      ["targetCoalition"] = targetCoalition,
      ["skill"] = skill,
      ["roundsPerMinute"] = roundsPerMinute,
      ["closestOnly"] = closestOnly or false -- default to shoot everyone
    },
    timer.getTime() + 1
  )
  debugText(string.format(
    "Starting continuous fire ID: %i in zone %s",
    continuousIDs[zoneName],
    zoneName
  ), 5)
end

function endContinuous(zoneName)
  if continuousIDs[zoneName] ~= nil then
    debugText(string.format(
      "Ending continuous fire ID: %i in zone %s",
      continuousIDs[zoneName],
      zoneName
    ), 5)
    timer.removeFunction(continuousIDs[zoneName])
    continuousIDs[zoneName] = nil
  end
end

local cont_tgtLastVels = {} -- continuous target last velocities
local cont_tgtLastTimes = {} -- continuous target last velocity timestamps
function continuously_pointed(params, time)
  local zoneName = params["zoneName"]
  local targetCoalition = params["targetCoalition"]
  local skill = params["skill"]
  local roundsPerMinute = params["roundsPerMinute"]
  local closestOnly = params["closestOnly"]

  local zone = trigger.misc.getZone(zoneName)
  local volS = {
    id = world.VolumeType.SPHERE,
    params = {
      point = zone.point,
      radius = zone.radius
    }
   }
  local targets = {}
  local target = nil
  local targetPos = nil
  local targetDist = math.huge
  local range = math.huge
  world.searchObjects(Object.Category.UNIT, volS, function(foundUnit, val)
    debugText("Found: " .. foundUnit:getName() .. " ID: " .. foundUnit:getID(), 3)
    if foundUnit:getCoalition() == targetCoalition then
      if foundUnit:inAir() and foundUnit:getLife() > 1 then
        debugText("Found: " .. foundUnit:getName() .. " ID: " .. foundUnit:getID(), 3)
        targets[#targets + 1] = foundUnit
        if cont_tgtLastVels[foundUnit:getID()] == nil then
          cont_tgtLastVels[foundUnit:getID()] = foundUnit:getVelocity() -- init
          cont_tgtLastTimes[foundUnit:getID()] = timer.getTime() -- init
        end
        if closestOnly then
          range = getDistance(foundUnit:getPoint(), zone.point)
          if range < targetDist then -- find closest target to shoot first
            targetDist = range
            target = foundUnit
          end
        end
      end
    end
    return true
  end)
  for i = 1, #targets do
    if closestOnly == false then
      target = targets[i] -- divide up targets
      targetPos = target:getPoint()
      targetDist = getDistance(targetPos, zone.point)
    else
      targetPos = target:getPoint()
    end
    if targetDist > minRange and targetDist < maxRange then
      local targetID = target:getID()
      local deltaT = timer.getTime() - cont_tgtLastTimes[targetID]
      local targetVel = target:getVelocity()
      local targetAcc = vec3div(
        vec3sub(targetVel, cont_tgtLastVels[targetID]),
        deltaT
      )
      debugText(
        string.format("%s V: %3.2f kt A: %3.2f kt/s dT: %1.2fs",
          target:getName(),
          vec3mag(targetVel) * 1.94384, -- m/s to knots
          vec3mag(targetAcc) * 1.94384,
          deltaT
        ),
        1
      )
      cont_tgtLastVels[targetID] = targetVel
      cont_tgtLastTimes[targetID] = timer.getTime()
      local targetHeight = targetPos.y - zone.point.y
      -- technically muzzleVelocity - (sqrt(2 * G * targetHeight) / 2)
      -- go a little slower until we can estimate air resistance
      local averageShellVel =  muzzleVelocity - sqrt(2 * G * targetHeight)
      local travelTime = targetDist / averageShellVel
      local firePos = leadPrediction(targetPos, targetVel, targetAcc, travelTime)
      debugText(
        "Shot at " .. target:getName() .. " arriving in: " ..
        string.format("%2.2fs at %4.2f m/s", travelTime, averageShellVel)
        , 1)
      timer.scheduleFunction(
        explode,
        {
          ["position"] = skillDeviation(firePos, targetDist, skill)
        },
        timer.getTime() + travelTime - 0.2 * random() -- more human-like
      )
    end
    if closestOnly then break end
  end
  if #targets > 0 then
    if closestOnly then
      return time + ((60/roundsPerMinute))
    else
      return time + ((60/roundsPerMinute) * #targets)
    end
  else
    return nil -- no more targets, quit
  end
end

local barrageIDs = {}
function startBarrage(zoneName, minAlt, maxAlt, roundsPerMinute)
  barrageIDs[zoneName] = -1
  barrageIDs[zoneName] = timer.scheduleFunction(
    barrage,
    {
      ["zoneName"] = zoneName,
      ["minAlt"] = minAlt,
      ["maxAlt"] = maxAlt,
      ["roundsPerMinute"] = roundsPerMinute
    },
    timer.getTime() + 1
  )
  debugText(string.format(
    "Starting barrage ID: %i in zone %s",
    barrageIDs[zoneName],
    zoneName
  ), 5)
end

function endBarrage(zoneName)
  if barrageIDs[zoneName] ~= nil then
    debugText(string.format(
      "Ending barrage ID: %i in zone %s",
      barrageIDs[zoneName],
      zoneName
    ), 5)
    timer.removeFunction(barrageIDs[zoneName])
    barrageIDs[zoneName] = nil
  end
end

function barrage(params, time)

  local zoneName = params["zoneName"]
  local minAlt = params["minAlt"]
  local maxAlt = params["maxAlt"]
  local roundsPerMinute = params["roundsPerMinute"]

  local zone = trigger.misc.getZone(zoneName)

  --get a random point in the zone
  local t = 2 * PI * random()
  local r = random()

  --taking into account terrain height generate a vec3 position at the
  -- random point in the zone at a random altitude
  local firevec3 = {
    x = zone.point.x + (zone.radius * r * cos(t)),
    y = land.getHeight(zone.point) + random(minAlt, maxAlt),
    z = zone.point.z + (zone.radius * r * sin(t))
  }

  -- create a single flak explosion at the position
  trigger.action.explosion(firevec3, shellStrength)
  return time + (60/roundsPerMinute)
end
