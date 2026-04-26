export type PlayerStateName = "Lobby" | "Safe" | "Burning"
export type RoundPhase = "Lobby" | "Intermission" | "Round" | "End"
export type EndReason = "Survived" | "AllInfected" | "Aborted"

export type RoundEndExtra = {
	winner: string?,
	reason: EndReason,
}

return {}
