-- Expedition Saver UE4SS mock suite. The native game is NOT running here.
local MAIN="ue4ss/Mods/ExpeditionSaver/Scripts/main.lua"
local function actor(fields)
    local a=fields or {}
    function a:IsValid() return self._valid~=false end
    function a:GetFullName() return self._name or tostring(self) end
    return a
end
local function fixture(useCoinNotifications)
    local now=0
    local coinCallbacks={}
    local registry,hooks,keys,files,logs,spawned={},{},{},{},{},{}
    local counts={clock=0,first=0,all=0,byClass={},respawn=0,teleport=0}
    local gm=actor({_name="GameMode /Game/GM"})
    local md={GameSlot=0,GameMode=1,bHasFailed=false}
    local save=actor({_name="SaveGame /Game/S0",MetaData=md,GameMode=1,
        DungeonLevel=2,TimePlayed=30,DungeonFails=0})
    local gi=actor({_name="HeldenGameInstance /Game/Instance",CurrentSaveGame=save})
    local lift=actor({_name="HeldenDungeonElevator /Game/Lift",InteriorCollisionBox=actor(),
        HomeStationIdx=0,CurrentStationIdx=0,bInteractionLocked=false})
    local machine=actor({_name="HeldenElevatorMachine /Game/Machine",bInteractionLocked=true})
    lift.ElevatorMachine=machine
    local function component()
        local c=actor()
        function c:SetCollisionEnabled(v) self.collision=v end
        function c:SetVisibility(v) self.visible=v end
        return c
    end
    local barrier=actor({_name="BP_ExpeditionFailed_Actor_C /Game/Maps/Helden_Expedition.Helden_Expedition:PersistentLevel.BP_ExpeditionFailed_Actor_C_1",
        bFailedExpedition=true,Box=component(),SM_SM_Door_Lock=component(),Cube=component()})
    function barrier:OnRep_bFailedExpedition() self.onrep=true end
    function barrier:UpdateCollisionSate() self.updated=true end
    function barrier:SetActorEnableCollision(v) self.collision=v end
    function machine:SetCanBeInteracted_Auth(value) self.interactionEnabled=value end
    function machine:OnRequirementSysUpdate_Auth() end
    function machine:OnDungeonRunStateChanged(r) self.lastRun=r.State end
    function lift.InteriorCollisionBox:K2_GetComponentLocation()
        return {X=1000,Y=2000,Z=300}
    end
    local dungeon=actor({CurrentSeed={Level=1}})
    local run={State=2,Flags=0,DungeonActor=dungeon}
    local gs=actor({_name="HeldenGameState /Game/GS",GameModeType=1,bExpeditionFailed=false,
        CurrentDungeonRun=run})
    function gs:OnRep_DungeonRunState() self.repCount=(self.repCount or 0)+1 end
    local stats=actor({CurrentHealth=120,TotalStats={MaxHealth=120}})
    local corpse=actor({_name="HeldenCharacter /Game/Old",EquipedItems={},CharacterStats=stats,
        Money={Gold=80,Artifacts=4,Scraps=17},ItemSlots={}})
    local newPawn=actor({_name="HeldenPlayerCharacter /Game/New",CharacterStats=
        actor({CurrentHealth=1,TotalStats={MaxHealth=120}}),
        Money={Gold=0,Artifacts=0,Scraps=0},
        ItemSlots={actor({_name="NewPlayerSlot 1"}),actor({_name="NewPlayerSlot 2"})},
        EquipedItems={}})
    function newPawn:K2_TeleportTo(at,rot)
        counts.teleport=counts.teleport+1
        self.location=at
        return true
    end
    local pc=actor({_name="HeldenPlayerController /Game/PC",LastPlayerChar=corpse})
    function corpse:GetController() return pc end
    function corpse:K2_GetActorLocation() return {X=1000,Y=2000,Z=300} end
    function pc:GetPawn() return self._pawn end
    pc._pawn=corpse
    function pc:IsLocalController() return true end
    function pc:RespawnCharacter_Server()
        counts.respawn=counts.respawn+1
        self._pawn=newPawn
    end
    local gearClass=actor({_name="Class /Game/BP_TestSword"})
    local item=actor({_name="HeldenEquipableItem /Game/A",CurrentInventorySlot=0,
        PreviousOwner=corpse,CurrentSlot=actor({_name="ItemSlot"})})
    function item:GetClass() return gearClass end
    function item:DetachFromAll() self.detached=true;self.CurrentSlot=nil end
    function item:SetSimulatePhysics(v) self.simulates=v end
    function item:Interact(player)
        self.PreviousOwner=player
        for i,slot in ipairs(player.ItemSlots or {}) do
            if not slot.CurrentItemInSlot then
                slot.CurrentItemInSlot=self
                self.CurrentSlot=slot
                self.CurrentInventorySlot=i-1
                return
            end
        end
    end
    corpse.ItemSlots={actor({CurrentItemInSlot=item})}
    function item:K2_TeleportTo(at,rot)
        self.location=at
        self.wasMoved=true
        return true
    end
    corpse.EquipedItems={item}
    registry.GameModeBase=gm;registry.HeldenGameInstance=gi
    registry.HeldenGameState=gs;registry.HeldenDungeonElevator=lift
    registry.HeldenElevatorMachine=machine
    registry.HeldenGameMode=gm
    local data=actor({_name="DataSingleton /Game/DS"})
    local coinClass=actor({_name="Class /Game/BP_ArtifactCoin"})
    local goldClass=actor({_name="Class /Game/BP_GoldCoin"})
    data.ArtifactCoinActorClass=coinClass
    data.GoldCoinActorClass=goldClass
    local physTable=actor()
    function physTable:FindRow(key)
        if tostring(key)=="RustyJunk" then
            return {Parsed_ScrapReward={Gold=45,Artifacts=2,Scraps=1}}
        end
    end
    data.PhysActorDataTable=physTable
    registry.HeldenDataSingleton=data
    local loot=actor({_name="HeldenConstructActor /Game/EpicLoot",ConstructQuality=2,
        OwningDungeon=dungeon,StatsComponent=actor({CurrentHealth=0})})
    function loot:K2_GetActorLocation() return {X=1000,Y=1980,Z=300} end
    function loot:GetInspectData() return {bIsInDungeon=true,Value={Gold=20,Artifacts=6,Scraps=5}} end
    function loot:K2_DestroyActor() self._valid=false end
    local itComp=actor()
    function itComp:GetOwner() return loot end
    pc.CurrentInteractTarget=itComp
    function newPawn:K2_GetActorLocation() return {X=1000,Y=2000,Z=300} end
    local world=actor({_name="World /Game/World"})
    function loot:GetWorld() return world end
    function newPawn:GetWorld() return world end
    function lift:GetWorld() return world end
    function world:SpawnActor(cls,loc,rot)
        assert(cls==coinClass or cls==goldClass or cls==gearClass)
        local coin=actor(cls==gearClass and {ItemDurability=0,ItemDataAsset=nil} or
            {Money={Artifacts=0,Gold=0,Scraps=0}})
        coin._coinClass=cls
        if cls==gearClass then
            function coin:Interact(player)
                self.PreviousOwner=player
                for i,slot in ipairs(player.ItemSlots or {}) do
                    if not slot.CurrentItemInSlot then
                        slot.CurrentItemInSlot=self
                        self.CurrentSlot=slot
                        self.CurrentInventorySlot=i-1
                        return
                    end
                end
            end
            function coin:DetachFromAll() end
            function coin:K2_TeleportTo(v) self._position=v;return true end
        else
            local root=actor()
            function root:SetMobility(m) self.mobility=m end
            function root:SetVisibility(v) self.visible=v end
            function root:SetCollisionEnabled(v) self.collision=v end
            function root:SetSimulatePhysics(v) self.simulates=v end
            function root:SetEnableGravity(v) self.gravity=v end
            function root:WakeAllRigidBodies() self.awake=true end
            function root:IsSimulatingPhysics() return self.simulates end
            function root:IsGravityEnabled() return self.gravity end
            function root:IsVisible() return self.visible end
            coin.RootMesh=root
        end
        coin._position={X=loc.X,Y=loc.Y,Z=loc.Z}
        function coin:K2_DestroyActor() self._valid=false end
        function coin:SetReplicates(v) self.replicates=v end
        function coin:SetActorHiddenInGame(v) self.hidden=v end
        function coin:SetActorEnableCollision(v) self.collision=v end
        function coin:K2_SetActorLocation(v) self._position=v;return true end
        function coin:K2_GetActorLocation() return self._position end
        function coin:GetClass() return self._coinClass end
        spawned[#spawned+1]={coin=coin,loc=loc}
        return coin
    end
    local listing={HeldenPlayerController={pc},HeldenEquipableItem={item},
        BP_ExpeditionFailed_Actor_C={barrier},HeldenPhysicsCoin={}}
    local clockcb
    local fakeio={open=function(fname,mode)
        if mode=="r" then
            local v=files[fname]
            if not v then return nil end
            return {read=function() return v:match("([^\r\n]+)") end,
                    close=function() end}
        end
        assert(mode=="w")
        return {write=function(_,text) files[fname]=text end,
                close=function() end}
    end}
    local env=setmetatable({
        os={clock=function() counts.clock=counts.clock+1;return now end,
            getenv=function() return "C:\\Users\\Tester\\AppData\\Local" end},
        io=fakeio,
        print=function(msg) logs[#logs+1]=msg end,
        FindFirstOf=function(cls) counts.first=counts.first+1;return registry[cls] end,
        FindAllOf=function(cls)
            counts.all=counts.all+1
            counts.byClass[cls]=(counts.byClass[cls] or 0)+1
            return listing[cls] or {}
        end,
        RegisterHook=function(name,pre,post)
            hooks[name]={pre=pre,post=post}
            return 100,101
        end,
        NotifyOnNewObject=useCoinNotifications and function(name,callback)
            coinCallbacks[name]=callback
        end or nil,
        RegisterKeyBind=function(key,callback) keys[key]=callback end,
        Key={F7=118},
        LoopInGameThreadWithDelay=function(ms,callback)
            assert(ms==300);clockcb=callback;return 1
        end,
        ExecuteInGameThread=function(callback) callback() end,
    },{__index=_G})
    env._G=env
    assert(loadfile(MAIN,"t",env))()
    assert(clockcb,"game-thread timer not registered")
    local test={
        gm=gm,save=save,md=md,gi=gi,gs=gs,run=run,
        lift=lift,machine=machine,barrier=barrier,
        pc=pc,corpse=corpse,newPawn=newPawn,item=item,loot=loot,
        world=world,registry=registry,listing=listing,spawned=spawned,
        hooks=hooks,keys=keys,logs=logs,files=files,counts=counts,
        coinCallbacks=coinCallbacks,
        tick=function(dt) now=now+(dt or 0.7);clockcb() end,
        killed=function()
            local h=hooks["/Script/Helden.HeldenCharacter:Die_Auth"]
            assert(h and h.pre)
            corpse.CharacterStats.CurrentHealth=0
            corpse.CharacterState=1
            h.pre(corpse)
        end,
        destroyLoot=function(direct)
            -- Legacy physics payout tests need a truly ambiguous co-op state.
            -- Default exposes two eligible player controllers without a native
            -- instigator; an explicit direct=true tests solo wallet credit.
            if not direct then
                local second=actor({_name="HeldenPlayerController /Game/Second"})
                local otherPawn=actor({_name="HeldenPlayerCharacter /Game/SecondPawn",
                    Money={Gold=0,Artifacts=0,Scraps=0},
                    CharacterStats=actor({CurrentHealth=100,
                        TotalStats={MaxHealth=100}})})
                function second:GetPawn() return otherPawn end
                function otherPawn:K2_GetActorLocation()
                    return {X=1010,Y=2000,Z=300}
                end
                listing.HeldenPlayerController[2]=second
            end
            local h=hooks["/Script/Helden.HeldenPhysicsActor:OnHealthModifed"]
            local d=hooks["/Script/Helden.HeldenPhysicsActor:PlayDestructionEffect_Mulitcast"]
            assert(h and d,"destruction hooks not registered")
            h.pre(loot)
            d.pre(loot)
        end,
        switchMode=function(mode)
            gs.GameModeType=mode;save.GameMode=mode;md.GameMode=mode
        end
    }
    return test
end
local passed=0
local function test(title,callback)
    callback()
    passed=passed+1
    print("PASS: "..title)
end
test("in expedition, depth and permadeath markers survive party wipe",function()
    local t=fixture()
    t.save.DungeonLevel=10;t.run.DungeonActor.CurrentSeed.Level=9
    t.tick()
    t.run.State=3;t.run.Flags=1;t.save.DungeonLevel=0
    t.md.bHasFailed=true;t.gs.bExpeditionFailed=true
    t.tick()
    assert(t.save.DungeonLevel==10,"depth must be restored")
    assert(t.md.bHasFailed==false and t.gs.bExpeditionFailed==false,
        "permadeath marker must clear on failed run")
end)
test("normal game is completely unchanged",function()
    local t=fixture()
    t.switchMode(0)
    t.md.bHasFailed=true
    t.gs.bExpeditionFailed=true
    t.run.State=3;t.run.Flags=1
    t.save.DungeonLevel=0
    t.tick()
    assert(t.save.DungeonLevel==0 and t.md.bHasFailed and t.gs.bExpeditionFailed)
    assert(t.counts.respawn==0)
end)
test("saved depth backup remains per-slot and never compounds",function()
    local t=fixture()
    t.save.DungeonLevel=5
    t.run.DungeonActor.CurrentSeed.Level=4
    t.tick()
    local count=0 for _ in pairs(t.files) do count=count+1 end
    assert(count==1 and t.files["C:\\Users\\Tester\\AppData\\Local\\Helden\\Saved\\ExpeditionSaver_slot0.txt"])
    t.tick()
    local count2=0 for _ in pairs(t.files) do count2=count2+1 end
    assert(count2==1)
end)
test("death of player uses native server respawn, then teleports to lift",function()
    local t=fixture()
    t.tick()
    t.killed()
    t.tick(1.5)
    assert(t.counts.respawn==1,"native server respawn should be requested")
    t.tick()
    assert(t.newPawn.location and t.newPawn.location.Z==380,"should respawn inside lift")
    assert(t.newPawn.CharacterStats.CurrentHealth==120,"health should restore")
    assert(t.counts.respawn==1,"no duplicate respawn")
end)
test("existing equipped item is picked into new pawn inventory, not left on elevator floor",function()
    local t=fixture();t.tick();t.killed();t.tick(1.5)
    for i=1,4 do t.tick(0) end
    assert(t.item.wasMoved and t.item.detached)
    assert(#t.spawned==0)
    assert(t.newPawn.ItemSlots[1].CurrentItemInSlot==t.item)
    assert(t.item.PreviousOwner==t.newPawn)
end)
test("respawn request still happens when the game prematurely ends the expedition",function()
    local t=fixture();t.tick();t.killed()
    t.run.State=3;t.run.Flags=1
    t.tick(2)
    assert(t.counts.respawn==1,"post-wipe recovery should not silently cancel death")
end)
test("AI character death is ignored",function()
    local t=fixture();t.tick()
    local npc=actor({_name="NPC /Game/Enemy"})
    local ai=actor({_name="AIController /Game/AI"})
    function npc:GetController() return ai end
    t.hooks["/Script/Helden.HeldenCharacter:Die_Auth"].pre(npc)
    t.tick(2)
    assert(t.counts.respawn==0)
end)
test("hammer destruction deposits Gold and Artifacts directly into nearest wallet",function()
    local t=fixture();t.tick();t.destroyLoot();t.tick(1)
    assert(#t.spawned==0,"furniture must never generate physical coins")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "Gold and Artifacts must be deposited directly")
    assert(t.loot._valid~=false,"mod must not destroy furniture itself")
    assert(t.keys[118]==nil,"F7 must not be registered")
end)
test("two destruction signals never double-pay the same loot",function()
    local t=fixture();t.tick()
    t.destroyLoot();t.destroyLoot();t.tick(1)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10)
    t.tick(1)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "duplicate destruction callbacks must never pay twice")
end)
test("scrap/resource payout remains native, no added scrap coin",function()
    local t=fixture();t.tick();t.destroyLoot();t.tick(1)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Scraps==17,"native scrap resource handling is unchanged")
end)
test("no rewards for actor outside dungeon",function()
    local t=fixture();t.tick()
    t.loot.OwningDungeon=nil
    t.loot.GetInspectData=function()
        return {bIsInDungeon=false,Value={Gold=40,Artifacts=8}}
    end
    t.destroyLoot();t.tick(1)
    assert(#t.spawned==0 and t.corpse.Money.Gold==80 and
        t.corpse.Money.Artifacts==4,"outside dungeon no Expedition reward")
end)
test("no payout for zero coin value",function()
    local t=fixture();t.tick()
    t.loot.GetInspectData=function()
        return {bIsInDungeon=true,Value={Gold=0,Artifacts=0,Scraps=10}}
    end
    t.destroyLoot();t.tick(1)
    assert(#t.spawned==0 and t.corpse.Money.Gold==80 and
        t.corpse.Money.Artifacts==4)
end)
test("coin actor assets are irrelevant to wallet-only rewards",function()
    local t=fixture();t.tick()
    t.registry.HeldenDataSingleton.ArtifactCoinActorClass=nil
    t.registry.HeldenDataSingleton.GoldCoinActorClass=nil
    t.destroyLoot();t.tick(1)
    assert(#t.spawned==0,"missing coin classes do not require physics fallback")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "currency is credited directly with no asset dependencies")
end)
test("PhysActorData fallback reads already patched QOL reward, without multiplying",function()
    local t=fixture();t.tick()
    t.loot.GetInspectData=nil
    t.loot.ConstructDataName="RustyJunk"
    t.destroyLoot();t.tick(1)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==125 and t.corpse.Money.Artifacts==6,
        "patched 45 Gold and 2 Artifacts must be credited once")
end)
test("hammer destruction below health zero is required for health trigger",function()
    local t=fixture();t.tick()
    t.loot.StatsComponent.CurrentHealth=10
    local h=t.hooks["/Script/Helden.HeldenPhysicsActor:OnHealthModifed"]
    h.pre(t.loot);t.tick(1)
    assert(#t.spawned==0)
    t.loot.StatsComponent.CurrentHealth=0
    h.pre(t.loot);t.tick(1)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "lethal callback must pay the solo player directly")
end)
test("elevator machine is unlocked after expedition wipe at home station",function()
    local t=fixture();t.tick()
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick(2)
    assert(t.run.State==0,"run must leave EndScreen")
    assert(t.run.Flags==0,"stale failure must be cleared")
    assert(t.machine.interactionEnabled==true)
    assert(t.machine.bInteractionLocked==false)
end)
test("elevator recovery defers if elevator has not reached home station",function()
    local t=fixture();t.tick()
    t.lift.CurrentStationIdx=1
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick(2)
    assert(t.run.State==3)
    assert(not t.machine.interactionEnabled)
end)
test("client-only mode never changes save or coins",function()
    local t=fixture();t.tick()
    t.gm._valid=false;t.registry.GameModeBase=nil
    t.run.State=3;t.run.Flags=1
    t.md.bHasFailed=true;t.gs.bExpeditionFailed=true
    t.tick()
    assert(t.md.bHasFailed and t.gs.bExpeditionFailed)
    t.destroyLoot();t.tick(1);assert(#t.spawned==0)
end)
test("a timer is independent of animation callback after all players die",function()
    local t=fixture()
    assert(t.hooks["/Game/Animation/ABP_HeldenPlayer.ABP_HeldenPlayer_C:BlueprintUpdateAnimation"]==nil,
        "timer should replace hot animation hook")
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick()
    assert(t.md.bHasFailed==false)
end)
test("do not detach items the game already equipped on respawn",function()
    local t=fixture();t.tick();t.killed()
    t.newPawn.EquipedItems={t.item}
    t.item.PreviousOwner=t.newPawn
    t.tick(1.5);t.tick()
    assert(t.item.detached~=true and not t.item.wasMoved,
        "native equipped items must remain in native inventory")
end)
test("do not convert Epic quest artifacts",function()
    local t=fixture();t.tick()
    t.loot.bIsQuestObjective=true
    t.destroyLoot();t.tick(1)
    assert(#t.spawned==0 and t.loot._valid~=false)
end)

test("HasFailedExpedition overridden only on authoritative Expedition",function()
    local t=fixture();t.tick()
    local cb=t.hooks["/Script/Helden.HeldenGameState:HasFailedExpedition"]
    assert(cb and type(cb.post)=="function","native post-hook missing")
    assert(cb.post(t.gs)==false,"must suppress permadeath in Expedition")
    t.switchMode(0)
    assert(cb.post(t.gs)==nil,"normal mode must be unaffected")
    t.switchMode(1)
    t.gm._valid=false;t.registry.GameModeBase=nil
    assert(cb.post(t.gs)==nil,"client may not override server failure")
end)
test("permadeath markers cleared during exploration, not only at end screen",function()
    local t=fixture();t.tick()
    t.md.bHasFailed=true;t.gs.bExpeditionFailed=true
    t.tick(1)
    assert(t.md.bHasFailed==false and t.gs.bExpeditionFailed==false)
end)

test("destroyed equipped item is reconstructed at most once and picked up",function()
    local t=fixture();t.tick();t.killed()
    t.item._valid=false
    for i=1,8 do t.tick(0) end
    assert(#t.spawned==1,"must spawn only one replacement")
    assert(t.newPawn.ItemSlots[1].CurrentItemInSlot==t.spawned[1].coin)
    for i=1,6 do t.tick(0) end
    assert(#t.spawned==1,"no second replacement after delivery")
end)

test("OnPlayerKilled post requests respawn in the same engine event",function()
    local t=fixture();t.tick();t.killed()
    local event=t.hooks["/Script/Helden.HeldenPlayerController:OnPlayerKilled"]
    assert(event and event.post)
    event.post(t.pc)
    assert(t.counts.respawn==1,"must not wait for wipe/end screen")
    t.tick(1)
    assert(t.newPawn.location and t.newPawn.location.Z==380)
    assert(t.counts.respawn==1,"no double native respawn")
end)
test("Expedition mode recovery accepts metadata after runtime mode resets",function()
    local t=fixture();t.tick()
    t.gs.GameModeType=0
    t.save.GameMode=1;t.md.GameMode=1
    t.md.bHasFailed=true
    t.tick(1)
    assert(t.md.bHasFailed==false)
end)

test("real HeldenConstructActor getter and weak dungeon pointer produce QOL payout",function()
    local t=fixture();t.tick(0)
    t.loot.GetInspectData=nil
    t.loot.OwningDungeon={Get=function() return t.run.DungeonActor end}
    function t.loot:GetConstructAssetData()
        return {Parsed_ScrapValue_Epic={Gold=60,Artifacts=4,Scraps=5}}
    end
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==140 and t.corpse.Money.Artifacts==8)
    assert(t.corpse.Money.Scraps==17)
end)
test("physics loot with no GetInspectData uses patched PhysActorData and weak ownership",function()
    local t=fixture();t.tick(0)
    t.loot.GetInspectData=nil
    t.loot.OwningDungeon={Get=function() return t.run.DungeonActor end}
    t.loot.StatsDataName="RustyJunk"
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==125 and t.corpse.Money.Artifacts==6)
end)
test("respawn and loot payout do not wait for os.clock CPU time",function()
    local t=fixture();t.tick(0);t.killed()
    t.tick(0)
    assert(t.counts.respawn==1,"respawn starts on engine tick")
    t.tick(0)
    assert(t.newPawn.location and t.newPawn.location.Z==380)
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0)
    assert(t.newPawn.Money.Gold==100 and t.newPawn.Money.Artifacts==10,
        "furniture wallet payout must not need CPU time to elapse")
end)
test("run recovery starts on failed EndScreen even without earlier exploring heartbeat",function()
    local t=fixture()
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick(0)
    assert(t.run.State==0 and not t.md.bHasFailed)
    assert(t.machine.interactionEnabled==true)
end)
test("same-slot save instance swap retains depth and recovery",function()
    local t=fixture();t.save.DungeonLevel=8;t.tick(0)
    local newSave=actor({_name="SaveGame /Game/S0_new",MetaData={GameSlot=0,GameMode=1,bHasFailed=true},
        GameMode=1,DungeonLevel=0,TimePlayed=30,DungeonFails=0})
    t.gi.CurrentSaveGame=newSave
    t.run.State=3;t.run.Flags=1;t.tick(0)
    assert(newSave.DungeonLevel==8,"depth should survive save object rotation")
    assert(newSave.MetaData.bHasFailed==false)
end)

test("the physical Expedition Failed door is actually disabled",function()
    local t=fixture();t.tick()
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick(2)
    assert(t.barrier.bFailedExpedition==false)
    assert(t.barrier.onrep and t.barrier.updated)
    assert(t.barrier.collision==false)
    assert(t.barrier.Box.collision==0)
    assert(t.barrier.SM_SM_Door_Lock.visible==false)
end)
test("poll detects player death without Die_Auth or OnPlayerKilled callbacks",function()
    local t=fixture()
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    t.tick(0)
    t.corpse.CharacterState=1;t.corpse.CharacterStats.CurrentHealth=0
    t.tick(0)
    assert(t.counts.respawn==1,"must respawn on observed Dead character state")
    t.tick(0)
    assert(t.newPawn.location and t.newPawn.location.Z==380)
end)
test("furniture currency never creates physics actors or coin meshes",function()
    local t=fixture();t.tick(0)
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0,"no actor/physics/gravity operations for furniture money")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "currency is stored in player wallet only")
end)
test("zero inspect payout falls back to patched live table",function()
    local t=fixture();t.tick(0)
    t.loot.GetInspectData=function()
        return {bIsInDungeon=true,Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.loot.StatsDataName="RustyJunk"
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==125 and t.corpse.Money.Artifacts==6)
end)
test("nil game mode is safely stringified in diagnostic heartbeat",function()
    local t=fixture()
    t.gs.GameModeType=nil
    t.save.GameMode=nil;t.md.GameMode=nil
    t.tick(0)
    for _,line in ipairs(t.logs) do assert(not line:find("poll error",1,true)) end
end)

