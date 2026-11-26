local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Config=require(script.Parent.Parent.Config)
local Remotes=RS.Clamillion.Remotes
local Queue={}
-- Every lobby pad is its own little queue: fill a pad to start a show on it.
local pads={} -- list of pad parts
local pools={} -- pad -> {players}
local selected,last={},{} -- player -> pad
-- AFK guard: clients report when their player stops/starts touching the controls.
-- Idle players are never queued and never pulled into a show.
local idle={}
local standingOn={} -- player -> pad they're physically on (updated by the occupancy loop)
local deps
local goCool={} -- player -> last "take me to a pad" teleport
local function collectPads()
 pads={}
 for mode in pairs(Config.Modes) do
  local station=workspace.ShowLobby.ModeStations:FindFirstChild(mode)
  local folder=station and station:FindFirstChild("Pads")
  if folder then
   for _,pad in ipairs(folder:GetChildren()) do
    if pad:IsA("BasePart") then pad:SetAttribute("Mode",mode);table.insert(pads,pad);pools[pad]=pools[pad] or {} end
   end
  end
 end
 table.sort(pads,function(a,b) return a:GetFullName()<b:GetFullName() end)
end
local function modeOf(pad) return pad and pad:GetAttribute("Mode") end
local function remove(p)
 for _,pool in pairs(pools) do local i=table.find(pool,p); if i then table.remove(pool,i) end end
 selected[p]=nil
end
local function status(p)
 local pad=selected[p]
 local mode=modeOf(pad)
 local onPad=standingOn[p]
 return {type="Queue",inQueue=pad~=nil,mode=mode,pad=pad and pad:GetAttribute("PadIndex"),count=pad and #pools[pad] or 0,
 needed=mode and Config.Modes[mode].count or 1,inMatch=deps.isInMatch(p),
 idle=idle[p]==true and onPad~=nil,idleMode=onPad and modeOf(onPad)}
end
function Queue.broadcast()
 for _,p in Players:GetPlayers() do Remotes.MatchState:FireClient(p,status(p)) end
 local waiting={}
 for _,pad in ipairs(pads) do
  local mode=modeOf(pad)
  local n=#pools[pad]
  local needed=Config.Modes[mode].count
  waiting[mode]=(waiting[mode] or 0)+n
  pad:SetAttribute("Queued",n)
  local card=pad:FindFirstChild("PadStatus") and pad.PadStatus:FindFirstChild("Card")
  if card and card:FindFirstChild("Count") then
   if mode=="Solo" then card.Count.Text="HOP ON!"
   else card.Count.Text=("%d / %d"):format(n,needed)..(n>0 and " !" or "") end
  end
 end
 for mode,def in pairs(Config.Modes) do
  local station=workspace.ShowLobby.ModeStations:FindFirstChild(mode)
  if station then
   station:SetAttribute("Queued",waiting[mode] or 0)
   if mode~="Solo" then station.ModeSign.SurfaceGui.Body.Text=("PICK A PAD • %d PLAYERS PER PAD\n%d waiting right now!"):format(def.count,waiting[mode] or 0) end
  end
 end
end
function Queue.tryStart()
 for _,pad in ipairs(pads) do
  local pool=pools[pad]
  local mode=modeOf(pad)
  for i=#pool,1,-1 do if pool[i].Parent~=Players or idle[pool[i]] then selected[pool[i]]=nil;table.remove(pool,i) end end
  local needed=Config.Modes[mode].count
  while #pool>=needed do
   local picked={}
   for i=1,needed do picked[i]=table.remove(pool,1);selected[picked[i]]=nil end
   if not deps.start(picked,mode) then
    for _,p in picked do
     if p.Parent==Players then Remotes.MatchState:FireClient(p,{type="QueueError",text="Character is still loading. Step off and back onto the pad to retry."}) end
    end
   end
  end
 end
 Queue.broadcast()
end
function Queue.join(p,pad)
 local mode=modeOf(pad)
 if not mode or not Config.Modes[mode] or not pools[pad] or deps.isInMatch(p) or selected[p]==pad then return end
 if idle[p] then return end
 if last[p] and os.clock()-last[p]<0.5 then return end
 last[p]=os.clock()
 remove(p);selected[p]=pad;table.insert(pools[pad],p)
 Queue.tryStart()
