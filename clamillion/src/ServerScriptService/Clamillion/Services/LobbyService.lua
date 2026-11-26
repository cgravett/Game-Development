local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Store=game:GetService("DataStoreService"):GetDataStore("ClamillionDailyTitles_v1")
local Remotes=RS.Clamillion.Remotes
local Service={}
local leaders={Solo={},Duel={},Triple={}}
local Catalog=require(RS.Clamillion.Shared.ShopCatalog)
local Shop=require(script.Parent.ShopService)
local Notifications=require(script.Parent.Notifications)
local MODE_LABEL={Solo="Solo",Duel="1v1",Triple="1v1v1"}
-- wheel prizes, in slice order (see ShopCatalog.WheelTitles; rare ones have thinner slices)
local titles={}
for _,t in ipairs(Catalog.WheelTitles) do table.insert(titles,t[1]) end
local busy,last={},{}
local inMatch
local wheelSpinning=false
-- won titles go into the player's inventory (they equip them from the Inventory)
local function award(p,title)
 Shop.ready(p)
 Shop.grant(p,Catalog.titleId(title),false)
end

---------------------------------------------------------------- daily reset (10:00 AM US Eastern)
-- A "wheel day" runs from 10:00 AM Eastern to 10:00 AM the next day. Daylight saving is handled
-- (EDT = UTC-4 from the 2nd Sunday of March to the 1st Sunday of November, otherwise EST = UTC-5).
local RESET_HOUR=10
local function daysFromCivil(y,m,d)
 y=y-(m<=2 and 1 or 0)
 local era=math.floor(y/400)
 local yoe=y-era*400
 local mp=(m+9)%12
 local doy=math.floor((153*mp+2)/5)+d-1
 local doe=yoe*365+math.floor(yoe/4)-math.floor(yoe/100)+doy
 return era*146097+doe-719468
end
local function nthSunday(y,m,n)
 local first=daysFromCivil(y,m,1)
 local dow=(first+4)%7 -- 0 = Sunday
 return first+((7-dow)%7)+(n-1)*7
end
local function easternOffset(t)
 local y=tonumber(os.date("!%Y",t))
 local dstStart=nthSunday(y,3,2)*86400+7*3600 -- 2:00 AM EST
 local dstEnd=nthSunday(y,11,1)*86400+6*3600  -- 2:00 AM EDT
 return (t>=dstStart and t<dstEnd) and -4 or -5
end
local function wheelDay(t)
 return math.floor((t+easternOffset(t)*3600-RESET_HOUR*3600)/86400)
end
local function nextReset(t)
 local day=wheelDay(t)+1
 local guess=day*86400+RESET_HOUR*3600-easternOffset(t)*3600
 return day*86400+RESET_HOUR*3600-easternOffset(guess)*3600
end
Service.wheelDay,Service.nextReset=wheelDay,nextReset
local studioSpins={} -- in Studio (no DataStores) the once-a-day rule is kept for this session
local function setNextSpin(p,unix) p:SetAttribute("NextWheelSpin",unix) end
---------------------------------------------------------------- leaderboards
-- All-time best match score per mode (OrderedDataStore), merged with this server's
-- scores so the boards update the moment a show ends, even if DataStores are slow/offline.
local DataStoreService=game:GetService("DataStoreService")
local BOARD_ROWS=8
local ordered,allTime,names={}, {Solo={},Duel={},Triple={}}, {}
for mode in pairs(leaders) do
 local ok,store=pcall(function() return DataStoreService:GetOrderedDataStore("ClamillionBest_"..mode.."_v1") end)
 if ok then ordered[mode]=store end
end
local storesOnline=false
local function nameFor(userId,fallback)
 if names[userId] then return names[userId] end
 local live=Players:GetPlayerByUserId(userId)
 if live then names[userId]=live.DisplayName return names[userId] end
 local ok,n=pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
 names[userId]=ok and n or fallback or ("Player "..userId)
 return names[userId]