test("after native respawn RPC is ignored, revive original pawn instead of soul",function()
    local t=fixture()
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    function t.corpse:K2_TeleportTo(at) self.location=at;return true end
    function t.pc:Possess(pawn) self._pawn=pawn end
    function t.pc:ClientRestart(pawn) self._clientRestarted=true end
    function t.corpse:OnRep_CharacterState() self.replicatedState=true end
    t.tick(0)
    t.corpse.CharacterState=1;t.corpse.CharacterStats.CurrentHealth=0
    t.pc.RespawnCharacter_Server=function(self)
        t.counts.respawn=t.counts.respawn+1
        -- Simulates server rejecting native respawn in Expedition EndScreen
    end
    for i=1,18 do t.tick(0) end
    assert(t.counts.respawn==3,"must try native respawn first")
    assert(t.pc:GetPawn()==t.corpse,"must possess original pawn after failed RPCs")
    assert(t.corpse.CharacterState==0 and t.corpse.CharacterStats.CurrentHealth==120)
    assert(t.corpse.location.Z==380 and t.pc._clientRestarted)
end)
test("possessed soul is never mistaken for a successfully respawned player",function()
    local t=fixture()
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    t.tick(0)
    t.corpse.CharacterState=1;t.corpse.CharacterStats.CurrentHealth=0
    local soul=actor({_name="HeldenSoul /Game/Soul",CharacterStats=
        actor({CurrentHealth=5,TotalStats={MaxHealth=10}})})
    t.pc.SoulCharacter=soul
    t.pc._pawn=soul
    t.pc.RespawnCharacter_Server=function(self)
        t.counts.respawn=t.counts.respawn+1
    end
    t.tick(0)
    assert(t.counts.respawn==1,"soul should not count as native respawn")
    assert(not soul.location,"soul must not be teleported to lift as player")
end)

