-- 16_vril_forge.lua : Vril Forge (live; vendor window 2026-10-24). Token 900090, Vril Sigil 900091, artifact grants, glow, Black Sun sphere,
-- M+ sigil drops, bot sigil strip. Item IDs follow gen_vril_stage.py / VRIL-MASTER.csv formulas. Needs the staged SQL + one restart first.
-- Effects are pure spell data (sql/04_effects.sql + client Spell.dbc): item spell links, spell_proc, spell_group 1200/1201. No Lua needed for them.
-- Rule: one weapon effect + one off-hand effect (OH half of a pair carries no spell). Agility/ranged paths also get a 'Swift Bulwark' (Agi shield).
local TOKEN, SIGIL       = 900090, 900091
local PRICE_SINGLE, PRICE_PAIR, PRICE_OFF = 25, 30, 15      -- sigils
local PRICE_GOLD         = 50000000                         -- 5000g in copper (flat, decided 22:03 MT)
local GLOW_BASE          = 3884                             -- spellitemenchantment 3884 + path
local SPHERE, SPHERE_DISPLAY, SPHERE_SCALE = 601400, 29270, 15   -- update after the sphere test
local SOUND              = 12559
local PHASE_BIT          = 0x40000000
local TXT_MAIN, TXT_WEAP, TXT_PAIR, TXT_OFF = 6011010, 6011011, 6011012, 6011013
local MAIL_STATIONERY    = 41
local FORGE_MENU         = 6011020                          -- player-gossip menu id for the .blacksun opener (fix 2026-10-11)
-- 2026-10-24 (armory-vendor / extcost-vendors): the Forge's wares open as a vendor window on a "Vril Forge" clerk (creature 601500)
-- that only you can see (Black Sun phase). List 601501 + path: every item twice - Vril Sigils (ExtendedCost 3902 = 25 / 3903 = 15)
-- and gold (BuyPrice 5000g; each half of a pair 2500g / 15 sigils). Skill / dual-wield filtering = conditions on 601500.
-- Glow: the on-equip hook below. Needs client b41v+ for the sigil prices. The old gossip pages stay as fallback.
local CLERK, LIST_BASE, SHOP_SECONDS = 601500, 601501, 180
-- 2026-10-28b (vrilforge-stay): the session used to end on ANY 3-yard step (and the sphere itself despawned after 60 s). With the
-- vendor window that never showed (it pins you in place), but with the FamVril panel you walk/turn while it is open, or step over to
-- the Vrilforge/clerk after closing it, and everything vanished. Now: a 25-yard leash and the sphere lives as long as the shop.
local LEASH = 25
local RN_SPHERE_Z, RN_SPHERE_SCALE, RN_FORGE_GO, RN_SIGIL_LISTS = -2, 8, 601600, 100   -- release-next (test realm); sigil-only lists = LIST_BASE + 100 + path
local SPHERE_BACK, SPHERE_UP = 9, 3   -- 2026-10-28c: sphere 9 yd out along the forge bearing (forge is at 4 yd) and 3 yd up
local BIT = bit32 or bit
local function u32(x) x = x % 4294967296; if x < 0 then x = x + 4294967296 end; return x end   -- LuaJIT bit ops are signed (fix 2026-10-13)

local NAMES = {[0]="Aetherion","Aethelmar","Val'kyrian","Seraphel","Glaciossa","Terravok","Maelthara","Zhao-Rin","Morthwyl","Xerathis","Pyralith",
 "Umbryss","Naiadia","Chronnax","Vypera","Zulmecca","Cogginz","Krathbari","Cutlassbane","Tempestyr","Whisperkin","Warbringer","Lumenor",
 "Sylvaris","Sanctoria","Gravemourn","Totemkar","Khadrix","Xarothim","Feralon","Melodyx"}
