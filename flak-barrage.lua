local PI = math.pi
local random = math.random
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt

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
  trigger.action.explosion(firevec3, 9)
  return time + (60/roundsPerMinute)
end