test("OnRep Dead hook catches player death without native Die_Auth callback",function()
    local t=fixture()
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    t.tick(0)
    local h=t.hooks["/Script/Helden.HeldenCharacter:OnRep_CharacterState"]
    assert(h and h.pre,"replicated dead-state hook must be registered")
    t.corpse.CharacterState=1;t.corpse.CharacterStats.CurrentHealth=0
    h.pre(t.corpse)
    t.tick(0)
    assert(t.counts.respawn==1)
end)
test("end-of-run failure queues a tracked player even when original actor vanished",function()
    local t=fixture()
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    t.tick(0)
    t.corpse._valid=false
    t.run.State=3;t.run.Flags=1
    t.tick(0)
    assert(t.counts.respawn==1,"failed run must not require old Pawn still existing")
end)

test("all three carried currencies survive a normal native respawn",function()
    local t=fixture();t.tick(0);t.killed()
    for i=1,6 do t.tick(0) end
    assert(t.newPawn.Money.Gold==80)
    assert(t.newPawn.Money.Artifacts==4)
    assert(t.newPawn.Money.Scraps==17)
    for i=1,5 do t.tick(0) end
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4,
        "restoring money twice must not duplicate currency")
end)
test("native respawn keeps higher balances while recovering missing currencies",function()
    local t=fixture();t.newPawn.Money.Gold=150;t.newPawn.Money.Artifacts=2
    t.tick(0);t.killed()
    for i=1,5 do t.tick(0) end
    assert(t.newPawn.Money.Gold==150)
    assert(t.newPawn.Money.Artifacts==4)
    assert(t.newPawn.Money.Scraps==17)
end)
test("inventory slots not listed under EquipedItems are also recovered",function()
    local t=fixture()
    local item2=actor({_name="HeldenEquipableItem /Game/B",CurrentInventorySlot=1,
        PreviousOwner=t.corpse,CurrentSlot=actor({_name="OldSlot2"})})
    function item2:GetClass() return t.item:GetClass() end
    function item2:DetachFromAll() self.CurrentSlot=nil end
    function item2:SetSimulatePhysics(v) end
    function item2:K2_TeleportTo(v) self.location=v;return true end
    item2.Interact=t.item.Interact
    t.corpse.ItemSlots[2]=actor({CurrentItemInSlot=item2})
    t.listing.HeldenEquipableItem[2]=item2
    t.corpse.CharacterState=0;t.corpse.CharacterStats.CurrentHealth=120
    t.tick(0)
    t.corpse.CharacterState=1;t.corpse.CharacterStats.CurrentHealth=0
    for i=1,8 do t.tick(0) end
    assert(t.newPawn.ItemSlots[1].CurrentItemInSlot==t.item)
    assert(t.newPawn.ItemSlots[2].CurrentItemInSlot==item2)
    assert(item2.PreviousOwner==t.newPawn)
end)
test("default physics treasure uses mesh-matched live QOL PhysActorData reward",function()
    local t=fixture();t.tick(0)
    t.loot.GetInspectData=function()
        return {bIsInDungeon=true,Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.loot.GetConstructAssetData=function()
        return {Parsed_ScrapValue_Epic={Gold=0,Artifacts=0}}
    end
    local m=actor({_name="StaticMesh /Game/TreasureMesh"})
    t.loot.RootMesh=actor({StaticMesh=m})
    t.registry.HeldenDataSingleton.PhysTreasureContainer=
        actor({TreasureData={{DataName="RustyJunk",StaticMesh=m}}})
    t.destroyLoot();t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==125 and t.corpse.Money.Artifacts==6,
        "live table loot value must go into wallet without physics")
end)
test("failed native pickup never destroys the only surviving item",function()
    local t=fixture()
    t.item.Interact=function() error("game rejected pickup") end
    t.tick(0);t.killed()
    for i=1,30 do t.tick(0) end
    assert(t.item:IsValid())
    assert(t.item.location and t.item.location.Z>=380,
        "unrecovered object must still be at elevator")
    assert(t.newPawn.ItemSlots[1].CurrentItemInSlot==nil)
    local warned=false
    for _,line in ipairs(t.logs) do
        if line:find("floor_or_missing=1",1,true) then warned=true end
    end
    assert(warned,"must not falsely report fully restored inventory")
end)