end
local function UIformat(n)
 local s=tostring(math.floor(n)):reverse():gsub("(%d%d%d)","%1,"):reverse()
 return (s:gsub("^,",""))
end
local function render(mode)
 local board=workspace.ShowLobby.Activities.Leaderboards:FindFirstChild(mode)
 local rows=board and board:FindFirstChild("SurfaceGui") and board.SurfaceGui:FindFirstChild("Rows",true)
 if not rows then return end
 local merged={}
 for _,e in ipairs(allTime[mode]) do merged[e.key]={name=e.name,score=e.score} end
 for key,e in pairs(leaders[mode]) do
  if not merged[key] or merged[key].score<e.score then merged[key]={name=e.name,score=e.score} end
 end
 local list={} for _,v in pairs(merged) do table.insert(list,v) end
 table.sort(list,function(a,b) if a.score~=b.score then return a.score>b.score end return a.name<b.name end)
 for i=1,BOARD_ROWS do
  local row=rows:FindFirstChild("Row"..i)
  if row then
   local e=list[i]
   row:FindFirstChild("Name").Text=e and e.name or (i==1 and "Be the first star!" or "—")
   row:FindFirstChild("Score").Text=e and UIformat(e.score) or ""
  end
 end
 local scope=rows.Parent:FindFirstChild("Scope")
 if scope then scope.Text=storesOnline and "ALL-TIME BEST SCORES" or "TODAY'S BEST SCORES (THIS SERVER)" end
end
function Service.refreshBoards()
 for mode in pairs(leaders) do render(mode) end
end
local function pullAllTime()
 for mode,store in pairs(ordered) do
  local ok,pages=pcall(function() return store:GetSortedAsync(false,BOARD_ROWS) end)
  if ok and pages then
   storesOnline=true
   local list={}
   for _,item in ipairs(pages:GetCurrentPage()) do
    local userId=tonumber(item.key)
    if userId and item.value>0 then table.insert(list,{key=userId,name=nameFor(userId),score=item.value}) end
   end
   allTime[mode]=list
  end
  render(mode)
 end
end
function Service.record(mode,standings)
 local pool=leaders[mode];if not pool then return end
 -- the all-time #1 for this mode (if known): they get a notification when someone beats them
 local top=storesOnline and allTime[mode] and allTime[mode][1]
 for _,row in ipairs(standings) do
  -- Only real players (bots have no userId) make the boards.
  if not row.withdrawn and row.userId and row.score>0 then
   if top and top.key~=row.userId and row.score>top.score then
    Notifications.send(top.key,"dethroned",{mode=MODE_LABEL[mode] or mode})
    top=nil
   end
   local prev=pool[row.userId]
   pool[row.userId]={name=row.name,score=math.max(row.score,prev and prev.score or 0)}
   names[row.userId]=row.name
   local store=ordered[mode]
   if store and (storesOnline or not RunService:IsStudio()) then
    task.spawn(function()
     pcall(function()
      store:UpdateAsync(tostring(row.userId),function(old) old=tonumber(old) or 0 if row.score>old then return math.floor(row.score) end return nil end)
     end)
    end)
   end
  end
 end
 render(mode)
 if storesOnline then task.delay(8,pullAllTime) end
