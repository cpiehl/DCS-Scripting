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
--   startBarrage("FlakZone1", gunType, numOfGuns, minAlt, maxAlt)
--   gunType is the type of gun, eg. "flak88", "oerlikon35", "bofors40", etc
--   minAlt and maxAlt are limits in meters
-- End the barrage by calling:
--   endBarrage("FlakZone1")
--
-- Start continuously pointed fire by calling:
--   startContinuous("FlakZone1", gunType, numOfGuns, targetCoalition, skill, [closestOnly])
--   gunType is the type of gun, eg. "flak88", "oerlikon35", "bofors40", etc
--   targetCoalition is the team color to shoot at, eg. "red" or "blue"
--   skill determines accuracy, "low", "med", or "high"
--   closestOnly optional, set to true to fire continuously only at the closest target
--     leave blank or set to false to spread fire among all targets
-- End it manually by calling:
--   endContinuous("FlakZone1")
--
-- Start concentrated prediction fire by calling:
--   startConcentrated("FlakZone1", gunType, numOfGuns, targetCoalition, skill, delay)
--   gunType is the type of gun, eg. "flak88", "oerlikon35", "bofors40", etc
--   numOfGuns determines how many guns will fire in a single concentrated burst
--   targetCoalition is the team color to shoot at, eg. "red" or "blue"
--   skill determines accuracy, "low", "med", or "high"
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

local gunData = {
  ["flak88"] = {
    ["muzzleVel"] = 840,  -- m/s
    ["minRange"] = 1000,  -- minimum fusing distance in meters
    ["maxRange"] = 8000,
    ["roundsPerMin"] = 20,
    ["shellStrength"] = 9 -- explosive power of shells
  },
  ["flak105"] = {
    ["muzzleVel"] = 880,
    ["minRange"] = 1000,
    ["maxRange"] = 9500,
    ["roundsPerMin"] = 15,
    ["shellStrength"] = 10
  },
  ["oerlikon35"] = {
    ["muzzleVel"] = 1175,
    ["minRange"] = 1000,
    ["maxRange"] = 4000,
    ["roundsPerMin"] = 550,
    ["shellStrength"] = 3
  },
  ["bofors40"] = {
    ["muzzleVel"] = 880,
    ["minRange"] = 1000,
    ["maxRange"] = 7200,
    ["roundsPerMin"] = 120,
    ["shellStrength"] = 5
  }
}

-- random deviation by skill in meters
local lowDev = 40
local medDev = 25
local highDev = 15

local Gx2 = 9.81 * 2 -- m/s^2 -- why not save the operations?
local PIx2 = math.pi * 2
local random = math.random
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt

function explode(params, time)
  trigger.action.explosion(params["position"], params["shellStrength"])
  return nil
end

-- returns distance squared, sqrt() later if you really need it
function getDistance2(a, b)
  local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
  return x*x + y*y + z*z
end

function vec3mag(a)
  return sqrt(getDistance2(a, {["x"] = 0, ["y"] = 0, ["z"] = 0}))
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

function skillDeviation(firePos, targetDist, gunType, skill)
  if skill == "low" then
    dev = lowDev  -- replace these with per-gun deviations if wanted
  elseif skill == "med" then
    dev = medDev  -- gunData[gunType].medDev
  elseif skill == "high" then
    dev = highDev  -- gunData[gunType].highDev
  end

  dev = dev * (targetDist / gunData[gunType].maxRange)

  return {
    ["x"] = firePos.x + (dev * random(-dev, dev)),
    ["y"] = firePos.y + (dev * random(-dev, dev)),
    ["z"] = firePos.z + (dev * random(-dev, dev))
  }
end