-- Death currency cleanup scenarios use real currency actors (not item actors).
local function makeCoin(t,id,money,x,age,world)
    local c=actor({_name="HeldenPhysicsCoin /Game/"..id,Money=money})
    function c:K2_GetActorLocation()
        return {X=x or 1010,Y=2000,Z=300}
    end
    function c:GetGameTimeSinceCreation() return age or 0.5 end
    function c:GetWorld() return world or t.world end
    function c:K2_DestroyActor() self._valid=false;self.destroyed=true end
    t.listing.HeldenPhysicsCoin[#t.listing.HeldenPhysicsCoin+1]=c
    return c
end

test("exact native death drop of all three currencies is consumed once",function()
    local t=fixture()
    t.tick(0);t.killed()
    local gold=makeCoin(t,"death_gold",{Gold=80,Artifacts=0,Scraps=0})
    local artifacts=makeCoin(t,"death_artifact",{Gold=0,Artifacts=4,Scraps=0},1020)
    local scrap=makeCoin(t,"death_scrap",{Gold=0,Artifacts=0,Scraps=17},1030)
    for _=1,8 do t.tick(0) end
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4 and
           t.newPawn.Money.Scraps==17,"wallet must survive")
    assert(gold.destroyed and artifacts.destroyed and scrap.destroyed,
           "all strictly matched death currency must be removed")
    assert(gold.Money.Gold==0 and artifacts.Money.Artifacts==0 and
           scrap.Money.Scraps==0,"currency must be zeroed before removal")
    assert(t.item:IsValid(),"physical equipment must never be destroyed")
    for _=1,10 do t.tick(0) end
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4,
           "repeated ticks must not add currency")