-- type index -> {skill, label}; single id = 900100 + path*15 + type
local TYPES = {[0]={44,"Axe"},[1]={172,"Two-Handed Axe"},[2]={45,"Bow"},[3]={46,"Gun"},[4]={54,"Mace"},[5]={160,"Two-Handed Mace"},
 [6]={229,"Polearm"},[7]={43,"Sword"},[8]={55,"Two-Handed Sword"},[9]={136,"Staff"},[10]={473,"Fist Weapon"},[11]={173,"Dagger"},
 [12]={176,"Thrown"},[13]={226,"Crossbow"},[14]={228,"Wand"}}
local TG = {[1]=true,[5]=true,[8]=true}    -- Titan's Grip: 2H axe/mace/sword (not staff/polearm)
local DUAL = {[0]=0,[1]=4,[2]=7,[3]=10,[4]=11}               -- dualIdx -> type; MH 911000+path*5+d, OH 912000+path*5+d
local AGI_PATHS = {[7]=true,[14]=true,[16]=true,[17]=true,[18]=true,[20]=true,[23]=true,[29]=true}   -- Swift Bulwark 913100+path

local function isArtifact(e)
  return (e >= 900100 and e <= 900564) or (e >= 911000 and e <= 911154) or (e >= 912000 and e <= 912154)
      or (e >= 913000 and e <= 913030) or (e >= 913100 and e <= 913130) or (e >= 914000 and e <= 914030)
end
local function pathOfItem(e)
  if e >= 900100 and e <= 900564 then return math.floor((e - 900100) / 15) end
  if e >= 911000 and e <= 911154 then return math.floor((e - 911000) / 5) end
  if e >= 912000 and e <= 912154 then return math.floor((e - 912000) / 5) end
  if e >= 913000 and e <= 913030 then return e - 913000 end
  if e >= 913100 and e <= 913130 then return e - 913100 end
  if e >= 914000 and e <= 914030 then return e - 914000 end
end

local function IsBot(p)
  local ok, b = pcall(function() return p:IsBot() end)
  if ok and b then return true end
  local ok2, acc = pcall(function() return p:GetAccountName() end)
  if ok2 and type(acc) == "string" then
    local u = acc:upper()
    if u:find("^RNDBOT") or u:find("PLAYERBOT") or u:find("^AHBOT") then return true end
  end
  return false
end
local function say(p, m) p:SendBroadcastMessage("|cffff8000[Vril Forge]|r " .. m) end
local gmPath = {}   -- guidLow -> path picked by a GM for this Forge session only (never saved)
local function isGM(p) local ok, r = pcall(function() return p:GetGMRank() end); return ok and (r or 0) >= 1 end
local function pathOf(p)
  local q = CharDBQuery("SELECT subclass_id FROM familylan_subclass WHERE guid=" .. p:GetGUIDLow())
  if q then return q:GetUInt32(0) end
end

-- glow ------------------------------------------------------------------
local function applyGlow(item)
  if not item then return end
  local path = pathOfItem(item:GetEntry())
  if path and (item:GetEnchantmentId(0) or 0) == 0 then item:SetEnchantment(GLOW_BASE + path, 0) end
end

-- grant (bag or mail); returns true when every copy landed somewhere --------
local function grant(p, entry, n)
  for _ = 1, n do
    local it = p:AddItem(entry, 1)
    if it then applyGlow(it)
    else
      SendMail("The Vril Forge", "Your bags were full, so the Forge sent this by mail.", p:GetGUIDLow(), 0, MAIL_STATIONERY, 0, 0, 0, entry, 1)
      say(p, "Bags full: sent by mail.")
    end
  end
  return true
end
-- release-next (2026-10-28, TEST realm only): gold is for VIPs/GMs and costs 3x; everyone else pays in Vril Sigils.
local function rnTest() return (FamRN and FamRN.test()) end
local function goldAllowed(p) return not rnTest() or FamRN.vip(p) end
local function goldPrice(p) if rnTest() then return PRICE_GOLD * 3 end return PRICE_GOLD end
local function goldText(p) return math.floor(goldPrice(p) / 10000) .. " gold" end
local function pay(p, mode, sigils)
  if mode == 1 then
    if p:GetItemCount(SIGIL) < sigils then return false, "You need " .. sigils .. " Vril Sigils." end
  else
    if not goldAllowed(p) then return false, "Paying with gold is for VIPs. Use Vril Sigils." end
    if p:GetCoinage() < goldPrice(p) then return false, "You need " .. goldText(p) .. "." end
  end
  return true
