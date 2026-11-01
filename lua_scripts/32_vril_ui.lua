-- 32_vril_ui.lua : FamVril panel, SERVER half (2026-10-27, WoWbot). The client half is the FamVril addon.
-- The panel only DISPLAYS and REQUESTS. Every rule (class, quest, combat, cooldown, Black Sun token, skills, price,
-- GM gating) is checked here, by the same helpers the Whiz gossip menu (12_subclass_system.lua) and the Vril Forge
-- (16_vril_forge.lua) use: FamVrilPaths / FamVrilForge are exported at the bottom of those two files.
-- Comms: AIO (Rochet2, already live for FamVoice). Client -> server handler "FamVrilServer"; server -> client "FamVril".
-- Protocol v2:  Hello(ver) | State() | Detail(id) | Choose(id) | Remove() | Armory() | BrowsePath(id)[GM] | Buy(kind,idx,mode)
--               | OpenForge() | OpenLegendary() | LegForge(which) | Forge() | ForgeBuy(slot) | ForgeSwap()
--               answers: Init(catalog) State(t) Detail(t) Armory(t) Forge(t) Result(ok,msg) Open(tab)
-- Fallback: players whose client has no FamVril never say Hello, so they only ever see the old gossip menus.
-- UNDO: rename this file and 32_vril_ui_data.lua to .off and ".reload ale" (the two small hooks in 12_ / 16_ stay harmless).
local AIO = AIO or require("AIO")
local VER = 2
local FORGE_SPELL = 706500
local pendingForge = {}
FamVrilUI = FamVrilUI or {}
local UI = FamVrilUI
local helloed, lastReq, blurbs = {}, {}, nil

local function gl(p) return p:GetGUIDLow() end
local function send(p, fn, ...) AIO.Handle(p, "FamVril", fn, ...) end
local function P() return FamVrilPaths end
local function F() return FamVrilForge end
local function isBot(p) local pp = P(); if pp and pp.IsBot then return pp.IsBot(p) end; return false end

function UI.HasAddon(p) return helloed[gl(p)] == true end
function UI.Open(p, tab) if helloed[gl(p)] then send(p, "Open", tab or "paths") end end

-- one-line "what is this path" text: the first paragraph of the Whiz preview text (npc_text 6010301 + path id)
local function loadBlurbs()
  if blurbs then return blurbs end
  blurbs = {}
  local q = WorldDBQuery("SELECT ID, text0_0 FROM npc_text WHERE ID BETWEEN 6010301 AND 6010331")
  if q then
    repeat
      local id, t = q:GetUInt32(0) - 6010301, q:GetString(1) or ""
      t = t:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      local b = t:match("%$B%$B(.-)%$B%$B") or t:match("%$B%$B(.-)$")
      if b then b = b:gsub("^%s+", ""):gsub("%s+$", ""); blurbs[id] = b end
    until not q:NextRow()
  end
  return blurbs
end