end)

test("pre-existing money on floor remains untouched even if value matches",function()
    local t=fixture()
    local existing=makeCoin(t,"old_coin",
        {Gold=80,Artifacts=4,Scraps=17})
    t.corpse.CharacterState=0
    t.corpse.CharacterStats.CurrentHealth=120
    for _=1,4 do t.tick(0) end
    t.corpse.CharacterState=1
    t.corpse.CharacterStats.CurrentHealth=0
    for _=1,9 do t.tick(0) end
    assert(existing:IsValid() and not existing.destroyed,
           "pre-existing physical currency is not a native death drop")
    assert(existing.Money.Gold==80)
    assert(t.newPawn.Money.Gold==80)
end)

test("partial native death drop is removed without needing exact full wallet sum",function()
    local t=fixture()
    t.tick(0);t.killed()
    local near=makeCoin(t,"partial_death_currency",
        {Gold=40,Artifacts=4,Scraps=0})
    for _=1,9 do t.tick(0) end
    assert(near.destroyed and near.Money.Gold==0,
        "native partial coin must be removed only after wallet is restored")
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4)
    assert(t.item:IsValid(),"death money cleanup never destroys equipment")
end)

test("new coins exceeding wallet budget are not deleted",function()
    local t=fixture()
    t.tick(0);t.killed()
    local unrelated=makeCoin(t,"too_large_coin",
        {Gold=500,Artifacts=0,Scraps=0})
    for _=1,9 do t.tick(0) end
    assert(unrelated:IsValid() and unrelated.Money.Gold==500)
    assert(t.newPawn.Money.Gold==80)
end)