end
local function spin(p)
 local wheel=workspace.ShowLobby.Activities.DailyWheel
 local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
 if not root or (root.Position-wheel.Interact.Position).Magnitude>22 then return end
 local waitUntil=p:GetAttribute("NextWheelSpin")
 if waitUntil and waitUntil>os.time() then
  Remotes.LobbyReply:FireClient(p,{type="Wheel",error=true,nextSpin=waitUntil,text="You already spun today!"})
  return
 end
 if wheelSpinning then return end
 if inMatch(p) or busy[p] or last[p] and os.clock()-last[p]<1 then return end
 busy[p]=true;wheelSpinning=true;last[p]=os.clock()
 -- weighted pick: rare titles have thinner slices, so they come up less often
 local layout=Catalog.wheelLayout()
 local total=0 for _,l in ipairs(layout) do total+=l.weight end
 local roll=math.random()*total
 local choice=#titles
 for i,l in ipairs(layout) do roll-=l.weight if roll<=0 then choice=i break end end
 local title=titles[choice]
 local now=os.time()
 local today=wheelDay(now)
 local resetAt=nextReset(now)
 local reply={type="Wheel",index=choice,title=title,nextSpin=resetAt}
 if RunService:IsStudio() then
  if studioSpins[p.UserId]==today then
   reply={type="Wheel",error=true,nextSpin=resetAt,text="You already spun today!"}
  else
   studioSpins[p.UserId]=today
   award(p,title)
   reply.practice=true
  end
 else
  local receipt=game:GetService("HttpService"):GenerateGUID(false)
  local ok,data=pcall(function()
   return Store:UpdateAsync("u"..p.UserId,function(old)
    old=old or {owned={}}
    if old.day==today then return nil end -- already spun this wheel-day
    old.owned=old.owned or {};old.owned[title]=true;old.day=today;old.nextSpin=resetAt;old.receipt=receipt
    return old
   end)
  end)
  if not ok then reply={type="Wheel",error=true,text="Daily rewards are unavailable. Please try again later."}
  elseif not data or data.receipt~=receipt then reply={type="Wheel",error=true,nextSpin=resetAt,text="You already spun today!"}
  else award(p,title) end
 end
 if not reply.error or reply.nextSpin then setNextSpin(p,resetAt) end
 if reply.error then
  busy[p]=nil;wheelSpinning=false
  if p.Parent==Players then Remotes.LobbyReply:FireClient(p,reply) end
  return
 end
 if not reply.error then
  -- Prize i sits at angle (i-1)*slice on the rotor; the pointer is at the top (angle 0).
  -- The rotor lands so the awarded prize is under the pointer. Clients animate it smoothly.
  local rotor=wheel.Rotor
  local rest=wheel:GetAttribute("RestPivot")
  local a0=wheel:GetAttribute("Angle") or 0
  local spot=Catalog.wheelLayout()[reply.index or 1]
  local target=-spot.center+(math.random()-.5)*spot.half*1.2
  local base=a0-math.pi*2*5
  local a1=target-math.pi*2*math.ceil((target-base)/(math.pi*2))
  local duration=4.6
  wheel.Result.SurfaceGui.Body.Text=p.DisplayName.." is spinning!"
  wheel:SetAttribute("SpinFrom",a0);wheel:SetAttribute("SpinTo",a1)
  wheel:SetAttribute("SpinDuration",duration);wheel:SetAttribute("SpinStart",workspace:GetServerTimeNow())
  wheel:SetAttribute("SpinId",(wheel:GetAttribute("SpinId") or 0)+1)
  task.wait(duration+.15)
  if rest then rotor:PivotTo(rest*CFrame.Angles(a1%(math.pi*2),0,0)) end
  wheel:SetAttribute("Angle",a1%(math.pi*2))
  task.wait(.4)
 end
 wheel.Result.SurfaceGui.Body.Text=reply.error and reply.text or (p.DisplayName.." won\n★ "..reply.title:upper().." ★")
 busy[p]=nil;wheelSpinning=false
 if p.Parent==Players then Remotes.LobbyReply:FireClient(p,reply) end
end
---------------------------------------------------------------- ad boards
-- Lobby wall boards cycle through the slides in Clamillion.LobbyAds.
local function showAd(board, slide)
 local bg=board:FindFirstChild("Screen") and board.Screen:FindFirstChild("Ad") and board.Screen.Ad:FindFirstChild("BG")
 if not bg or not slide then return end
 bg.Tag.Text=slide.tag or ""
 bg.Tag.Visible=slide.tag~=nil
 bg.Icon.Text=slide.icon or "★"
 bg.Title.Text=slide.title or ""
 bg.Body.Text=slide.body or ""
 if slide.colors then bg.Gradient.Color=ColorSequence.new(slide.colors[1],slide.colors[2]) end
