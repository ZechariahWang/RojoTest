local Constants = {}

-- ROUND
Constants.MIN_PLAYERS = 2
Constants.INTERMISSION_TIME = 10
Constants.ROUND_TIME = 90
Constants.END_TIME = 5

-- INFECTION
Constants.INFECTION_RADIUS = 8
Constants.INFECTION_TIME = 0.6
Constants.INFECTION_DECAY_RATE = 1.5
Constants.NEW_BURNER_GRACE = 1.0

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