test("stale death-area coins cannot be removed",function()
    local t=fixture()
    t.tick(0);t.killed()
    local stale=makeCoin(t,"stale_gold",
        {Gold=80,Artifacts=4,Scraps=17},1010,35)
    for _=1,9 do t.tick(0) end
    assert(stale:IsValid() and stale.Money.Gold==80)
end)

test("distant fresh coins cannot be mistaken for native death drop",function()
    local t=fixture()
    t.tick(0);t.killed()
    local other=makeCoin(t,"remote_gold",
        {Gold=80,Artifacts=4,Scraps=17},2000)
    for _=1,9 do t.tick(0) end
    assert(other:IsValid() and other.Money.Gold==80)
end)

test("currency must not be destroyed if respawned pawn has no valid wallet",function()
    local t=fixture()
    t.newPawn.Money=nil
    t.tick(0);t.killed()
    local gold=makeCoin(t,"not_funded",
        {Gold=80,Artifacts=4,Scraps=17})
    for _=1,9 do t.tick(0) end
    assert(gold:IsValid() and not gold.destroyed)
    assert(gold.Money.Gold==80)
    assert(t.item:IsValid())
end)

test("fresh same-value currency from a different world must not be removed",function()
    local t=fixture()
    function t.corpse:GetWorld() return t.world end
    t.tick(0);t.killed()
    local otherWorld=actor({_name="World /Game/Other"})
    local elsewhere=makeCoin(t,"other_world",
        {Gold=80,Artifacts=4,Scraps=17},1010,0.5,otherWorld)
    for _=1,9 do t.tick(0) end
    assert(elsewhere:IsValid() and not elsewhere.destroyed)
    assert(t.newPawn.Money.Gold==80)
end)

test("solo furniture reward credits wallet directly without coin actors",function()
    local t=fixture()
    t.tick(0)
    t.destroyLoot(true)
    t.tick(0)
    assert(#t.spawned==0,"direct payout must not spawn physical coin actors")
    assert(t.corpse.Money.Gold==100)
    assert(t.corpse.Money.Artifacts==10)
    t.destroyLoot(true)
    t.tick(0)
    assert(t.corpse.Money.Gold==100,"two hooks must not credit twice")
end)

test("verified projectile damage targets correct co-op player",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/P2"})
    local secondPawn=actor({_name="HeldenPlayerCharacter /Game/P2Pawn",
        Money={Gold=5,Artifacts=1,Scraps=9}})
    function second:GetPawn() return secondPawn end
    t.listing.HeldenPlayerController[2]=second
    local projectile=actor()
    function projectile:GetInstigatorController() return second end
    t.tick(0)
    local h=t.hooks["/Script/Helden.HeldenProjectile:OnDamagedActor"]
    assert(h and h.pre,"reflected projectile damage hook is required")
    h.pre(projectile,nil,t.loot)
    t.destroyLoot(true)
    t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==80)
    assert(secondPawn.Money.Gold==25 and secondPawn.Money.Artifacts==7)
    assert(secondPawn.Money.Scraps==9,"destroy reward must not touch scrap")
end)

test("victim actor instigator cannot steal payout from uniquely close player",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/P2"})
    local secondPawn=actor({_name="HeldenPlayerCharacter /Game/P2Pawn",
        Money={Gold=5,Artifacts=1,Scraps=9}})
    function second:GetPawn() return secondPawn end
    function secondPawn:K2_GetActorLocation()
        return {X=2500,Y=2000,Z=300}
    end
    t.listing.HeldenPlayerController[2]=second
    function t.loot:GetInstigatorController() return second end
    t.tick(0)
    t.destroyLoot(true)
    t.tick(0)
    assert(#t.spawned==0,"unique nearby melee player should get direct credit")
    assert(t.corpse.Money.Gold==100,
        "victim GetInstigator must not override actual nearby player")
    assert(secondPawn.Money.Gold==5)
end)

test("ambiguous multiplayer awards nearest player without any physical coins",function()
    local t=fixture();t.tick(0)
    t.destroyLoot();t.tick(0)
    local second=t.listing.HeldenPlayerController[2]:GetPawn()
    assert(#t.spawned==0,"ambiguous multiplayer is no excuse for a coin drop")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "closer player must receive currency")
    assert(second.Money.Gold==0 and second.Money.Artifacts==0)
end)

test("dead co-op partner is excluded from eligible recipient positions",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/DeadPartner"})
    local deadSoul=actor({_name="HeldenCharacterSoul /Game/Soul"})
    function second:GetPawn() return deadSoul end
    t.listing.HeldenPlayerController[2]=second
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "only eligible living player gets the reward directly")
end)

test("two damage sources fall back to nearest player wallet",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/P2"})
    local secondPawn=actor({_name="HeldenPlayerCharacter /Game/P2Pawn",
        Money={Gold=5,Artifacts=1,Scraps=9}})
    function second:GetPawn() return secondPawn end
    function secondPawn:K2_GetActorLocation()
        return {X=1010,Y=2000,Z=300}
    end
    t.listing.HeldenPlayerController[2]=second
    local hit=t.hooks["/Script/Helden.HeldenProjectile:OnDamagedActor"]
    assert(hit and hit.pre)
    local p1=actor();local p2=actor()
    function p1:GetInstigatorController() return t.pc end
    function p2:GetInstigatorController() return second end
    t.tick(0)
    hit.pre(p1,nil,t.loot);hit.pre(p2,nil,t.loot)
    t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0,"simultaneous damage uses nearest, not physical coins")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10)
    assert(secondPawn.Money.Gold==5)