end
function Queue.init(d)
 deps=d
 collectPads()
 local function spawnTarget(p) p.RespawnLocation=workspace.ShowLobby.LobbySpawn end
 Players.PlayerAdded:Connect(spawnTarget)
 for _,p in Players:GetPlayers() do spawnTarget(p) end
 Remotes.QueueRequest.OnServerEvent:Connect(function(p,mode)
  if mode==nil then Remotes.MatchState:FireClient(p,status(p));return end
  if mode==false then remove(p);Queue.broadcast();return end
  if mode=="idle" then
   idle[p]=true
   p:SetAttribute("AFK",true) -- AFK time doesn't count toward playtime rewards
   if selected[p] then remove(p) end
   Queue.broadcast();return
  end
  if mode=="active" then
   if not idle[p] then return end
   idle[p]=nil
   p:SetAttribute("AFK",nil)
   -- back at the keyboard while still standing on a pad: put them straight back in line
   local pad=standingOn[p]
   if pad and not deps.isInMatch(p) then last[p]=nil;Queue.join(p,pad) else Queue.broadcast() end
   return
  end
  -- "Take me there": a mode in the lobby banner was tapped. Stand the player just in front of an
  -- open pad for that mode, facing it (never ON it: joining still means stepping onto a pad).
  if type(mode)=="table" and type(mode.goTo)=="string" then
   local want=mode.goTo
   if not Config.Modes[want] or deps.isInMatch(p) then return end
   if goCool[p] and os.clock()-goCool[p]<1 then return end
   goCool[p]=os.clock()
   local needed=Config.Modes[want].count
   local best,bestScore
   for _,pad in ipairs(pads) do
    if modeOf(pad)==want and #pools[pad]<needed then
     local standing=0
     for other,on in pairs(standingOn) do if on==pad and other~=p then standing+=1 end end
     -- pads someone is already waiting on fill a show fastest; solo pads should be empty
     local score=(want=="Solo" and standing*100 or (#pools[pad]>0 and 0 or 10))+(tonumber(pad.Name:match("%d+")) or 0)*0.1
     if not bestScore or score<bestScore then best,bestScore=pad,score end
    end
   end
   local char=p.Character
   local r=char and char:FindFirstChild("HumanoidRootPart")
   if not (best and r) then return end
   local flat=Vector3.new(0,best.Position.Y,best.Position.Z)-best.Position
   local front=flat.Magnitude>0.1 and flat.Unit or Vector3.new(1,0,0)
   local pos=best.Position+front*(math.max(best.Size.X,best.Size.Z)/2+5)+Vector3.new(0,3.2,0)
   p:SetAttribute("ObbyCP",nil);p:SetAttribute("ObbyStart",nil) -- leaving the mini obby ends that run
   r.AssemblyLinearVelocity=Vector3.zero
   char:PivotTo(CFrame.lookAt(pos,Vector3.new(best.Position.X,pos.Y,best.Position.Z)))
   return
  end
  -- Mode joins are exclusively detected from server-observed pad occupancy.
 end)
 -- Enter-only occupancy detection prevents cancellation from immediately requeuing.
 task.spawn(function()
  local previous,positions,armed={},{},{}
  while true do
   local inside={}
   for _,p in Players:GetPlayers() do
    local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if r then
     for _,pad in ipairs(pads) do
      local v=pad.CFrame:PointToObjectSpace(r.Position)
      if math.abs(v.X)<=pad.Size.X/2 and math.abs(v.Z)<=pad.Size.Z/2 and v.Y>=0 and v.Y<9 then
       inside[p]=pad
       local before=positions[p]
       local delta=before and (Vector3.new(r.Position.X,0,r.Position.Z)-Vector3.new(before.X,0,before.Z)).Magnitude or 0
       if previous[p]~=pad and armed[p]==p.Character and delta>.15 and delta<12 and not deps.isInMatch(p) then Queue.join(p,pad) end
       break
      end
     end
    end
   end
   for _,p in Players:GetPlayers() do
    local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if r then
     if not inside[p] and not deps.isInMatch(p) then armed[p]=p.Character end
     if deps.isInMatch(p) then armed[p]=nil end
     positions[p]=r.Position
    else armed[p]=nil;positions[p]=nil end
   end
   for p in pairs(positions) do if p.Parent~=Players then positions[p]=nil;armed[p]=nil end end
   local changed=false
   for p,pad in pairs(selected) do if inside[p]~=pad then remove(p);changed=true end end
   if changed then Queue.broadcast() end
   previous=inside
   standingOn=inside
   task.wait(0.2)
  end
 end)
 Players.PlayerRemoving:Connect(function(p) remove(p);last[p]=nil;idle[p]=nil;goCool[p]=nil;task.defer(Queue.tryStart) end)
end
return Queue