end
local function charge(p, mode, sigils)
  if mode == 1 then p:RemoveItem(SIGIL, sigils) else p:ModifyMoney(-goldPrice(p)) end
end

-- Black Sun sphere --------------------------------------------------------
local active = {}
local function cleanup(g)
  local s = active[g]; if not s then return end
  active[g] = nil
  if s.ev then RemoveEventById(s.ev) end
  local p = GetPlayerByGUID(s.pguid)
  if p then
    p:SetPhaseMask(s.oldPhase, true)
    for _, gd in ipairs({ s.cguid, s.kguid }) do
      local w = gd and p:GetMap() and p:GetMap():GetWorldObject(gd)
      local c = w and w:ToCreature()
      if c then c:DespawnOrUnsummon(0) end
    end
    if s.goguid then   -- release-next Vrilforge object
      pcall(function() local w = p:GetMap():GetWorldObject(s.goguid); local go = w and w:ToGameObject(); if go then go:Despawn(); go:RemoveFromWorld(false) end end)
    end
  end
end
local function sphere(p)
  local g = p:GetGUIDLow(); cleanup(g)
  local test = rnTest()   -- release-next: lower, smaller sphere + a Vrilforge object on the test realm (tune in game)
  -- 2026-10-28c: the sphere sat on the player, between them and the Vrilforge's skull front, so the forge only took
  -- right-clicks from behind/the side. Now it hangs BEHIND the forge (same bearing, farther out) and higher. Tune here.
  local so = p:GetO() + (test and 0.9 or 0)   -- the forge's bearing from the player (see SummonGameObject below)
  local c = p:SpawnCreature(SPHERE, p:GetX() + SPHERE_BACK * math.cos(so), p:GetY() + SPHERE_BACK * math.sin(so), p:GetZ() + (test and SPHERE_UP or 1), p:GetO(), 3, SHOP_SECONDS * 1000)   -- was at the player, Z+RN_SPHERE_Z(-2)
  p:PlayDirectSound(SOUND, p)
  if not c then return end
  c:SetDisplayId(SPHERE_DISPLAY); c:SetScale(test and RN_SPHERE_SCALE or SPHERE_SCALE); c:SetUnitFlags(0x02000302); c:SetReactState(0); c:SetDisableGravity(true)
  local s = { pguid = p:GetGUID(), cguid = c:GetGUID(), x = p:GetX(), y = p:GetY(), map = p:GetMapId(), t0 = os.time(), oldPhase = p:GetPhaseMask() }
  c:SetPhaseMask(PHASE_BIT, true); p:SetPhaseMask(u32(BIT.bor(s.oldPhase, PHASE_BIT)), true)
  active[g] = s
  if test then
    pcall(function()
      local o = p:GetO() + 0.9
      local go = p:SummonGameObject(RN_FORGE_GO, p:GetX() + 4 * math.cos(o), p:GetY() + 4 * math.sin(o), p:GetZ(), (p:GetO() + math.pi) % (2 * math.pi), SHOP_SECONDS)
      if go then go:SetPhaseMask(PHASE_BIT, true); s.goguid = go:GetGUID() end
    end)
  end
  s.ev = CreateLuaEvent(function()
    local pl = GetPlayerByGUID(s.pguid)
    if not pl or not pl:IsInWorld() or pl:GetMapId() ~= s.map or pl:IsInCombat()
       or pl:GetDistance(s.x, s.y, pl:GetZ()) > LEASH or os.time() - s.t0 >= (s.ttl or 60) then cleanup(g) end
  end, 1000, 0)
end

local function effPath(p) return pathOf(p) or gmPath[p:GetGUIDLow()] end
-- vendor window (2026-10-24) -----------------------------------------------
local function clerkFor(p)
  local s = active[p:GetGUIDLow()]; if not s or not s.kguid then return nil end
  local m = p:GetMap(); local w = m and m:GetWorldObject(s.kguid); local c = w and w:ToCreature()
  if c and c:IsInWorld() then return c end
