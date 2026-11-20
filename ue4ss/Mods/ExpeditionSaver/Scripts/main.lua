-- Expedition Saver v0.2.0-alpha | Grain Rot (Helden / UE4SS 3.x)
-- Host-authoritative only. This mod is EXPERIMENTAL; back up the save.
-- The latest 2026-11-20 USMAP confirms fields and reflected signatures,
-- not the exact native save/death sequence. Every mutation is checked.
local CFG = {
    PollSeconds = 0.30,
    AnimationSample = 8,
    MaxDepth = 10000,
    EnableRespawn = true,
    EnableItemRecovery = true,
    RestoreDestroyedItems = true,
    MaxGearPerPlayer = 60,
    EnableNoPermadeath = true,
    EnablePhysicalCoins = true,
    RespawnDelaySeconds = 1.25,
    RespawnRetrySeconds = 2.5,
    MaxRespawnRequests = 3,
    BackupFile = true,
    MaxCoinsPerDrop = 100000,
    RewardDelaySeconds = 0.20,
    RetryHookSeconds = 8,
    HeartbeatDiagnosticsSeconds = 12,
    RecoveryRetrySeconds = 2,
    Verbose = false,
}
local TAG = "[ExpeditionSaver] "
local function log(s) print(TAG..tostring(s).."\n") end
local function diag(s) if CFG.Verbose then log(s) end end
local function get(o,k)
    if o == nil then return nil end
    local ok,r=pcall(function() return o[k] end)
    if ok then return r end
end
local function put(o,k,v)
    if o == nil then return false end
    local ok=pcall(function() o[k]=v end)
    if not ok then return false end
    return true
end
local function valid(o)
    if o==nil then return false end
    local ok,r=pcall(function() return o:IsValid() end)
    return ok and r==true
end
local function unwrap(o)
    if o==nil then return nil end
    local ok,r=pcall(function() return o:get() end)
    if ok then return r end
    return o
end
local function number(o,lo,hi)
    local n=tonumber(o)
    if n and n==n and n~=math.huge and n~=-math.huge then
        n=math.floor(n)
        if n>=lo and n<=hi then return n end
    end
    return nil
end
local function enum(v)
    if type(v)=="number" then return v end
    if v==nil then return nil end
    local s=tostring(v)
    local n=tonumber(s)
    if n then return n end
    if s:find("Expedition",1,true) then return 1 end
    if s:find("Exploring",1,true) then return 2 end
    if s:find("EndScreen",1,true) then return 3 end
    if s:find("ElevatorRideDown",1,true) then return 1 end
    if s:find("Epic",1,true) then return 2 end
    if s:find("Failed",1,true) then return 1 end
    if s:find("None",1,true) or s:find("Default",1,true) then return 0 end
end
local function failure(v)
    local n=enum(v)
    return n~=nil and n%2==1
end
local function path(o)
    if not valid(o) then return nil end
    local ok,r=pcall(function() return o:GetFullName() end)
    if ok and r then return tostring(r) end
    return tostring(o)