end)

test("Story mode native death respawns and recovers wallet plus inventory",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDungeonElevator=nil
    t.registry.HeldenElevator=nil
    t.tick(0)
    t.killed()
    for _=1,8 do t.tick(0) end
    assert(t.counts.respawn==1,
        "native respawn must work in Story Default=0")
    assert(t.newPawn.location and t.newPawn.location.X==1000,
        "Story should preserve a valid native spawn location")
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4
        and t.newPawn.Money.Scraps==17,"wallet survives Story death")
    assert(t.newPawn.ItemSlots[1].CurrentItemInSlot==t.item,
        "Story must recover held items")
    assert(t.save.DungeonLevel==2,
        "Story respawn never mutates Expedition depth")
end)

test("Story furniture rewards are paid directly even without dungeon owner",function()
    local t=fixture()
    t.switchMode(0)
    t.loot.OwningDungeon=nil
    t.loot.GetInspectData=function()
        return {bIsInDungeon=false,
            Value={Gold=20,Artifacts=6,Scraps=5}}
    end
    t.tick(0)
    t.destroyLoot(true)
    t.tick(0)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "Story Gold and tokens go straight into wallet")
    assert(#t.spawned==0,
        "no physics coins when Story receiver is known")
end)

test("Story death with currency drops removes coins, not equipment",function()
    local t=fixture()
    t.switchMode(0)
    t.tick(0)
    t.killed()
    local dropped=makeCoin(t,"story_death_drop",
        {Gold=80,Artifacts=4,Scraps=0})
    for _=1,10 do t.tick(0) end
    assert(t.newPawn.Money.Gold==80)
    assert(dropped.destroyed,"Story duplicated money drops must be removed")
    assert(t.item:IsValid(),"never destroy dropped gear")
end)

test("Story failure does not modify Expedition-only failure flags",function()
    local t=fixture()
    t.switchMode(0)
    t.tick(0)
    t.md.bHasFailed=true
    t.gs.bExpeditionFailed=true
    t.run.State=3;t.run.Flags=1
    t.tick(0)
    assert(t.md.bHasFailed and t.gs.bExpeditionFailed,
        "Expedition save repairs must remain disabled in Story")
end)

test("recent weapon attack identifies co-op killer even when both players stand close",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/OtherPlayer"})
    local pawn=actor({_name="HeldenPlayerCharacter /Game/OtherPawn",
        Money={Gold=10,Artifacts=1,Scraps=2}})
    function second:GetPawn() return pawn end
    function pawn:K2_GetActorLocation() return {X=1010,Y=2000,Z=300} end
    t.listing.HeldenPlayerController[2]=second
    local weapon=actor({_name="HeldenWeapon /Game/OtherHammer",
        PreviousOwner=pawn})
    t.tick(0)
    local attack=t.hooks["/Script/Helden.HeldenWeapon:Attack_Server"]
    assert(attack and attack.pre,"real server weapon action must be hooked")
    attack.pre(weapon)
    t.destroyLoot(true)
    t.tick(0)
    assert(#t.spawned==0,
        "actual attacker receives direct payout even with both nearby")
    assert(t.corpse.Money.Gold==80,
        "non-attacking nearby player must never receive gold")
    assert(pawn.Money.Gold==30 and pawn.Money.Artifacts==7)
end)

test("simultaneous weapon attacks fall back to nearest player with no drop",function()
    local t=fixture()
    local second=actor({_name="HeldenPlayerController /Game/OtherPlayer"})
    local pawn=actor({_name="HeldenPlayerCharacter /Game/OtherPawn",
        Money={Gold=10,Artifacts=1,Scraps=2}})
    function second:GetPawn() return pawn end
    function pawn:K2_GetActorLocation() return {X=1010,Y=2000,Z=300} end
    t.listing.HeldenPlayerController[2]=second
    local weapon1=actor({_name="HeldenWeapon /Game/Hammer1",PreviousOwner=t.corpse})
    local weapon2=actor({_name="HeldenWeapon /Game/Hammer2",PreviousOwner=pawn})
    t.tick(0)
    local attack=t.hooks["/Script/Helden.HeldenWeapon:Attack_Server"]
    attack.pre(weapon1);attack.pre(weapon2)
    t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0,"multiple attackers fall back to nearest player wallet")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10)
    assert(pawn.Money.Gold==10)
end)

test("nearest player receives reward even with a one-millimeter difference",function()
    local t=fixture()
    local other=actor({_name="HeldenPlayerController /Game/Nearer"})
    local pawn=actor({_name="HeldenPlayerCharacter /Game/NearerPawn",
        Money={Gold=10,Artifacts=1,Scraps=9}})
    function other:GetPawn() return pawn end
    -- Loot is at Y=1980. Original player is at Y=2000 (20cm),
    -- second player at Y=1999.9 (19.9cm): exactly a 1mm difference.
    function pawn:K2_GetActorLocation()
        return {X=1000,Y=1999.9,Z=300}
    end
    t.listing.HeldenPlayerController[2]=other
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==80)
    assert(pawn.Money.Gold==30 and pawn.Money.Artifacts==7,
        "1mm must select the closer player with no tolerance band")
end)

test("an exact distance tie is broken deterministically by controller name",function()
    local t=fixture()
    local other=actor({_name="HeldenPlayerController /Game/A_First"})
    local pawn=actor({_name="HeldenPlayerCharacter /Game/TiedPawn",
        Money={Gold=10,Artifacts=1,Scraps=9}})
    function other:GetPawn() return pawn end
    function pawn:K2_GetActorLocation()
        return {X=1000,Y=2000,Z=300}
    end
    t.listing.HeldenPlayerController[2]=other
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0)
    assert(t.corpse.Money.Gold==80)
    assert(pawn.Money.Gold==30 and pawn.Money.Artifacts==7)
