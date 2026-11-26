local Config = {}
Config.Modes = { Solo = {count=1,label="Solo Challenge"}, Duel = {count=2,label="Head-to-Head"}, Triple = {count=3,label="Triple Showdown"} }
Config.QuestionsPerRound = 5
Config.Rounds = {{name="Round 1",base=1},{name="Round 2",base=1},{name="Round 3",base=1}}
Config.AnswerSeconds = 30
Config.MaxAnswerLength = 60
Config.Rarity = {
 common={label="Common",points=10,mult=1,order=1},
 too_clever={label="Too Clever",points=15,mult=1.5,order=1.5}, -- Krillion's 15-pt tier ("Too clever")
 uncommon={label="Uncommon",points=30,mult=2,order=2},
 rare={label="Rare",points=60,mult=3,order=3},
 very_rare={label="Very Rare",points=85,mult=4,order=4},
 extremely_rare={label="Extremely Rare",points=100,mult=5,order=5},
}
Config.Typo = nil
Config.Tiebreak = {enabled=true,base=1,maxRounds=3}
Config.FinalWager = {enabled=false}
Config.Pacing = {intro=27,roundIntro=2,betweenQuestions=1,revealPerContestant=2.6,recap=3.5,roundTransition=5,tiebreakIntro=4,results=12}
-- Host voice pacing. Must match the client voice (Roblox "Host voice", VoiceId 11, Speed 1.0).
-- Times below were measured from the voice itself (AudioTextToSpeech TimeLength).
-- Durations below were measured in Studio for the exact intro lines; anything else is estimated.
Config.Pacing.hostBeat = 0.4
-- 1v1 / 1v1v1: seconds of winner celebration (trophy, confetti, victory dance) before the results card
Config.Pacing.celebrate = 8 -- the breath between host sentences
Config.Pacing.speechTimes = {
	["Hello, welcome to Clamillion!"] = 2.50,
	["Here's how it works. There are three rounds, with five questions in each round."] = 5.55,
	["You get thirty seconds to answer. If your answer isn't right, that's okay, just try again!"] = 7.04,
	["And here's the fun part. The rarer your answer, the more points you'll get!"] = 4.70,
	["Alright, let's meet our contestants!"] = 2.80,
}
function Config.Pacing.speechSeconds(text)
	return Config.Pacing.speechTimes[text] or (#text * 0.08 + 0.2)
end
-- Shop: in Studio every item counts as owned so you can try them all on.
Config.Shop = { unlockAllInStudio = true }
Config.IsStudio = game:GetService("RunService"):IsStudio()
Config.Studio = {fillWithBots=false}
return Config

