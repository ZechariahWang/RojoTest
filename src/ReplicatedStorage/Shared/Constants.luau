local Constants = {}

-- ROUND
Constants.MIN_PLAYERS = 2
Constants.INTERMISSION_TIME = 10
Constants.REVEAL_TIME = 6 -- post-teleport grace: announce burner, let players position. No damage.
Constants.ROUND_TIME = 90
Constants.END_TIME = 5

-- STAGES (within Round phase)
Constants.STAGE_DURATION = 30
Constants.STAGE_COUNT = 3

-- INFECTION
Constants.NEW_BURNER_GRACE = 1.0

-- FIRE ATTACK (active flamethrower from burners)
Constants.FIRE_CONE_RANGE = 14            -- studs
Constants.FIRE_CONE_HALF_ANGLE = 35       -- degrees, ~70° total spread
Constants.FIRE_DAMAGE_PER_SEC = 18
Constants.FIRE_FUEL_MAX = 3.0             -- seconds of continuous fire
Constants.FIRE_FUEL_REGEN_PER_SEC = 1.0
Constants.FIRE_FUEL_MIN_TO_START = 0.3    -- prevents tap-spam at empty

-- DAMAGE (passive hazard — trail walls, ignited parts)
Constants.HAZARD_DAMAGE_PER_SEC = 5

-- TRAIL (Stage 2+)
Constants.TRAIL_DURATION = 5
Constants.TRAIL_RADIUS = 3 -- distance from wall surface that still counts as "touching"
Constants.TRAIL_WALL_HEIGHT = 6
Constants.TRAIL_WALL_THICKNESS = 0.6
Constants.TRAIL_SEGMENT_MIN_LENGTH = 1.5 -- min movement before dropping a new wall segment
Constants.TRAIL_SEGMENT_MAX_LENGTH = 10 -- larger movement (teleport / dash skip) drops no segment

-- IGNITE (Stage 3)
Constants.IGNITE_RADIUS = 5

-- FIREPROOF FLAG (BoolValue child on a part — set Value = true to opt out of ignition)
Constants.FIREPROOF_FLAG_NAME = "Fireproof"

-- MOVEMENT
Constants.SAFE_WALKSPEED = 16
Constants.BURNING_WALKSPEED = 20

-- DASH
Constants.DASH_COOLDOWN = 3
Constants.DASH_DURATION = 0.2
Constants.DASH_VELOCITY = 60

-- PLAYER STATES
Constants.STATE_LOBBY = "Lobby"
Constants.STATE_SAFE = "Safe"
Constants.STATE_BURNING = "Burning"

-- ROUND PHASES
Constants.PHASE_LOBBY = "Lobby"
Constants.PHASE_INTERMISSION = "Intermission"
Constants.PHASE_REVEAL = "Reveal"
Constants.PHASE_ROUND = "Round"
Constants.PHASE_END = "End"

-- END REASONS
Constants.REASON_SURVIVED = "Survived"
Constants.REASON_ALL_INFECTED = "AllInfected"
Constants.REASON_ABORTED = "Aborted"

return Constants