end
local function spawnClerk(p)   -- needs the Black Sun session (sphere) so the clerk shares its phase
  local s = active[p:GetGUIDLow()]; if not s then return nil end
  local c = clerkFor(p); if c then return c end
  local o = p:GetO()
  c = p:SpawnCreature(CLERK, p:GetX() + 2 * math.cos(o), p:GetY() + 2 * math.sin(o), p:GetZ(), (o + math.pi) % (2 * math.pi), 3, SHOP_SECONDS * 1000)
  if not c then return nil end
  c:SetPhaseMask(PHASE_BIT, true)
  s.kguid = c:GetGUID(); s.klow = c:GetGUIDLow(); s.ttl = SHOP_SECONDS
  return c
end
local function openWares(p, path, delay)
  local c = spawnClerk(p); if not c then return false end
  local pg, cg, list = p:GetGUID(), c:GetGUID(), LIST_BASE + path
  if not goldAllowed(p) then list = list + RN_SIGIL_LISTS end   -- release-next: sigil-only list
  CreateLuaEvent(function()   -- give the client a moment to see the clerk first
    local pl = GetPlayerByGUID(pg); if not pl then return end
    local m = pl:GetMap(); local w = m and m:GetWorldObject(cg); local cr = w and w:ToCreature()
    if cr then pl:SendListInventory(cr, list) end
  end, delay or 700, 1)
  return true
end
-- legendary-lk10 "The Thaw": forging step (staged 2026-10-13) ------------------------
local LEG = { [1]={{915100,1},{915101,1},{915105,1}}, [2]={{915102,1},{915103,1},{915104,1},{915105,1}}, [3]={{915106,1}},
  [4]={{915107,1},{915108,1}}, [5]={{915109,1}}, [6]={{915110,1},{915111,1}}, [7]={{915112,2},{915113,1},{915114,1}},
  [8]={{915115,1}}, [9]={{915116,1}}, [11]={{915117,1},{915118,1}} }