end)

test("missing wallet defers reward without spawning physical currency",function()
    local t=fixture()
    t.tick(0)
    t.corpse.Money=nil
    t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0)
    t.corpse.Money={Gold=80,Artifacts=4,Scraps=17}
    t.tick(0)
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "queued payout must deliver after the recipient has a wallet")
    assert(#t.spawned==0)
end)

test("Story furniture wallet reward does not require World actor",function()
    local t=fixture()
    t.switchMode(0)
    function t.loot:GetWorld() return nil end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0,"wallet-only payout must never create coin actors")
    assert(t.corpse.Money.Gold==100 and t.corpse.Money.Artifacts==10,
        "Story furniture with a valid position must award even without World")
end)

test("Story trash native Gold resource pays wallet with zero inspect value",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.RandomMoneySpawn={Type="EHeldenResource::Gold",Amount=7}
    t.loot.MoneySpawnChance=1
    t.loot.bCanSpawnLoot=true
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Value={Gold=0,Artifacts=0,Scraps=9}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==87 and t.corpse.Money.Artifacts==4)
    assert(#t.spawned==0)
end)

test("Story trash native Artifact Coins resource pays wallet",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.RandomMoneySpawn={Type="EHeldenResource::Artifacts",Amount=3}
    t.loot.MoneySpawnChance=100 -- 100 percent also supported
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==80 and t.corpse.Money.Artifacts==7)
    assert(#t.spawned==0)
end)

test("Story native resource configured as Scraps never fabricates Gold or tokens",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.RandomMoneySpawn={Type=0,Amount=200}
    t.loot.MoneySpawnChance=100
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==80 and t.corpse.Money.Artifacts==4)
    assert(t.corpse.Money.Scraps==17 and #t.spawned==0)
end)

test("Story physics resource amount pays both currencies when no table",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.ResourceDropAmount={Gold=6,Artifacts=2,Scraps=10}
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Value={Gold=0,Artifacts=0,Scraps=10}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==86 and t.corpse.Money.Artifacts==6)
    assert(t.corpse.Money.Scraps==17)
    assert(#t.spawned==0)
end)

test("Story destroy collision multicast pays only dead furniture",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.RandomMoneySpawn={Type=1,Amount=8}
    t.loot.MoneySpawnChance=1
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.tick(0)
    local h=t.hooks["/Script/Helden.HeldenConstructActor:DisableCollision_Multicast"]
    assert(h and h.pre)
    t.loot.StatsComponent.CurrentHealth=12
    h.pre(t.loot);t.tick(0)
    assert(t.corpse.Money.Gold==80,
        "construct placement/collision must not accidentally pay")
    t.loot.StatsComponent.CurrentHealth=0
    h.pre(t.loot);t.tick(0)
    assert(t.corpse.Money.Gold==88 and #t.spawned==0,
        "destroyed Story construct must credit native reward")
    h.pre(t.loot);t.tick(0)
    assert(t.corpse.Money.Gold==88,"no duplicate payout from repeated multicast")
end)

test("healthy gameplay amortizes coin inventory and controller UObject scans",function()
    local t=fixture()
    for i=1,65 do t.tick(0) end
    local c=t.counts.byClass
    assert((c.HeldenPhysicsCoin or 0)<=4,
        "full coin snapshot may run at most about every 9s when healthy")
    assert((c.HeldenEquipableItem or 0)<=4,
        "world item scan must be cached instead of every 1.2s")
    assert((c.HeldenPlayerController or 0)<=10,
        "world controller list must be reused across game-thread polls")
end)

test("critical health refreshes coin baseline more often for death safety",function()
    local t=fixture()
    t.tick(0)
    local before=t.counts.byClass.HeldenPhysicsCoin or 0
    t.corpse.CharacterStats.CurrentHealth=20
    for i=1,10 do t.tick(0) end
    local after=t.counts.byClass.HeldenPhysicsCoin or 0
    assert(after>before,"low-health baseline must refresh near death")
end)

test("native death coin cleanup does not rescan the whole world every poll",function()
    local t=fixture()
    t.tick(0);t.killed()
    -- Native coins may arrive late; the cleanup window stays active
    -- without doing a massive UObject search every 300ms.
    for i=1,25 do t.tick(0) end
    local count=t.counts.byClass.HeldenPhysicsCoin or 0
    assert(count<=7,"death cleanup should use a bounded 2.4s scan cadence")
    assert(t.newPawn.Money.Gold==80 and t.newPawn.Money.Artifacts==4)
end)

test("Story convertible scrap value yields Gold even with zero native Gold payout",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,Quality=1,XP=8,
            Value={Gold=0,Artifacts=0,Scraps=12}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(#t.spawned==0,"the reward is always credited to wallet")
    assert(t.corpse.Money.Gold==116,
        "valuable furniture with 12 scraps should grant 36 Gold")
    assert(t.corpse.Money.Artifacts==5,
        "rare furniture should grant one Artifact Coin")
    assert(t.corpse.Money.Scraps==17,"native scraps must be unchanged")
end)

test("Story XP value can fund Gold when item has no money or scrap field",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    t.loot.ConstructQuality=0
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,XP=24,Quality=0,
            Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==84 and t.corpse.Money.Artifacts==4)
    assert(#t.spawned==0)
end)

test("Story no-value item cannot create arbitrary currencies",function()
    local t=fixture()
    t.switchMode(0)
    t.registry.HeldenDataSingleton=nil
    function t.loot:GetInspectData()
        return {bIsInDungeon=false,XP=0,Quality=0,
            Value={Gold=0,Artifacts=0,Scraps=0}}
    end
    t.tick(0);t.destroyLoot(true);t.tick(0)
    assert(t.corpse.Money.Gold==80 and t.corpse.Money.Artifacts==4)
end)

test("nonexistent HeldenDamageBox overlap hook is never registered",function()
    local t=fixture()
    assert(t.hooks["/Script/Helden.HeldenDamageBoxComponent:OnTriggerOverlapBegin"]==nil)
    t.tick(0)
    assert(t.hooks["/Script/Helden.HeldenProjectile:OnDamagedActor"],
        "valid projectile hook must remain")
end)

test("coin construction notifications replace all recurring global baseline scans",function()
    local t=fixture(true)
    local notify=t.coinCallbacks["/Script/Helden.HeldenPhysicsCoin"]
    assert(notify,"UE4SS coin object notification should register once")
    t.tick(0)
    local first=t.counts.byClass.HeldenPhysicsCoin or 0
    for i=1,90 do t.tick(0) end
    assert((t.counts.byClass.HeldenPhysicsCoin or 0)==first,
        "healthy Story gameplay must never issue a repeating registry sweep")
end)

print("ALL TESTS PASSED ("..passed..")")