end
function Service.startAds()
 local boards=workspace.ShowLobby:FindFirstChild("AdBoards")
 local ok,ads=pcall(require,script.Parent.Parent:FindFirstChild("LobbyAds"))
 if not boards or not ok or not ads or #ads.Slides==0 then return end
 task.spawn(function()
  local step=0
  while true do
   for _,b in ipairs(boards:GetChildren()) do
    local slot=b:GetAttribute("Slot") or 1
    showAd(b,ads.Slides[((step+slot-1)%#ads.Slides)+1])
   end
   step+=1
   task.wait(ads.Seconds or 8)
  end
 end)
end

function Service.init(isInMatch)
 inMatch=isInMatch
 Service.startAds()
 do
  local wheel=workspace.ShowLobby.Activities.DailyWheel
  local rotor=wheel.Rotor
  if not wheel:GetAttribute("RestPivot") then wheel:SetAttribute("RestPivot",rotor:GetPivot()) end
  wheel:SetAttribute("Angle",0)
 end
 Service.refreshBoards()
 -- The wheel is activated only at its physical station.
 local A=workspace.ShowLobby.Activities
 -- optional world kiosks (shop/settings are also on-screen buttons)
 local shop=A:FindFirstChild("ShopKiosk")
 if shop and shop:FindFirstChild("ProximityPrompt") then shop.ProximityPrompt.Triggered:Connect(function(p)
  if not inMatch(p) then Remotes.LobbyReply:FireClient(p,{type="OpenShop"}) end
 end) end
 workspace.ShowLobby.Activities.DailyWheel.Interact.ProximityPrompt.Triggered:Connect(function(p)
  if not inMatch(p) then task.spawn(spin,p) end
 end)
 -- the cotton-candy Rewards stand opens the rewards menu
 local stand=A:FindFirstChild("RewardsStand")
 local standPrompt=stand and stand:FindFirstChild("ProximityPrompt",true)
 if standPrompt then standPrompt.Triggered:Connect(function(p)
  if not inMatch(p) then Remotes.LobbyReply:FireClient(p,{type="OpenRewards"}) end
 end) end
 local settingsKiosk=A:FindFirstChild("SettingsKiosk")
 if settingsKiosk and settingsKiosk:FindFirstChild("ProximityPrompt") then settingsKiosk.ProximityPrompt.Triggered:Connect(function(p)
  if not inMatch(p) then Remotes.LobbyReply:FireClient(p,{type="OpenSettings"}) end
 end) end
 local function joined(p)
  -- restore today's spin status (so the countdown shows) and copy any older wheel titles into the inventory
  if RunService:IsStudio() then
   if studioSpins[p.UserId]==wheelDay(os.time()) then setNextSpin(p,nextReset(os.time())) end
   return
  end
  task.spawn(function()
   local ok,data=pcall(function()return Store:GetAsync("u"..p.UserId)end)
   if not (ok and data and p.Parent==Players) then return end
   if data.day==wheelDay(os.time()) then setNextSpin(p,data.nextSpin or nextReset(os.time())) end
   Shop.ready(p)
   for name in pairs(data.owned or {}) do Shop.grant(p,Catalog.titleId(name),false) end
  end)
 end
 Players.PlayerAdded:Connect(joined);for _,p in Players:GetPlayers() do joined(p) end
 task.spawn(function()
  while true do
   pullAllTime()
   -- In Studio without API access, stop retrying (boards keep showing this server's scores).
   if RunService:IsStudio() and not storesOnline then break end
   task.wait(90)
  end
 end)
 Players.PlayerRemoving:Connect(function(p)busy[p]=nil;last[p]=nil end)
end
return Service