local LEG_IDX = {[1]=0,[2]=1,[3]=2,[4]=3,[5]=4,[6]=5,[7]=6,[8]=7,[9]=8,[11]=9}
local LEG_TOKEN = 915121
local function legQuest(p) local i = LEG_IDX[p:GetClass()]; return i and (915212 + i) end
local function legMissing(p)
  local m = {}
  for _, e in ipairs(LEG[p:GetClass()] or {}) do local have = p:GetItemCount(e[1], true); if have < e[2] then m[#m+1] = {e[1], e[2] - have} end end
  return m
end
local function legState(p)   -- 1 = ready to forge, 2 = re-grant lost pieces, nil = nothing
  if IsBot(p) then return end
  local q = legQuest(p); if not q then return end
  local st = p:GetQuestStatus(q)
  if st == 3 and p:GetItemCount(LEG_TOKEN) >= 1 then return 1 end
  if (st == 1 or p:GetQuestRewardStatus(q)) and #legMissing(p) > 0 then return 2 end
end
local function legAddOption(p)
  local ls = legState(p)
  if ls == 1 then p:GossipMenuAddItem(3, "Forge my legendary (uses the Token of the Thaw Trial)", 0, 7)
  elseif ls == 2 then p:GossipMenuAddItem(3, "Re-forge my lost legendary pieces", 0, 6) end
  return ls
end
local function legForge(p, intid)
  local ls = legState(p)
  if intid == 7 and ls == 1 then
    p:RemoveItem(LEG_TOKEN, 1)
    for _, e in ipairs(LEG[p:GetClass()]) do grant(p, e[1], math.max(0, e[2] - p:GetItemCount(e[1], true))) end
    pcall(function() p:CompleteQuest(legQuest(p)) end)
    pcall(function() p:CastSpell(p, 11540, true) end); pcall(function() p:CastSpell(p, 11542, true) end)
    p:PlayDirectSound(SOUND, p)
    say(p, "The frozen crown melts into light... your legendary is born! Return to Tirion's Echo.")
    pcall(SendWorldMessage, "|cffff8000[Legendary]|r " .. p:GetName() .. " has forged a legendary weapon at the Vril Forge!")
  elseif intid == 6 and ls == 2 then
    for _, e in ipairs(legMissing(p)) do grant(p, e[1], e[2]) end
    say(p, "The Forge remembers your legendary and makes it again.")
  end
  cleanup(p:GetGUIDLow()); p:GossipComplete()
end
-- menu ------------------------------------------------------------------
-- intid: 1 weapons page, 2 pairs page, 3 off-hand page, 9 close; items: (kind*100 + idx)*10 + mode  (mode 1 sigils, 2 gold)
local function title(path) return NAMES[path] end
local function sendMenu(p, txt, obj)   -- obj = token item (right-click) or the player (.blacksun)
  if obj and obj:GetTypeId() == 4 then p:GossipSendMenu(txt, p, FORGE_MENU) else p:GossipSendMenu(txt, obj) end
end
local function addBuy(p, label, kind, idx, sig)
  p:GossipMenuAddItem(1, label .. " - " .. sig .. " Vril Sigils", 0, (kind * 100 + idx) * 10 + 1, false, "Spend " .. sig .. " Vril Sigils on " .. label .. "?")
  if goldAllowed(p) then p:GossipMenuAddItem(1, label .. " - " .. goldText(p), 0, (kind * 100 + idx) * 10 + 2, false, "Spend " .. goldText(p) .. " on " .. label .. "?") end
end
local function showMain(p, item)
  p:GossipClearMenu()
  if clerkFor(p) then
    p:GossipMenuAddItem(1, "Browse the Forge's wares", 0, 4)
  else   -- fallback: the clerk could not appear
    p:GossipMenuAddItem(9, "Weapons of my path", 0, 1)
    if p:HasSpell(674) then p:GossipMenuAddItem(9, "Paired weapons (main hand + off hand)", 0, 2) end
    p:GossipMenuAddItem(9, "Shield or held focus", 0, 3)
  end
  legAddOption(p)
  p:GossipMenuAddItem(0, "Close", 0, 9)
  sendMenu(p, TXT_MAIN, item)
end
local function showPage(p, item, page, path)
  p:GossipClearMenu()
  local nm = title(path)
  if page == 1 then
    for t = 0, 14 do
      if p:HasSkill(TYPES[t][1]) then
        local extra = (TG[t] and p:CanTitanGrip()) and " (x2, Titan's Grip)" or ""
        p:GossipMenuAddItem(1, nm .. " - " .. TYPES[t][2] .. extra .. ": " .. PRICE_SINGLE .. " sigils", 0, (100 + t) * 10 + 1, false, "Spend " .. PRICE_SINGLE .. " Vril Sigils on " .. nm .. " (" .. TYPES[t][2] .. ")?")
        if goldAllowed(p) then p:GossipMenuAddItem(1, nm .. " - " .. TYPES[t][2] .. extra .. ": " .. goldText(p), 0, (100 + t) * 10 + 2, false, "Spend " .. goldText(p) .. " on " .. nm .. " (" .. TYPES[t][2] .. ")?") end
      end
    end
    sendMenu(p, TXT_WEAP, item)
  elseif page == 2 then
    for d = 0, 4 do
      local t = DUAL[d]
      if p:HasSkill(TYPES[t][1]) then addBuy(p, nm .. " pair (" .. TYPES[t][2] .. ")", 2, d, PRICE_PAIR) end
    end
    sendMenu(p, TXT_PAIR, item)
  else
    if p:HasSkill(433) then
      if AGI_PATHS[path] then
        addBuy(p, nm .. "'s Bulwark (Strength shield)", 3, 0, PRICE_OFF)
        addBuy(p, nm .. "'s Swift Bulwark (Agility shield)", 5, 0, PRICE_OFF)
      else
        addBuy(p, nm .. "'s Bulwark (shield)", 3, 0, PRICE_OFF)
      end
    end
    addBuy(p, nm .. "'s Focus (held)", 4, 0, PRICE_OFF)
    sendMenu(p, TXT_OFF, item)
  end
end

local function onHello(event, p, item)
  print(string.format('[Vril Forge] hello guid=%d combat=%s fly=%s path=%s', p:GetGUIDLow(), tostring(p:IsInCombat()), tostring(p:IsFlying()), tostring(effPath(p))))
  pcall(function() p:GossipComplete() end)
  -- 2026-10-28b: keep a live Forge (sphere + clerk + Vrilforge) instead of despawning and respawning it on every use; stale ones still reset.
  local live = active[p:GetGUIDLow()] and clerkFor(p)
  if not live then pcall(cleanup, p:GetGUIDLow()) end   -- reset any stale menu/sphere so every right-click reopens (fix 2026-10-13b)
  if p:IsInCombat() or p:InBattleground() or p:InArena() or p:IsFlying() or p:GetTransport() then
    say(p, "The Black Sun will not rise here. Try again on solid ground, out of combat.")
    return false
  end
  local path = effPath(p)
  if not path and isGM(p) then
    say(p, "GM: you have no Vril Path - pick one to browse the Forge with (this session only, nothing is saved).")
    p:GossipClearMenu()
    for i = 0, 30 do p:GossipMenuAddItem(3, NAMES[i], 0, 8000 + i) end
    sendMenu(p, TXT_MAIN, item)
    return false
  end
  if not path and not isGM(p) and legState(p) then   -- legendary forging works without a Vril Path (legendary-lk10)
    p:GossipClearMenu(); legAddOption(p); p:GossipMenuAddItem(0, "Close", 0, 9); sendMenu(p, TXT_MAIN, item); return false
  end
  if not path then say(p, "Choose a Vril Path with Whiz first (Whiz picks your path; then the Black Sun can forge for it)."); return false end
  if not (active[p:GetGUIDLow()] and clerkFor(p)) then
    local ok, err = pcall(sphere, p); if not ok then print('[Vril Forge] sphere: ' .. tostring(err)) end
  end
  local okc, c = pcall(spawnClerk, p); if not okc then print('[Vril Forge] clerk: ' .. tostring(c)) end
  if okc and c and not legState(p) then   -- straight to the vendor window
    -- 2026-10-28 (vrilforge-panel): clients with the FamVril panel (FamUI 'Vril' module) get the Vrilforging panel (Armory tab)
    -- instead; the vendor window stays the fallback for clients without it (and via the clerk / the Vrilforge's 'wares' option).
    if FamVrilUI and FamVrilUI.HasAddon and FamVrilUI.HasAddon(p) and FamVrilUI.Open then
      local okp = pcall(FamVrilUI.Open, p, "armory")
      if okp then return false end
    end
    local okw, opened = pcall(openWares, p, path, 900)
    if okw and opened then return false end
  end
  showMain(p, item)
  return false   -- never cast the use spell, never consume
end
local function onSelect(event, p, item, sender, intid)
  if intid >= 8000 and intid <= 8030 and isGM(p) then
    gmPath[p:GetGUIDLow()] = intid - 8000
    say(p, "GM browse path: " .. NAMES[intid - 8000] .. ".")
    pcall(sphere, p); pcall(spawnClerk, p); showMain(p, item); return
  end
  if intid == 6 or intid == 7 then legForge(p, intid); return end   -- legendary-lk10
  local path = effPath(p)
  if not path then cleanup(p:GetGUIDLow()); p:GossipComplete(); return end
  if intid == 9 then cleanup(p:GetGUIDLow()); p:GossipComplete(); return end
  if intid == 4 then
    local okw, opened = pcall(openWares, p, path, 100)
    if okw and opened then p:GossipComplete(); return end
    showPage(p, item, 1, path); return   -- clerk gone: old pages
  end
  if intid >= 1 and intid <= 3 then showPage(p, item, intid, path); return end
  local mode = intid % 10; local kind = math.floor(intid / 1000); local idx = math.floor(intid / 10) % 100
  local entries, price = {}, PRICE_SINGLE
  if kind == 1 then
    if not TYPES[idx] or not p:HasSkill(TYPES[idx][1]) then p:GossipComplete(); return end
    local e = 900100 + path * 15 + idx
    entries = { e }; if TG[idx] and p:CanTitanGrip() then entries[2] = e end
  elseif kind == 2 then
    if not DUAL[idx] or not p:HasSpell(674) then p:GossipComplete(); return end
    entries = { 911000 + path * 5 + idx, 912000 + path * 5 + idx }; price = PRICE_PAIR
  elseif kind == 3 then entries = { 913000 + path }; price = PRICE_OFF
  elseif kind == 4 then entries = { 914000 + path }; price = PRICE_OFF
  elseif kind == 5 then
    if not AGI_PATHS[path] or not p:HasSkill(433) then p:GossipComplete(); return end
    entries = { 913100 + path }; price = PRICE_OFF
  else p:GossipComplete(); return end
  local ok, why = pay(p, mode, price)
  if not ok then say(p, why .. " Nothing was charged."); showMain(p, item); return end
  for _, e in ipairs(entries) do grant(p, e, 1) end     -- bag or mail, never lost
  charge(p, mode, price)                                -- charge only after the grant
  say(p, "The Forge answers. " .. (#entries > 1 and (#entries .. " items granted.") or "Item granted."))
  cleanup(p:GetGUIDLow()); p:GossipComplete()
end
RegisterItemGossipEvent(TOKEN, 1, onHello)
RegisterItemGossipEvent(TOKEN, 2, onSelect)
RegisterPlayerGossipEvent(FORGE_MENU, 2, onSelect)
-- right-clicking your own clerk reopens your path's window
RegisterCreatureGossipEvent(CLERK, 1, function(event, p, c)
  local s = active[p:GetGUIDLow()]; local path = effPath(p)
  if s and s.klow == c:GetGUIDLow() and path then p:SendListInventory(c, LIST_BASE + path + (goldAllowed(p) and 0 or RN_SIGIL_LISTS))
  else say(p, "This Forge answers someone else.") end
  return true
end)
-- '.blacksun' (or '.forge') opens the Forge while carrying the token - works without a restart.
-- Right-click needs item 900090 to carry a valid on-use spell (36177 'Dummy'): spell 483 'Learning' is reserved for the
-- recipe 'special learning format', so the core zeroed it at load and the client never sent the use (fix 2026-10-11).
RegisterPlayerEvent(42, function(event, p, command)
  local cmd = ((command or ""):lower():match("^%s*%.?(%S+)")) or ""
  if cmd ~= "blacksun" and cmd ~= "forge" then return end
  print("[VrilForge] ." .. cmd .. " from " .. p:GetName() .. " path=" .. tostring(pathOf(p)) .. " gm=" .. tostring(isGM(p)) .. " token=" .. p:GetItemCount(TOKEN))
  if IsBot(p) then return false end
  if p:GetItemCount(TOKEN) < 1 then say(p, "You need the Supreme Timelord's Black Sun in your bags."); return false end
  onHello(1, p, p)
  return false
end)

-- FamVril panel API (2026-10-27, additive): 32_vril_ui.lua reuses this file's rules and prices; nothing above changed.
FamVrilForge = {
  TOKEN = TOKEN, SIGIL = SIGIL, PRICE_SINGLE = PRICE_SINGLE, PRICE_PAIR = PRICE_PAIR, PRICE_OFF = PRICE_OFF, PRICE_GOLD = PRICE_GOLD,
  NAMES = NAMES, TYPES = TYPES, TG = TG, DUAL = DUAL, AGI_PATHS = AGI_PATHS, gmPath = gmPath,
  pathOf = pathOf, effPath = effPath, isGM = isGM, IsBot = IsBot,
  pay = pay, charge = charge, grant = grant, goldAllowed = goldAllowed, goldPrice = goldPrice, onHello = onHello, legState = legState, legMissing = legMissing, legForge = legForge,
}
-- 2026-10-28b: the Vrilforge object's "Browse the Forge's wares" opens the clerk's vendor list on the LIVE session (no reset).
function FamVrilForge.openWares(p)
  local path = effPath(p); if not path or not active[p:GetGUIDLow()] then return false end
  local ok, opened = pcall(openWares, p, path, 150)
  return ok and opened
end
function FamVrilForge.live(p) return active[p:GetGUIDLow()] ~= nil end

-- token grant / re-grant -------------------------------------------------
local function tokenInMail(p)
  local q = CharDBQuery("SELECT 1 FROM mail_items mi JOIN item_instance ii ON ii.guid=mi.item_guid WHERE mi.receiver=" .. p:GetGUIDLow() .. " AND ii.itemEntry=" .. TOKEN .. " LIMIT 1")
  return q ~= nil
end
local function ensureToken(p)
  if IsBot(p) or p:GetLevel() < 80 then return end
  if p:GetItemCount(TOKEN, true) > 0 or tokenInMail(p) then return end
  if not p:AddItem(TOKEN, 1) then SendMail("The Black Sun", "It found you anyway.", p:GetGUIDLow(), 0, MAIL_STATIONERY, 0, 0, 0, TOKEN, 1) end
  say(p, "The Supreme Timelord's Black Sun answers your call.")
end
RegisterPlayerEvent(13, function(e, p) if p:GetLevel() >= 80 then ensureToken(p) end end)
RegisterPlayerEvent(3, function(e, p)
  local m = p:GetPhaseMask(); if BIT.band(m, PHASE_BIT) ~= 0 then p:SetPhaseMask(u32(BIT.band(m, BIT.bnot(PHASE_BIT))), true) end
  ensureToken(p)
end)
RegisterPlayerEvent(4, function(e, p) cleanup(p:GetGUIDLow()); gmPath[p:GetGUIDLow()] = nil end)
RegisterPlayerEvent(29, function(e, p, item) if item and isArtifact(item:GetEntry()) then applyGlow(item) end end)

-- sigils: bots MAY keep Vril Sigils (rule lifted 2026-10-22). The old PLAYER_EVENT_ON_LOOT_ITEM strip
-- (RemoveItem inside the loot hook) destroyed the item mid hook-chain and crashed the worldserver on Ruby Sanctum kills.

-- Mythic+ boss sigils (bigupd 2026-10-28: MythicPlus-extended Lua exports FAMWOW_MYTHIC_TIER[instanceId] and
-- FAMWOW_MYTHIC_LAST_BOSSES; was mod-mythic-plus mythic_plus_dungeon.mythiclevel) -----
local paid = {}   -- [instanceId .. ":" .. bossEntry] = true
RegisterPlayerEvent(7, function(e, killer, killed)
  local map = killer:GetMap()
  if not map or not map:IsDungeon() or map:IsRaid() or not killed:IsDungeonBoss() then return end
  local inst = map:GetInstanceId(); local key = inst .. ":" .. killed:GetEntry()
  if paid[key] then return end
  local lvl = (FAMWOW_MYTHIC_TIER and FAMWOW_MYTHIC_TIER[inst]) or 0
  if lvl <= 0 then return end
  paid[key] = true
  local n = 1 + lvl
  if FAMWOW_MYTHIC_LAST_BOSSES and FAMWOW_MYTHIC_LAST_BOSSES[killed:GetEntry()] then n = n * 2 end
  local members = {}
  local grp = killer:GetGroup()
  if grp then members = grp:GetMembers() else members = { killer } end
  for _, m in ipairs(members) do
    if m:IsInWorld() and m:GetMapId() == map:GetMapId() and m:GetInstanceId() == inst and not IsBot(m) then
      if not m:AddItem(SIGIL, n) then SendMail("Vril Sigils", "Mythic+ reward.", m:GetGUIDLow(), 0, MAIL_STATIONERY, 0, 0, 0, SIGIL, n) end
      say(m, "+" .. n .. " Vril Sigils (Mythic+ " .. lvl .. ").")
    end
  end
end)