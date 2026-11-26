--!strict
-- Runs the headless acceptance tests at the start of a Studio playtest and prints the results.
-- Never runs on a live server.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SimTests = require(ServerStorage:WaitForChild("Tests"):WaitForChild("SimTests"))

local ok, results = pcall(SimTests.run, ReplicatedStorage:WaitForChild("Shared"))
if not ok then
	warn(`[SimTests] crashed: {results}`)
	return
end

local failed = 0
for _, line in results do
	if string.sub(line, 1, 4) == "FAIL" then
		failed += 1
		warn(`[SimTests] {line}`)
	else
		print(`[SimTests] {line}`)
	end
end
print(`[SimTests] done: {#results - failed} passed, {failed} failed`)
