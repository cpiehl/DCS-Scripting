-- WW2 Flak Simulation Script by Chuzuki
--
-- Put this script in a "Mission Start" trigger
-- Create a trigger zone to barrage with flak, named eg. "FlakZone1"
-- Rounds per minute is the combined fire rate of all simulated "guns"
--   A single 8.8cm Flak 36 had a fire rate of 15-20 rounds per minute,
--   so multiply accordingly, eg. 180 RPM is roughly equivalent to 12 Flak 36s
--
-- Start a barrage with conditions of your choice by calling:
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
-- End it by calling:
--   endContinuous("FlakZone1")
--
-- Start concentrated prediction fire by calling:
--   startConcentrated("FlakZone1", targetCoalition, skill, roundsPerBurst, delay)
--   targetCoalition is the team color to shoot at, eg. "red" or "blue"
--   skill determines accuracy, "low", "med", or "high"
--   roundsPerBurst is how many guns will shoot at the single target in one
--     concentrated burst
--   delay is seconds between bursts
-- End it by calling:
--   endConcentrated("FlakZone1")

muzzleVelocity = 820 -- m/s
minRange = 1000 -- minimum fusing distance
maxRange = 8000
shellStrength = 9 -- explosive power of flak shells

-- random deviation by skill in meters
lowDev = 30
medDev = 20
highDev = 10

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

function leadPrediction(targetPos, targetVel, travelTime)
  local dx = targetVel.x * travelTime
  local dy = targetVel.y * travelTime
  local dz = targetVel.z * travelTime
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
end

function endConcentrated(zoneName)
  timer.removeFunction(concentratedIDs[zoneName])
end

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
      local targetVel = target:getVelocity()
      local travelTime = targetDist / muzzleVelocity
      local firePos = leadPrediction(targetPos, targetVel, travelTime)
      for i = 1, roundsPerBurst do
        firePos = skillDeviation(firePos, targetDist, skill)
        timer.scheduleFunction(
          explode,
          {
            ["position"] = firePos
          },
          timer.getTime() + travelTime
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
end

function endContinuous(zoneName)
  timer.removeFunction(continuousIDs[zoneName])
end

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
    if foundUnit:getCoalition() == targetCoalition then
      if foundUnit:inAir() and foundUnit:getLife() > 1 then
        targets[#targets + 1] = foundUnit
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
      local targetVel = Unit.getVelocity(target)
      local travelTime = targetDist / muzzleVelocity
      local firePos = leadPrediction(targetPos, targetVel, travelTime)
      firePos = skillDeviation(firePos, targetDist, skill)
      timer.scheduleFunction(
        explode,
        {
          ["position"] = firePos
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
end

function endBarrage(zoneName)
  timer.removeFunction(barrageIDs[zoneName])
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