------------------------------------------------------------------ data builders
local function catalog(p)
  local pp = P()
  local cls = p:GetClass()
  local rec = {}
  for i, id in ipairs(pp.RECOMMENDED[cls] or {}) do rec[id] = i end
  local bl, list = loadBlurbs(), {}
  for id = 0, 30 do
    local d = pp.PATHS[id]
    if d and d.enabled then
      list[#list + 1] = { id = id, n = d.name, c = d.color, ic = d.icon, rec = rec[id], blk = (pp.BLOCKED[cls] == id) and 1 or nil, b = bl[id] or "" }
    end
  end
  local recAll = {}
  for c, l in pairs(pp.RECOMMENDED) do recAll[c] = l end
  return { v = VER, cls = cls, cn = pp.CLASS_NAME[cls], gm = pp.isGM(p) and 1 or 0, paths = list, recAll = recAll,
           echo = pp.BLOCKED, clsNames = pp.CLASS_NAME, power = pp.powerOf(p), forms = pp.ENABLED_FORMS and 1 or 0,
           cd = pp.COOLDOWN, sigilItem = F() and F().SIGIL or 900091, tokenItem = F() and F().TOKEN or 900090 }
end

local function legState(p)
  local f = F(); if not (f and f.legState) then return 0 end
  local ok, s = pcall(f.legState, p)
  return (ok and s) or 0
end

local function state(p)
  local pp, f = P(), F()
  local row = pp.getRow(gl(p))
  return { path = row and row.id or nil, left = pp.cooldownLeft(p), lvl = p:GetLevel(), qd = pp.questDone(p) and 1 or 0,
           combat = p:IsInCombat() and 1 or 0, tok = f and p:GetItemCount(f.TOKEN) or 0, sig = f and p:GetItemCount(f.SIGIL) or 0,
           gm = pp.isGM(p) and 1 or 0, leg = legState(p), cls = p:GetClass() }
end

local function detail(p, id)
  local pp = P()
  id = tonumber(id)
  local d = id and pp.PATHS[id]
  if not d or not d.enabled then return nil end
  local lvl, slots, av = p:GetLevel(), {}, {}
  for _, s in ipairs(d.slots) do
    if not (s.form30 or s.form50 or s.ult) then
      local sid = pp.spellFor(s, p)
      slots[#slots + 1] = { s = s.slot, n = s.name, u = s.unlock, sp = sid, ic = s.icon, w = s.what,
        k = s.capstone and "cap" or (s.bonus and "bonus" or "kit"),
        dm = s.bp and pp.scaled(s, math.max(lvl, s.unlock)) or nil, kn = p:HasSpell(sid) and 1 or 0 }
    end
  end
  local a = d.avatar or pp.AVATAR[id]
  if pp.ENABLED_FORMS and a then
    local function k(sid) return p:HasSpell(sid) and 1 or 0 end
    av = {
      { k = "form30", n = a.f30, u = 30, sp = pp.FORM30_BASE + id, ic = a.ic30, e = "Vril Avatar (1 minute)", kn = k(pp.FORM30_BASE + id) },
      { k = "form50", n = a.f50, u = 50, sp = pp.FORM50_BASE + id, ic = a.ic50, e = "Vril Avatar, the Boss form (2 minutes)", kn = k(pp.FORM50_BASE + id) },
      { k = "ult1", n = a.u30, u = 60, sp = pp.ULT1_BASE + id, ic = a.ic30, e = "Ultimate I: " .. a.e30, kn = k(pp.ULT1_BASE + id) },
      { k = "ult2", n = a.u50, u = 80, sp = pp.ULT2_BASE + id, ic = a.ic50, e = "Ultimate II: " .. a.e50, kn = k(pp.ULT2_BASE + id) },
    }
  end
  local B = d.bundle
  local bundle = B and { set = B.set, tab = B.tabardName, pet = B.petName, title = "the " .. d.name, got = pp.hasReward(gl(p), id) and 1 or 0 } or nil
  local cls = p:GetClass()
  return { id = id, n = d.name, c = d.color, ic = d.icon, b = loadBlurbs()[id] or "", slots = slots, av = av, bundle = bundle,
           blk = (pp.BLOCKED[cls] == id) and 1 or nil, lvl = lvl }
end

local function armory(p)
  local pp, f = P(), F()
  local data = FamVrilUIData and FamVrilUIData.eff or {}
  local path = f.effPath(p)
  local isgm = pp.isGM(p)
  local out = { gm = isgm and 1 or 0, tok = p:GetItemCount(f.TOKEN), sig = p:GetItemCount(f.SIGIL), price = { f.PRICE_SINGLE, f.PRICE_PAIR, f.PRICE_OFF },
                gold = f.goldPrice and f.goldPrice(p) or f.PRICE_GOLD, nogold = (f.goldAllowed and not f.goldAllowed(p)) and 1 or nil }   -- release-next: gold VIP-only on the test realm
  if not path then out.nopath = 1; return out end
  local D = data[path] or {}
  local pd = pp.PATHS[path]
  out.path, out.pn, out.pc, out.pic, out.set = path, pd.name, pd.color, pd.icon, f.NAMES[path]
  out.temp = (f.gmPath[gl(p)] == path and not f.pathOf(p)) and 1 or nil   -- a GM browsing only (never saved)
  local items = {}
  local function add(kind, idx, lab, ids, sig, e, x2)
    items[#items + 1] = { kind = kind, idx = idx, lab = lab, ids = ids, sig = sig, x2 = x2 and 1 or nil, eff = e and D[e] or nil }
  end
  for t = 0, 14 do
    if p:HasSkill(f.TYPES[t][1]) then
      local e = 900100 + path * 15 + t
      local x2 = f.TG[t] and p:CanTitanGrip()
      add(1, t, f.TYPES[t][2], x2 and { e, e } or { e }, f.PRICE_SINGLE, "weapon", x2)
    end
  end
  if p:HasSpell(674) then
    for d = 0, 4 do
      local t = f.DUAL[d]
      if p:HasSkill(f.TYPES[t][1]) then
        add(2, d, f.TYPES[t][2] .. " pair", { 911000 + path * 5 + d, 912000 + path * 5 + d }, f.PRICE_PAIR, "weapon")
      end
    end
  end
  if p:HasSkill(433) then
    add(3, 0, f.AGI_PATHS[path] and "Bulwark (Strength shield)" or "Bulwark (shield)", { 913000 + path }, f.PRICE_OFF, "shield")
    if f.AGI_PATHS[path] then add(5, 0, "Swift Bulwark (Agility shield)", { 913100 + path }, f.PRICE_OFF, "swift") end
  end
  add(4, 0, "Focus (held)", { 914000 + path }, f.PRICE_OFF, "focus")
  out.items = items
  return out
end

local SLOT_NAME = { [0] = "Helm", [1] = "Shoulders", [2] = "Chest", [3] = "Gloves", [4] = "Legs" }
local function armorType(p)
  if p:HasSkill(293) then return 3 end
  if p:HasSkill(413) then return 2 end
  if p:HasSkill(414) then return 1 end
  return 0
end
local function teachForge(p)
  if not p:HasSpell(FORGE_SPELL) then pcall(function() p:LearnSpell(FORGE_SPELL) end) end
end
local function unteachForge(p)
  if p:HasSpell(FORGE_SPELL) then pcall(function() p:RemoveSpell(FORGE_SPELL, false, false) end) end
end
local function forge(p)
  local pp, f = P(), F()
  local path = f.effPath(p)
  local out = { gm = pp.isGM(p) and 1 or 0, tok = p:GetItemCount(f.TOKEN), sig = p:GetItemCount(f.SIGIL), price = 15 }
  if not path then out.nopath = 1; return out end
  local pd = pp.PATHS[path]
  local typ = armorType(p)
  out.path, out.pn, out.pc, out.pic, out.set, out.typ = path, pd.name, pd.color, pd.icon, f.NAMES[path], typ
  local pieces = {}
  for slot = 0, 4 do
    local e = 916000 + path * 20 + typ * 5 + slot
    if p:GetItemCount(e) == 0 then
      local name = SLOT_NAME[slot]
      pcall(function()
        local t = GetItemTemplate(e)
        if t then
          if t.GetName then name = t:GetName()
          elseif type(t) == "table" and t.name then name = t.name end
        end
      end)
      pieces[#pieces + 1] = { slot = slot, e = e, n = name }
    end
  end
  out.pieces = pieces
  if FamRN and FamRN.vrilSwap then
    local ok, cost = FamRN.vrilSwap(p, true)
    if ok then out.swap = cost end
  end
  return out
end
local function doForgeBuy(p, slot)
  local pp, f = P(), F()
  slot = tonumber(slot)
  if slot == nil or slot < 0 or slot > 4 then return false, "That didn't make sense. Try again!" end
  if p:GetItemCount(f.TOKEN) < 1 and not pp.isGM(p) then return false, "You need the Supreme Timelord's Black Sun in your bags." end
  if p:IsInCombat() or p:InBattleground() or p:InArena() or p:IsFlying() or p:GetTransport() then
    return false, "The Forge only answers on solid ground, out of combat."
  end
  local path = f.effPath(p)
  if not path then return false, "Choose a Vril Path first." end
  local e = 916000 + path * 20 + armorType(p) * 5 + slot
  if p:GetItemCount(e) > 0 then return false, "You already have that piece." end
  if not GetItemTemplate(e) then return false, "That armor isn't ready yet." end
  local ok, why = f.pay(p, 1, 15)
  if not ok then return false, why end
  teachForge(p)
  pendingForge[gl(p)] = e
  local castOk = pcall(function() p:CastSpell(p, FORGE_SPELL, false) end)
  if not castOk then pendingForge[gl(p)] = nil; return false, "The Forge could not start. Try again." end
  return true, "The Forge begins (8 seconds). Stay still!"
end

------------------------------------------------------------------ actions
local function throttled(p, name, gap)
  local g, t = gl(p), os.clock()
  local r = lastReq[g]; if not r then r = {}; lastReq[g] = r end
  if r[name] and t - r[name] < (gap or 0.25) then return true end
  r[name] = t
  return false
end

local function doBuy(p, kind, idx, mode)
  local pp, f = P(), F()
  kind, idx, mode = tonumber(kind), tonumber(idx), tonumber(mode)
  if not kind or not idx or (mode ~= 1 and mode ~= 2) then return false, "That didn't make sense. Try again!" end
  local isgm = pp.isGM(p)
  if p:GetItemCount(f.TOKEN) < 1 and not isgm then return false, "You need the Supreme Timelord's Black Sun in your bags." end
  if p:IsInCombat() or p:InBattleground() or p:InArena() or p:IsFlying() or p:GetTransport() then
    return false, "The Forge only answers on solid ground, out of combat."
  end
  local path = f.effPath(p)
  if not path then return false, "Choose a Vril Path first." end
  local entries, price = {}, f.PRICE_SINGLE
  if kind == 1 then
    if not f.TYPES[idx] or not p:HasSkill(f.TYPES[idx][1]) then return false, "Your class can't use that weapon." end
    local e = 900100 + path * 15 + idx
    entries = { e }; if f.TG[idx] and p:CanTitanGrip() then entries[2] = e end
  elseif kind == 2 then
    if not f.DUAL[idx] or not p:HasSpell(674) then return false, "You need dual wield for a pair." end
    if not p:HasSkill(f.TYPES[f.DUAL[idx]][1]) then return false, "Your class can't use that weapon." end
    entries = { 911000 + path * 5 + idx, 912000 + path * 5 + idx }; price = f.PRICE_PAIR
  elseif kind == 3 then
    if not p:HasSkill(433) then return false, "Your class can't use a shield." end
    entries = { 913000 + path }; price = f.PRICE_OFF
  elseif kind == 4 then entries = { 914000 + path }; price = f.PRICE_OFF
  elseif kind == 5 then
    if not f.AGI_PATHS[path] or not p:HasSkill(433) then return false, "That shield isn't for you." end
    entries = { 913100 + path }; price = f.PRICE_OFF
  else return false, "That didn't make sense. Try again!" end
  local ok, why = f.pay(p, mode, price)
  if not ok then return false, why .. " Nothing was charged." end
  for _, e in ipairs(entries) do f.grant(p, e, 1) end     -- bag or mail, never lost
  f.charge(p, mode, price)                                -- charge only after the grant
  print(string.format("[FamVrilUI] %s bought kind=%d idx=%d path=%d with %s", p:GetName(), kind, idx, path, mode == 1 and "sigils" or "gold"))
  return true, "The Forge answers. " .. (#entries > 1 and (#entries .. " items granted.") or "Item granted.")
end

------------------------------------------------------------------ AIO handlers (from the FamVril addon)
local H = {}
local function guard(name, fn, gap)
  H[name] = function(p, ...)
    if not p or isBot(p) then return end
    if throttled(p, name, gap) then return end
    local pp = P()
    if not pp or not F() then send(p, "Result", false, "The Vril panel isn't ready yet. Use Whiz's menu for now."); return end
    local ok, err = pcall(fn, p, ...)
    if not ok then
      print("[FamVrilUI] " .. name .. ": " .. tostring(err))
      send(p, "Result", false, "Something went wrong. Try again, or use Whiz's menu.")
    end
  end
end

guard("Hello", function(p, ver)
  helloed[gl(p)] = true
  send(p, "Init", catalog(p))
  send(p, "State", state(p))
end, 0)
guard("State", function(p) send(p, "State", state(p)) end)
guard("Detail", function(p, id)
  local d = detail(p, id)
  if d then send(p, "Detail", d) end
end, 0)
guard("Choose", function(p, id)
  local ok, msg = P().choose(p, id)
  if ok then teachForge(p) end
  send(p, "Result", ok, msg)
  send(p, "State", state(p))
end, 0.5)
guard("Remove", function(p)
  local ok, msg = P().remove(p)
  if ok then unteachForge(p); pendingForge[gl(p)] = nil end
  send(p, "Result", ok, msg)
  send(p, "State", state(p))
end, 0.5)
guard("Armory", function(p) send(p, "Armory", armory(p)); send(p, "State", state(p)) end)
guard("BrowsePath", function(p, id)       -- GM only: browse another path's armory (this session only, nothing saved)
  id = tonumber(id)
  if not P().isGM(p) or not id or not P().PATHS[id] then return end
  F().gmPath[gl(p)] = id
  send(p, "Armory", armory(p))
end)
guard("Buy", function(p, kind, idx, mode)
  local ok, msg = doBuy(p, kind, idx, mode)
  send(p, "Result", ok, msg)
  send(p, "Armory", armory(p)); send(p, "State", state(p))
end, 0.75)
guard("OpenForge", function(p)           -- same as ".blacksun": needs the token, solid ground, out of combat
  local f = F()
  if p:GetItemCount(f.TOKEN) < 1 then send(p, "Result", false, "You need the Supreme Timelord's Black Sun in your bags."); return end
  f.onHello(1, p, p)
end, 1)
guard("OpenLegendary", function(p)
  if FamLegendaryArmory and FamLegendaryArmory.Open then FamLegendaryArmory.Open(p) else send(p, "Result", false, "The Legendary Armory isn't open right now.") end
end, 1)
guard("LegForge", function(p, which)
  local f = F()
  local s = legState(p)
  which = tonumber(which)
  if which == 1 and s == 1 then f.legForge(p, 7)
  elseif which == 2 and s == 2 then f.legForge(p, 6)
  else send(p, "Result", false, "There is nothing to forge right now.") end
  send(p, "State", state(p))
end, 1)
guard("Forge", function(p) send(p, "Forge", forge(p)); send(p, "State", state(p)) end)
guard("ForgeBuy", function(p, slot)
  local ok, msg = doForgeBuy(p, slot)
  send(p, "Result", ok, msg)
  send(p, "Forge", forge(p)); send(p, "State", state(p))
end, 0.5)
guard("ForgeSwap", function(p)
  if not (FamRN and FamRN.vrilSwap) then send(p, "Result", false, "Swap isn't ready."); return end
  local ok, msg = FamRN.vrilSwap(p)
  send(p, "Result", ok, ok and msg or msg)
  send(p, "Forge", forge(p)); send(p, "State", state(p))
end, 1)
AIO.AddHandlers("FamVrilServer", H)

------------------------------------------------------------------ events / commands
RegisterPlayerEvent(4, function(_, p) local g = gl(p); helloed[g] = nil; lastReq[g] = nil; pendingForge[g] = nil end)
RegisterPlayerEvent(3, function(_, p)
  if P() and P().getRow and P().getRow(gl(p)) then teachForge(p) end
end)
RegisterPlayerEvent(5, function(_, p, spell)
  local sid = spell
  if type(spell) == "table" or type(spell) == "userdata" then
    local ok, v = pcall(function() return spell:GetEntry() end)
    if ok then sid = v end
  end
  if sid ~= FORGE_SPELL then return end
  local g = gl(p)
  local e = pendingForge[g]; pendingForge[g] = nil
  local f = F()
  if not e or not f then return end
  if p:GetItemCount(e) > 0 then return end
  local ok, why = f.pay(p, 1, 15)
  if not ok then
    if helloed[g] then send(p, "Result", false, why) end
    return
  end
  f.grant(p, e, 1)
  f.charge(p, 1, 15)
  print(string.format("[FamVrilUI] %s forged %d", p:GetName(), e))
  if helloed[g] then
    send(p, "Result", true, "The Forge answers. Item granted.")
    send(p, "Forge", forge(p)); send(p, "State", state(p))
  end
end)

-- ".vril" opens the panel when the client has the addon; otherwise explains. Blocks only this exact command.
RegisterPlayerEvent(42, function(event, p, command)
  local cmd = ((command or ""):lower():match("^%s*%.?(%S+)")) or ""
  if cmd ~= "vril" then return end
  if isBot(p) then return false end
  if helloed[gl(p)] then send(p, "Open", "paths")
  else p:SendBroadcastMessage("|cff66ccff[Vril]|r The Vril panel needs the FamVril addon on your computer. Talk to Whiz for the menu version.") end
  return false
end)

PrintInfo("[FamVrilUI] panel server v" .. VER .. " loaded (AIO handler FamVrilServer)")