end
local function each(arr,callback)
    if not arr then return end
    local ok,n=pcall(function() return #arr end)
    if not ok or type(n)~="number" then return end
    for i=1,math.min(n,128) do
        local success,o=pcall(function() return unwrap(arr[i]) end)
        if success and o then callback(o,i) end
    end
end
local cache={}
local function first(cls)
    if valid(cache[cls]) then return cache[cls] end
    cache[cls]=nil
    local function live(obj)
        if not valid(obj) then return false end
        local id=path(obj)
        return id and not id:find("Default__",1,true)
    end
    local ok,obj=pcall(FindFirstOf,cls)
    if ok and live(obj) then cache[cls]=obj;return obj end
    -- FindFirstOf may return a Class Default Object before an actual actor.
    local good,items=pcall(FindAllOf,cls)
    if good and type(items)=="table" then
        for _,candidate in ipairs(items) do
            if live(candidate) then cache[cls]=candidate;return candidate end
        end
    end
end
local function all(cls)
    local ok,objects=pcall(FindAllOf,cls)
    if ok and type(objects)=="table" then return objects end
    return {}
end
local function vec(v)
    if not v then return nil end
    local x,y,z=tonumber(get(v,"X")),tonumber(get(v,"Y")),tonumber(get(v,"Z"))
    if x and y and z then return {X=x,Y=y,Z=z} end
end
local function distance2(a,b)
    if not a or not b then return math.huge end
    return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
end
local function location(a)
    if not valid(a) then return nil end
    local ok,r=pcall(function() return a:K2_GetComponentLocation() end)
    if ok and r then return vec(r) end
    ok,r=pcall(function() return a:K2_GetActorLocation() end)
    if ok and r then return vec(r) end
end
local function teleport(obj,dest)
    if not valid(obj) or not dest then return false end
    local rot={Pitch=0,Yaw=0,Roll=0}
    local ok,result=pcall(function() return obj:K2_TeleportTo(dest,rot) end)
    if ok and result~=false then return true end
    ok,result=pcall(function()
        return obj:K2_SetActorLocation(dest,false,{},true)
    end)
    return ok and result~=false
end
local function onHost()
    return valid(first("HeldenGameMode")) or valid(first("GameModeBase"))
end
local function game()
    local gi=first("HeldenGameInstance")
    local gs=first("HeldenGameState")
    local save=gi and get(gi,"CurrentSaveGame")
    if not valid(gs) or not valid(save) then return nil end
    -- Do not touch the normal game. GameModeType is the authoritative check.
    local gm=enum(get(gs,"GameModeType"))
    local sg=enum(get(save,"GameMode"))
    local metadataMode=enum(get(get(save,"MetaData"),"GameMode"))
    -- Some transitions leave GameState.GameModeType unset while the
    -- underlying SaveGame still identifies a valid Expedition. Require two
    -- independent saved indicators if the live GameState disagrees.
    if gm~=1 and not (sg==1 and metadataMode==1) then return nil end
    local run=get(gs,"CurrentDungeonRun")
    if not run then return nil end
    return {gi=gi,gs=gs,save=save,run=run,
        phase=enum(get(run,"State")) or 0,
        failed=failure(get(run,"Flags"))}
end
local S={
    slot=nil,saveKey=nil,depth=0,highestSeed=0,offset=nil,
    active=false,failed=false,phase=nil,pending={},
    sample=0,lastPoll=-1,nextBackupDepth=-1,
    nextBackupTime=-1,coinLedger={},respawned=0,
    lastMode="unknown",lastDisplay=nil,warned=false,
    lastHeartbeat=0,lastGuard=nil,recoveryRequired=false,
    nextMachineRepair=0,machineRepairAttempts=0,
    dropQueue={},destructionSeen={},dropAttempt=0,
    deathEvents=0,newPawnEvents=0,rewardEvents=0
}
local function backupFile(slot)
    if not CFG.BackupFile then return nil end
    local base
    pcall(function() base=os.getenv("LOCALAPPDATA") end)
    if not base or base=="" then return nil end
    return base.."\\Helden\\Saved\\ExpeditionSaver_slot"..slot..".txt"
end
local function readBackup(slot,played,fails)
    local fname=backupFile(slot)
    if not fname or played==nil or fails==nil then return nil end
    local f=io.open(fname,"r")
    if not f then return nil end
    local line=f:read("*l");f:close()
    if not line then return nil end
    local ver,sl,d,t,ff=line:match("^(%S+) (%d+) (%d+) (%d+) (%d+)$")
    if ver~="EXPS1" or tonumber(sl)~=slot then return nil end
    local depth=number(d,0,CFG.MaxDepth)
    local oldTime=number(t,0,1000000000)
    local oldFails=number(ff,0,1000000000)
    if not depth or not oldTime or not oldFails then return nil end
    -- Never restore older progress to a brand-new game on the same slot.
    if played+5<oldTime or fails<oldFails then return nil end
    return depth
end
local function backupDepth(ctx,depth)
    if not CFG.BackupFile or depth<1 then return end
    if S.nextBackupDepth==depth then return end
    local slot=S.slot
    local time=number(get(ctx.save,"TimePlayed"),0,1000000000)
    local fails=number(get(ctx.save,"DungeonFails"),0,1000000000)
    local fname=slot and backupFile(slot)
    if not fname or time==nil or fails==nil then return end
    local f=io.open(fname,"w")
    if not f then return end
    f:write(string.format("EXPS1 %d %d %d %d\n",slot,depth,time,fails))
    f:close()
    S.nextBackupDepth=depth
end
local function resetForSave(ctx,key,slot)
    local oldSlot=S.slot
    local oldPending=S.pending
    local preserve=oldSlot==slot and S.recoveryRequired
    S.slot=slot;S.saveKey=key
    S.depth=number(get(ctx.save,"DungeonLevel"),0,CFG.MaxDepth) or 0
    S.highestSeed=0;S.offset=nil;S.active=false;S.failed=false
    S.phase=nil;S.pending=preserve and oldPending or {};S.coinLedger={}
    S.nextBackupDepth=-1
    S.dropQueue={};S.destructionSeen={}
    S.nextMachineRepair=0;S.machineRepairAttempts=0
    local time=number(get(ctx.save,"TimePlayed"),0,1000000000)
    local fails=number(get(ctx.save,"DungeonFails"),0,1000000000)
    local recovered=readBackup(slot,time,fails)
    if recovered and recovered>S.depth then S.depth=recovered end
    log("Expedition slot "..slot.." loaded; protected depth "..S.depth)
end
local function keepExpedition(ctx)
    if not CFG.EnableNoPermadeath then return end
    local raw=number(get(ctx.save,"DungeonLevel"),0,CFG.MaxDepth)
    if not raw then return end
    if raw>S.depth then S.depth=raw;diag("reached save depth "..raw) end
    local dungeon=get(ctx.run,"DungeonActor")
    local seed=get(dungeon,"CurrentSeed")
    local lv=number(get(seed,"Level"),0,CFG.MaxDepth)
    if ctx.phase==1 or ctx.phase==2 then
        if ctx.phase==1 and S.phase~=1 and S.recoveryRequired then
            S.recoveryRequired=false;S.machineRepairAttempts=0
            log("new expedition ride started; recovery finished")
        end
        S.active=true
        if lv then
            if raw>=lv and raw<=lv+1 then S.offset=raw-lv end
            if lv>S.highestSeed then S.highestSeed=lv end
        end
    end
    if S.highestSeed>0 then
        local goal=S.highestSeed+(S.offset or 0)
        if goal>S.depth then S.depth=goal end
    end
    if (ctx.phase==3 or ctx.phase==0) and S.active and ctx.failed then
        if not S.failed then
            S.failed=true;S.recoveryRequired=true
            log("failed Expedition run; keeping dungeon depth "..S.depth)
        end
    end
    -- Clear permanent flags even during Exploration: the native game may
    -- set them at the instant the last party member dies.
    local md=get(ctx.save,"MetaData")
    if md and get(md,"bHasFailed")==true then
        if put(md,"bHasFailed",false) then
            S.recoveryRequired=true
            log("suppressed permanent failure in SaveGame metadata")
        end
    end
    if get(ctx.gs,"bExpeditionFailed")==true then
        if put(ctx.gs,"bExpeditionFailed",false) then
            S.recoveryRequired=true
            log("cleared expedition failure in runtime")
        end
    end
    if ctx.phase==3 or ctx.phase==0 then
        -- Do not clear CurrentDungeonRun.Flags.Failed: the end screen uses it.
        if raw<S.depth and (S.failed or (ctx.phase==0 and not S.active)) then
            if put(ctx.save,"DungeonLevel",S.depth) then
                log("restored Expedition depth "..raw.." -> "..S.depth)
            end
        end
    end
    backupDepth(ctx,S.depth)
end

-- Record *existing* item actors, not classes or copies. No destructive array
-- operations on the new pawn; we never create duplicated item instances.
local function gearOf(char)
    local result,seen={},{}
    local function add(item)
        if not valid(item) then return end
        local id=path(item)
        if not id or seen[id] then return end
        seen[id]=true
        if #result>=CFG.MaxGearPerPlayer then return end
        local cls
        pcall(function() cls=item:GetClass() end)
        local asset=get(item,"ItemDataAsset")
        result[#result+1]={ref=item,key=id,klass=cls,
            classPath=valid(cls) and path(cls) or nil,
            asset=asset,assetPath=valid(asset) and path(asset) or nil,
            durability=tonumber(get(item,"ItemDurability")),
            enchant=get(item,"ItemEnchantment"),
            slotIdx=number(get(item,"CurrentInventorySlot"),0,128)}
    end
    each(get(char,"EquipedItems"),add)
    for _,item in ipairs(all("HeldenEquipableItem")) do
        if valid(item) and get(item,"PreviousOwner")==char and valid(get(item,"CurrentSlot")) then
            add(item)
        end
    end
    return result
end
local function currentPawn(pc)
    if not valid(pc) then return nil end
    local ok,pawn=pcall(function() return pc:GetPawn() end)
    if ok and valid(pawn) then return pawn end
end
local function captureDeath(char)
    if not CFG.EnableRespawn or not onHost() then return end
    local ctx=game()
    if not ctx or not (ctx.phase==2 or (ctx.phase==3 and S.active)) then return end
    local pc
    pcall(function() pc=char:GetController() end)
    if not valid(pc) then return end
    local key=path(pc)
    if not key or S.pending[key] then return end
    -- Ignore NPC/AI deaths even if they expose a Controller method.
    local isPlayer=false
    for _,playerController in ipairs(all("HeldenPlayerController")) do
        if path(playerController)==key then isPlayer=true;break end
    end
    if not isPlayer then return end
    local inv=gearOf(char)
    local entry={controller=pc,oldChar=char,gear=inv,
        started=os.clock(),attempts=0,nextRequest=0,
        spawned=nil,delivered=false}
    S.pending[key]=entry
    S.deathEvents=S.deathEvents+1
    log("DEATH HOOK player="..key.." phase="..ctx.phase..
        " retained="..#inv.." awaiting server respawn")
end
local function respawnLocation()
    local lift=first("HeldenDungeonElevator")
    if not valid(lift) then return nil end
    local comp=get(lift,"InteriorCollisionBox")
    local loc=location(comp) or location(lift)
    if not loc then return nil end
    return {X=loc.X,Y=loc.Y,Z=loc.Z+80}
end
local function heal(pawn)
    local stats=get(pawn,"CharacterStats")
    if not valid(stats) then return false end
    local max=tonumber(get(get(stats,"TotalStats"),"MaxHealth"))
    if not max or max<=0 or max>1000000 then return false end
    return put(stats,"CurrentHealth",max)
end
local function collectAtElevator(entry,dest,pawn)
    if not CFG.EnableItemRecovery then return end
    local moved,alreadyOwned,created,lost=0,0,0,0
    local counts={}
    local nativeRefs={}
    local function countNative(item)
        if not valid(item) then return end
        nativeRefs[path(item)]=true
        local klass
        pcall(function() klass=item:GetClass() end)
        local key=valid(klass) and path(klass)
        if key then counts[key]=(counts[key] or 0)+1 end
    end
    each(get(pawn,"EquipedItems"),countNative)
    each(get(pawn,"ItemSlots"),function(slot)
        local item=get(slot,"CurrentItemInSlot")
        if valid(item) then countNative(item) end
    end)
    local world
    pcall(function() world=pawn:GetWorld() end)
    if not valid(world) then
        local lift=first("HeldenDungeonElevator")
        pcall(function() world=lift:GetWorld() end)
    end
    for i,r in ipairs(entry.gear) do
        local item=r.ref
        local key=r.classPath
        local count=key and (counts[key] or 0) or 0
        if (valid(item) and nativeRefs[path(item)]) or count>0 or
            (valid(item) and get(item,"PreviousOwner")==pawn) then
            if count>0 then counts[key]=count-1 end
            -- Native game already restored an item of this class.
            alreadyOwned=alreadyOwned+1
        else
            local at={X=dest.X+((i-1)%4)*55-75,
                Y=dest.Y+math.floor((i-1)/4)*55,Z=dest.Z+40}
            if valid(item) then
                pcall(function() item:DetachFromAll() end)
                if teleport(item,at) then moved=moved+1 else lost=lost+1 end
            elseif CFG.RestoreDestroyedItems and valid(world) then
                local klass=r.klass
                if not valid(klass) and r.classPath and
                    type(StaticFindObject)=="function" then
                    pcall(function() klass=StaticFindObject(r.classPath) end)
                end
                if valid(klass) then
                    local ok,newItem=pcall(function()
                        return world:SpawnActor(klass,at,{Pitch=0,Yaw=0,Roll=0})
                    end)
                    if ok and valid(newItem) then
                        if r.asset and valid(r.asset) then
                            put(newItem,"ItemDataAsset",r.asset)
                        end
                        if r.durability then
                            put(newItem,"ItemDurability",r.durability)
                        end
                        if r.enchant~=nil then
                            pcall(function() newItem.ItemEnchantment=r.enchant end)
                        end
                        created=created+1
                        diag("recreated destroyed gear "..r.key)
                    else lost=lost+1 end
                else lost=lost+1 end
            else lost=lost+1 end
        end
    end
    log("EQUIPMENT native="..alreadyOwned.." moved="..moved..
        " recreated="..created.." unavailable="..lost)
    if lost>0 then
        log("WARNING: "..lost.." items could not be recovered; see complete UE4SS.log")
    end
end

local function processDeaths(ctx)
    if not CFG.EnableRespawn then return end
    local now=os.clock()
    for key,entry in pairs(S.pending) do
        -- Do not try respawn after the entire expedition has already failed.
        if now-entry.started>35 then
            log("respawn timed out for "..key)
            S.pending[key]=nil
        else
            local pawn=currentPawn(entry.controller)
            if entry.spawned and valid(entry.spawned) then pawn=entry.spawned end
            if pawn and path(pawn)~=path(entry.oldChar) and valid(get(pawn,"CharacterStats")) then
                local at=respawnLocation()
                if at and teleport(pawn,at) then
                    local healed=heal(pawn)
                    collectAtElevator(entry,at,pawn)
                    log("respawn in elevator "..key.."; healed="..tostring(healed))
                    S.pending[key]=nil
                    S.respawned=S.respawned+1
                end
            elseif now-entry.started>=CFG.RespawnDelaySeconds and
                   entry.attempts<CFG.MaxRespawnRequests and now>=entry.nextRequest then
                entry.attempts=entry.attempts+1
                entry.nextRequest=now+CFG.RespawnRetrySeconds
                local ok,err=pcall(function()
                    entry.controller:RespawnCharacter_Server()
                end)
                log("respawn request "..entry.attempts.." -> "..tostring(ok)..
                    (ok and "" or (": "..tostring(err))))
            end
        end
    end
end
-- Automatic payout on physical destruction. There is no hotkey.
-- The game still handles its native scrap/resource drops; we add only
-- the Gold/Artifacts that the *same actor* would pay at extraction.
-- IMPORTANT: Read live structs/tables, which also sees QOL's edited values.
local function rowOf(tableObject,rowName)
    if not valid(tableObject) or not rowName then return nil end
    local ok,row=pcall(function() return tableObject:FindRow(rowName) end)
    if ok and row then return unwrap(row) end
    ok,row=pcall(function() return tableObject:GetRowMap() end)
    if ok and type(row)=="table" then
        return unwrap(row[tostring(rowName)])
    end
end
local function lootValue(actor)
    if not valid(actor) then return nil end
    local id=path(actor) or ""
    local normalized=id:lower()
    -- Coin/pickup destruction must never recursively create currency.
    if normalized:find("coin",1,true) or normalized:find("pickup",1,true) then return nil end
    local ds=first("HeldenDataSingleton")
    local inspected
    pcall(function() inspected=actor:GetInspectData() end)
    if inspected and get(inspected,"bIsInDungeon")==true then
        local value=get(inspected,"Value")
        if value then
            local gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0
            local artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0
            return {gold=gold,artifacts=artifacts,source="inspect"}
        end
    end
    if not ds then return nil end
    -- Reflected actor DataName fields are used as keys; never infer rewards
    -- from an object's color or from an unrelated player's inventory.
    local construct=get(actor,"ConstructAsset")
    if valid(construct) then
        local n=get(construct,"DataName")
        local dt=get(ds,"ConstructAssetDataTable")
        local row=rowOf(dt,n)
        if row then
            local quality=enum(get(actor,"ConstructQuality"))
            local key=quality==2 and "Parsed_ScrapValue_Epic"
                or quality==1 and "Parsed_ScrapValue_Rare"
                or "Parsed_ScrapValue_Common"
            local value=get(row,key)
            if value then
                return {gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0,
                    artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0,
                    source="construct-table"}
            end
        end
    end
    -- Non-construct physical loot uses PhysActorData, where QOL multiplies
    -- Parsed_ScrapReward.Gold. No additional multiplier is applied here.
    local n=get(actor,"ConstructDataName") or get(actor,"StatsDataName")
    if not n then return nil end
    local row=rowOf(get(ds,"PhysActorDataTable"),n)
    local value=row and get(row,"Parsed_ScrapReward")
    if not value then return nil end
    return {gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0,
        artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0,
        source="physical-table"}
end
local function destructionEvent(ctx,origin)
    if not onHost() then return end
    local gameCtx=game()
    if not gameCtx or gameCtx.phase~=2 then return end
    local a=unwrap(ctx)
    if not valid(a) or not valid(get(a,"StatsComponent")) then return end
    if get(a,"bIsQuestObjective")==true or
       get(a,"bRequireQuestObjectiveToKill")==true then return end
    -- Require an actual in-dungeon loot actor; never pay for built furniture.
    local owning=get(a,"OwningDungeon")
    local inspecting
    pcall(function() inspecting=a:GetInspectData() end)
    local inDungeon=inspecting and get(inspecting,"bIsInDungeon")==true
    if not inDungeon and not valid(unwrap(owning)) then return end
    if origin=="health" then
        local hp=tonumber(get(get(a,"StatsComponent"),"CurrentHealth"))
        if not hp or hp>0 then return end
    end
    local key=path(a)
    if not key or S.destructionSeen[key] then return end
    S.rewardEvents=S.rewardEvents+1
    local value=lootValue(a)
    if not value then
        if S.rewardEvents<=15 then log("DESTRUCTION "..origin.." "..key.." (no reward data)") end
        return
    end
    if value.gold<=0 and value.artifacts<=0 then
        if S.rewardEvents<=15 then log("DESTRUCTION "..origin.." "..key.." (no coin payout)") end
        return
    end
    local at=location(a)
    local world
    pcall(function() world=a:GetWorld() end)
    if not at or not valid(world) then
        log("DESTRUCTION "..origin.." cannot resolve world/position; no payout")
        return
    end
    S.destructionSeen[key]=true
    S.dropQueue[#S.dropQueue+1]={world=world,at=at,key=key,
        gold=value.gold,artifacts=value.artifacts,source=value.source,
        queued=os.clock(),goldDone=false,artifactDone=false}
    log("DESTRUCTION queued "..key.." gold="..value.gold.." artifacts="..
        value.artifacts.." source="..value.source.." from="..origin)
end
local function spawnMoney(world,position,actorClass,amount,currency)
    if not valid(world) or not valid(actorClass) or amount<=0 then return false end
    local ok,coin=pcall(function()
        return world:SpawnActor(actorClass,position,{Pitch=0,Yaw=0,Roll=0})
    end)
    if not ok or not valid(coin) then return false end
    local money=get(coin,"Money")
    if not money then
        pcall(function() coin:K2_DestroyActor() end)
        return false
    end
    local success=put(money,"Gold",currency=="Gold" and amount or 0)
        and put(money,"Artifacts",currency=="Artifacts" and amount or 0)
        and put(money,"Scraps",0)
    -- Check the *actor's own* struct again; success on a Lua copy isn't enough.
    local actual=get(coin,"Money")
    success=success and number(get(actual,currency),0,CFG.MaxCoinsPerDrop)==amount
        and number(get(actual,"Scraps"),0,CFG.MaxCoinsPerDrop)==0
        and number(get(actual,currency=="Gold" and "Artifacts" or "Gold"),
            0,CFG.MaxCoinsPerDrop)==0
    if not success then
        pcall(function() coin:K2_DestroyActor() end)
        return false
    end
    return true
end
local function processDropQueue()
    if #S.dropQueue==0 or not onHost() then return end
    local ds=first("HeldenDataSingleton")
    if not ds then return end
    local goldClass=get(ds,"GoldCoinActorClass")
    local artifactClass=get(ds,"ArtifactCoinActorClass")
    local now=os.clock()
    for i=#S.dropQueue,1,-1 do
        local job=S.dropQueue[i]
        if now-job.queued>=CFG.RewardDelaySeconds then
            local done=true
            if job.gold>0 and not job.goldDone then
                job.goldDone=spawnMoney(job.world,job.at,goldClass,job.gold,"Gold")
                if job.goldDone then
                    log("DROP gold="..job.gold.." "..job.key)
                else done=false end
            end
            if job.artifacts>0 and not job.artifactDone then
                local offset={X=job.at.X+65,Y=job.at.Y,Z=job.at.Z+25}
                job.artifactDone=spawnMoney(job.world,offset,artifactClass,
                    job.artifacts,"Artifacts")
                if job.artifactDone then
                    log("DROP artifacts="..job.artifacts.." "..job.key)
                else done=false end
            end
            if done or now-job.queued>5 then
                if not done then
                    log("WARNING partial/unpaid extraction reward: "..job.key..
                        " goldDone="..tostring(job.goldDone)..
                        " artifactsDone="..tostring(job.artifactDone))
                end
                table.remove(S.dropQueue,i)
            end
        end
    end
end

-- Game preserves an EndScreen/Failed state after the final death. Updating
-- DungeonLevel alone does NOT unlock the machine; repair the run AND its
-- interaction gate only after the elevator is back at the home station.
local function repairElevator(ctx)
    if not CFG.EnableNoPermadeath or not S.recoveryRequired then return end
    if ctx.phase==1 or ctx.phase==2 then return end
    local now=os.clock()
    if now<S.nextMachineRepair or S.machineRepairAttempts>=10 then return end
    S.nextMachineRepair=now+CFG.RecoveryRetrySeconds
    S.machineRepairAttempts=S.machineRepairAttempts+1
    local lift=first("HeldenDungeonElevator")
    local machine=first("HeldenElevatorMachine")
    if valid(lift) then
        local home=number(get(lift,"HomeStationIdx"),0,256)
        local station=number(get(lift,"CurrentStationIdx"),0,256)
        if home~=nil and station~=nil and home~=station then
            log("RECOVERY waiting for elevator at home; station="..station.." home="..home)
            return
        end
    elseif ctx.phase~=0 then
        log("RECOVERY waiting for home elevator (run="..ctx.phase..")")
        return
    end
    local run=get(ctx.gs,"CurrentDungeonRun")
    local before=enum(get(run,"State"))
    local flagsBefore=enum(get(run,"Flags"))
    local changed=true
    if before==3 then changed=put(run,"State",0) end
    if get(run,"Flags")~=nil then put(run,"Flags",0) end
    -- A reflected UStruct might be copy-on-read. Write it back to its
    -- GameState owner and verify that the actual source changed.
    if before==3 and enum(get(get(ctx.gs,"CurrentDungeonRun"),"State"))~=0 then
        put(ctx.gs,"CurrentDungeonRun",run)
    end
    local after=enum(get(get(ctx.gs,"CurrentDungeonRun"),"State"))
    local clear=after==0
    local interaction="not found"
    if valid(machine) then
        if get(machine,"bInteractionLocked")==true then
            put(machine,"bInteractionLocked",false)
        end
        local ok,why=pcall(function() machine:SetCanBeInteracted_Auth(true) end)
        if ok then interaction="unlocked" else interaction="error:"..tostring(why) end
        pcall(function() machine:OnRequirementSysUpdate_Auth() end)
        -- Recompute native elevator-button state using the restored run.
        if clear then
            pcall(function() machine:OnDungeonRunStateChanged(get(ctx.gs,"CurrentDungeonRun")) end)
        end
    end
    if valid(lift) and get(lift,"bInteractionLocked")==true then
        put(lift,"bInteractionLocked",false)
    end
    if clear then
        pcall(function() ctx.gs:OnRep_DungeonRunState() end)
    end
    log("RECOVERY run="..tostring(before).." -> "..tostring(after)..
        " flags="..tostring(flagsBefore).." -> "..
        tostring(enum(get(get(ctx.gs,"CurrentDungeonRun"),"Flags")))..
        " machine="..interaction.." attempt="..S.machineRepairAttempts)
    if after~=0 and S.machineRepairAttempts==10 then
        log("WARNING: cannot reset ended run; elevator may stay locked")
    end
end

local function poll()
    local now=os.clock()
    local host=onHost()
    local ctx=host and game()
    if now-S.lastHeartbeat>=CFG.HeartbeatDiagnosticsSeconds then
        S.lastHeartbeat=now
        local gs=first("HeldenGameState")
        local gi=first("HeldenGameInstance")
        local save=gi and get(gi,"CurrentSaveGame")
        log("HEARTBEAT host="..tostring(host).." GS="..tostring(valid(gs))..
            " mode="..tostring(enum(get(gs,"GameModeType")))..
            " save="..tostring(valid(save))..
            " saveMode="..tostring(enum(get(save,"GameMode")))..
            " phase="..tostring(ctx and ctx.phase)..
            " deaths="..S.deathEvents.." destructionEvents="..S.rewardEvents)
    end
    if not ctx then
        if S.lastMode~="nonexpedition" then
            S.lastMode="nonexpedition"
            log("inactive: missing authoritative Expedition context")
        end
        return
    end
    S.lastMode="expedition"
    local md=get(ctx.save,"MetaData")
    local slot=number(get(md,"GameSlot"),0,100)
    if not slot then return end
    local key=path(ctx.save)
    if S.slot~=slot or S.saveKey~=key then resetForSave(ctx,key,slot) end
    keepExpedition(ctx)
    processDeaths(ctx)
    repairElevator(ctx)
    processDropQueue()
    if ctx.phase==1 or ctx.phase==2 then
        if S.phase==0 or S.phase==3 then
            cache["HeldenDungeonElevator"]=nil
        end
    end
    if S.phase~=ctx.phase then
        log("run state "..tostring(S.phase).." -> "..ctx.phase.."; depth="..S.depth)
    end
    S.phase=ctx.phase
end

local function isExpeditionDeath()
    if not onHost() then return false end
    local ctx=game()
    return ctx and (ctx.phase==2 or (ctx.phase==3 and S.active))
end
local function watchDeath(context)
    local character=unwrap(context)
    if not valid(character) or not isExpeditionDeath() then return end
    captureDeath(character)
end
local function watchControllerKilled(context)
    local pc=unwrap(context)
    if not valid(pc) or not isExpeditionDeath() then return end
    local old=get(pc,"LastPlayerChar")
    if valid(old) then captureDeath(old) end
end
local function watchNewPawn(context,oldPawn,newPawn)
    local pc=unwrap(context)
    local pawn=unwrap(newPawn)
    if not valid(pc) or not valid(pawn) then return end
    S.newPawnEvents=S.newPawnEvents+1
    local entry=S.pending[path(pc)]
    if entry then entry.spawned=pawn;log("NEWPAWN event for pending death") end
end
local registered={}
local retries={}
local knownHooks={}
local function hook(f,pre,post)
    if not knownHooks[f] then knownHooks[f]={pre=pre,post=post} end
    if registered[f] then return end
    local now=os.clock()
    if retries[f] and now<retries[f] then return end
    retries[f]=now+CFG.RetryHookSeconds
    local ok,a,b=pcall(function() return RegisterHook(f,pre,post) end)
    if ok and a~=nil then
        registered[f]=true
        log("HOOK ACTIVE "..f)
    else
        log("HOOK NOT READY "..f.." (will retry): "..tostring(a))
    end
end
local function safePre(label,cb)
    return function(...)
        local ok,err=pcall(cb,...)
        if not ok then log("HOOK "..label.." callback failed: "..tostring(err)) end
    end
end
local function safePostBool(cb)
    return function(...)
        local ok,result=pcall(cb,...)
        if ok then return result end
    end
end
local function retryHooks()
    for f,spec in pairs(knownHooks) do
        if not registered[f] then hook(f,spec.pre,spec.post) end
    end
end
-- Native hooks run on the engine thread; no worker threads modify UObjects.
hook("/Script/Helden.HeldenCharacter:Die_Auth",
     safePre("Die_Auth",watchDeath))
hook("/Script/Helden.HeldenPlayerController:OnPlayerKilled",
     safePre("OnPlayerKilled",watchControllerKilled),
     safePre("OnPlayerKilledPost",watchControllerKilled))
hook("/Script/Helden.HeldenPlayerController:OnNewPawn",
     function() end,safePre("OnNewPawn",watchNewPawn))
if CFG.EnableNoPermadeath then
    -- Native post-hook return override, documented in UE4SS RegisterHook.
    -- A false result is intentionally restricted to the Expedition game
    -- mode and authoritative host; it does not touch normal saves.
    hook("/Script/Helden.HeldenGameState:HasFailedExpedition",
        function() end,
        safePostBool(function(context)
            local gs=unwrap(context)
            local ctx=onHost() and game()
            if valid(gs) and ctx and path(ctx.gs)==path(gs) then
                return false
            end
        end))
    hook("/Script/Helden.HeldenGameState:EndDungeonRunSequence_Multicast",
        safePre("EndDungeonRunSequence",function(context,statsArg)
            local gs=unwrap(context)
            local ctx=onHost() and game()
            if not ctx or path(ctx.gs)~=path(gs) then return end
            local stats=unwrap(statsArg)
            if get(stats,"bHaveFailed")==true then
                S.failed=true;S.recoveryRequired=true
                local depth=number(get(stats,"DungeonLevel"),0,CFG.MaxDepth)
                if depth and depth>S.depth then S.depth=depth end
                log("END RUN failure event; protected depth="..S.depth)
            end
        end))
    hook("/Script/Helden.HeldenElevatorMachine:CanBeInteracted",
        function() end,
        safePostBool(function(context)
            if not S.recoveryRequired or not onHost() then return end
            local ctx=game()
            if not ctx or (ctx.phase~=0 and ctx.phase~=3) then return end
            local machine=first("HeldenElevatorMachine")
            if valid(machine) and path(machine)==path(unwrap(context)) then return true end
        end))
end
-- Capture the destruction signal from the engine, not keyboard actions.
-- Health==0 handles direct damage. Multicast catches non-health-based breakage.
hook("/Script/Helden.HeldenPhysicsActor:OnHealthModifed",
     safePre("health",function(context) destructionEvent(context,"health") end))
hook("/Script/Helden.HeldenPhysicsActor:PlayDestructionEffect_Mulitcast",
     safePre("destruction",function(context) destructionEvent(context,"effect") end))
local function safePoll()
    local now=os.clock()
    if S.lastPoll>=0 and now>=S.lastPoll and now-S.lastPoll<CFG.PollSeconds then return end
    S.lastPoll=now
    retryHooks()
    local ok,err=pcall(poll)
    if not ok and not S.warned then
        S.warned=true;log("poll error: "..tostring(err))
    end
end
local function heartbeat()
    S.sample=S.sample+1
    if S.sample<CFG.AnimationSample then return end
    S.sample=0
    safePoll()
end
-- Persistent game-thread polling is crucial: when the final player dies,
-- BlueprintUpdateAnimation may stop entirely. UE4SS v3 has LoopAsync and
-- ExecuteInGameThread; v4 also has a direct game-thread timer.
local scheduled=false
if type(LoopInGameThreadWithDelay)=="function" then
    local ok=pcall(function()
        LoopInGameThreadWithDelay(450,function() safePoll() end)
    end)
    if ok then scheduled=true;log("game-thread timer active (450 ms)") end
elseif type(LoopAsync)=="function" and type(ExecuteInGameThread)=="function" then
    local ok=pcall(function()
        LoopAsync(450,function()
            pcall(function() ExecuteInGameThread(function() safePoll() end) end)
            return false
        end)
    end)
    if ok then scheduled=true;log("UE4SS v3 async timer -> game-thread queue active") end
end
if not scheduled then
    log("WARNING: no independent timer; animation-hook fallback may stop during party wipe")
    hook("/Game/Animation/ABP_HeldenPlayer.ABP_HeldenPlayer_C:BlueprintUpdateAnimation",
         function() heartbeat() end)
end
hook("/Script/Engine.PlayerController:ClientRestart",
     function()
         cache={};S.lastPoll=-1;S.sample=CFG.AnimationSample-1
         S.coinLedger={}
         S.dropQueue={};S.destructionSeen={}
     end)
log("v0.2.0-alpha loaded: automatic physical extraction drops; Expedition recovery diagnostics")