-- Probably want to start this on a Switched Condition,
--   Part of Coalition in Zone
local concentratedIDs = {}
function startConcentrated(zoneName, gunType, numOfGuns, targetCoalition, skill, delay)
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
      ["gunType"] = gunType,
      ["numOfGuns"] = numOfGuns,
      ["targetCoalition"] = targetCoalition,
      ["skill"] = skill,
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
  local gunType = params["gunType"]
  local numOfGuns = params["numOfGuns"]
  local targetCoalition = params["targetCoalition"]
  local skill = params["skill"]
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
  local targetDist2 = math.huge  -- squared ranges, sqrt() later if needed
  local range2 = math.huge
  world.searchObjects(Object.Category.UNIT, volS, function(foundUnit, val)
    if foundUnit:getCoalition() == targetCoalition then
      if foundUnit:inAir() and foundUnit:getLife() > 1 then
        debugText("Found: " .. foundUnit:getName() .. " ID: " .. foundUnit:getID(), 3)
        if conc_tgtLastVels[foundUnit:getID()] == nil then
          conc_tgtLastVels[foundUnit:getID()] = foundUnit:getVelocity() -- init
          conc_tgtLastTimes[foundUnit:getID()] = timer.getTime() -- init
        end
        range2 = getDistance2(foundUnit:getPoint(), zone.point)
        if range2 < targetDist2 then -- find closest target to shoot first
          targetDist2 = range2
          target = foundUnit  -- save this for later
        end
      end
    end
    return true
  end)
  if target ~= nil then
    local targetDist = sqrt(targetDist2)
    local targetPos = target:getPoint()
    if targetDist > gunData[gunType].minRange and targetDist < gunData[gunType].maxRange then
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
      local averageShellVel = gunData[gunType].muzzleVel - sqrt(Gx2 * targetHeight)
      local travelTime = targetDist / averageShellVel
      local firePos = leadPrediction(targetPos, targetVel, targetAcc, travelTime)
      debugText(
        "Burst at " .. target:getName() .. " arriving in: " ..
        string.format("%2.2fs at %4.2f m/s", travelTime, averageShellVel)
        , 1)
      for i = 1, numOfGuns do
        timer.scheduleFunction(
          explode,
          {
            ["position"] = skillDeviation(firePos, targetDist, gunType, skill),
            ["shellStrength"] = gunData[gunType].shellStrength
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
function startContinuous(zoneName, gunType, numOfGuns, targetCoalition, skill, closestOnly)
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
      ["gunType"] = gunType,
      ["numOfGuns"] = numOfGuns,
      ["targetCoalition"] = targetCoalition,
      ["skill"] = skill,
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
  local gunType = params["gunType"]
  local numOfGuns = params["numOfGuns"]
  local targetCoalition = params["targetCoalition"]
  local skill = params["skill"]
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
  local targetDist2 = math.huge  -- squared ranges, sqrt() later if needed
  local range2 = math.huge
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
          range2 = getDistance2(foundUnit:getPoint(), zone.point)
          if range2 < targetDist2 then -- find closest target to shoot first
            targetDist2 = range2
            target = foundUnit  -- save this for later
          end
        end
      end
    end
    return true
  end)
  for i = 1, #targets do
    if closestOnly == false then
      target = targets[i] -- divide up targets
    end
    local targetPos = target:getPoint()
    local targetDist = sqrt(getDistance2(targetPos, zone.point))
    if targetDist > gunData[gunType].minRange and targetDist < gunData[gunType].maxRange then
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
      local averageShellVel =  gunData[gunType].muzzleVel - sqrt(Gx2 * targetHeight)
      local travelTime = targetDist / averageShellVel
      local firePos = leadPrediction(targetPos, targetVel, targetAcc, travelTime)
      debugText(
        "Shot at " .. target:getName() .. " arriving in: " ..
        string.format("%2.2fs at %4.2f m/s", travelTime, averageShellVel)
        , 1)
      timer.scheduleFunction(
        explode,
        {
          ["position"] = skillDeviation(firePos, targetDist, gunType, skill),
          ["shellStrength"] = gunData[gunType].shellStrength
        },
        timer.getTime() + travelTime - 0.2 * random() -- more human-like
      )
    end
    if closestOnly then break end
  end
  if #targets > 0 then
    if closestOnly then
      return time + (60 / (gunData[gunType].roundsPerMin * numOfGuns))
    else
      return time + ((60 / (gunData[gunType].roundsPerMin * numOfGuns)) * #targets)
    end
  else
    return nil -- no more targets, quit
  end
end

local barrageIDs = {}
function startBarrage(zoneName, gunType, numOfGuns, minAlt, maxAlt)
  barrageIDs[zoneName] = -1
  barrageIDs[zoneName] = timer.scheduleFunction(
    barrage,
    {
      ["zoneName"] = zoneName,
      ["gunType"] = gunType,
      ["numOfGuns"] = numOfGuns,
      ["minAlt"] = minAlt,
      ["maxAlt"] = maxAlt
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
  local gunType = params["gunType"]
  local numOfGuns = params["numOfGuns"]
  local minAlt = params["minAlt"]
  local maxAlt = params["maxAlt"]

  local zone = trigger.misc.getZone(zoneName)

  --get a random point in the zone
  local t = PIx2 * random()
  local r = random()

  --taking into account terrain height generate a vec3 position at the
  -- random point in the zone at a random altitude
  local firevec3 = {
    x = zone.point.x + (zone.radius * r * cos(t)),
    y = land.getHeight(zone.point) + random(minAlt, maxAlt),
    z = zone.point.z + (zone.radius * r * sin(t))
  }

  -- create a single flak explosion at the position
  trigger.action.explosion(firevec3, gunData[gunType].shellStrength)
  return time + (60 / (gunData[gunType].roundsPerMin * numOfGuns))
end
