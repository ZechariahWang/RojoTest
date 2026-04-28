local Constants = {}

-- ROUND
Constants.MIN_PLAYERS = 2
Constants.INTERMISSION_TIME = 10
Constants.ROUND_TIME = 90
Constants.END_TIME = 5

-- STAGES (within Round phase)
Constants.STAGE_DURATION = 30
Constants.STAGE_COUNT = 3

-- INFECTION
Constants.INFECTION_RADIUS = 8
Constants.NEW_BURNER_GRACE = 1.0

-- DAMAGE
Constants.BURNER_DAMAGE_PER_SEC = 10
Constants.HAZARD_DAMAGE_PER_SEC = 5

-- TRAIL (Stage 2+)
Constants.TRAIL_DURATION = 5
Constants.TRAIL_EMIT_INTERVAL = 0.25
Constants.TRAIL_RADIUS = 4

-- IGNITE (Stage 3)
Constants.IGNITE_DURATION = 5
Constants.IGNITE_RADIUS = 4

-- TAGS
Constants.TAG_FIREPROOF = "Fireproof"

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
Constants.PHASE_ROUND = "Round"
Constants.PHASE_END = "End"

-- END REASONS
Constants.REASON_SURVIVED = "Survived"
Constants.REASON_ALL_INFECTED = "AllInfected"
Constants.REASON_ABORTED = "Aborted"

return Constants
