--[[ 12_subclass_system.lua  --  Family LAN "Vril Path" (ClassScrolls) system, PHASE 2 (all 31 paths)
  Plan: ClassScrolls-PLAN.md rev 16 (sections 2f.3, 3.2b, 3.3-3.9, 5.4).  Staged by WoWbot 2026-10-10.
  Ships DISABLED: install as 12_subclass_system.lua.off and rename in the maintenance window.
  Player-facing name is "Vril Path"; internal names (subclass, familylan_subclass*) stay.
  Does NOT touch 11_ogre_caveman_talk.lua (chat handlers here never return a value).
]]
local VP_VERSION = "p2-20261010"

------------------------------------------------------------------ constants
local MENU            = 6010300          -- player-gossip menu id (also gossip_menu range)
local QUEST           = 6010300          -- "Patience, Young Grasshopper"
local TOME            = 900001           -- Arcane Tome of Displacement (mod-travel-book)
local BANANA          = 500533           -- Space Banana
local SPELL_TRAIN     = 950547           -- Vril Path Training (C++ -> Lua handoff)
local SPELL_MONKEY    = 950548           -- Space Monkey (5 min look timer)
local SPELL_FRENZY    = 950545           -- Unholy Frenzy
local SPELL_WHIZ_MENU = 950600           -- Whiz menu bridge (Lua menu -> C++ Whiz menu) (plan 16.2.1)
local SPELL_WHIZ_GH   = 950601           -- Whiz Guild House bridge (C++ menu -> Lua teleport) (plan 16.2.3; hooked in 04_guildhouse_teleport.lua)
local MEDIVH_ENTRY    = 601264           -- Whiz Z. McWizardface (QOL-Followers trainer)
local WHIZ            = "Whiz Z. McWizardface"
local WHIZ_COLOR      = "|cffff80ff"
local COOLDOWN        = 3600             -- 1 hour between changes
local STILL_SECONDS   = 180              -- 3 minutes
local SKILL_BASE      = 1000             -- SkillLine = 1000 + subclass_id
local OUR_SPELL_LO, OUR_SPELL_HI = 950000, 950548   -- P2: children 950484-950494/950511 are never in PATHS, so never taught   -- player spell range incl. the Phase 4 ranks below (selfHeal keeps everything taught via spells_csv)
local TXT_MAIN, TXT_BROWSE, TXT_COLLECT, TXT_INFO, TXT_QUEST = 6010300, 6010332, 6010333, 6010334, 6010350
local function TXT_PREVIEW(id) return 6010301 + id end   -- 6010301..6010331
local SOUND_LEVELUP   = 888
local SOUND_CHIME     = 3337                             -- "QUESTCOMPLETED" style chime (see README; verify in test)
local FIREWORK_SPELL  = 11540                            -- visual used by mod-fireworks-on-level (verify in README)
local PLAYER_VISIBLE_ITEM_1_ENTRYID = 283                -- UpdateFields.h: UNIT_END(0x94) + 0x87; stride 2, 19 slots
local QUEST_STATUS_INCOMPLETE = 3

local CLASS_NAME = {[1]="Warrior",[2]="Paladin",[3]="Hunter",[4]="Rogue",[5]="Priest",[6]="Death Knight",[7]="Shaman",[8]="Mage",[9]="Warlock",[11]="Druid"}
local CLASS_PLURAL = {[1]="Warriors",[2]="Paladins",[3]="Hunters",[4]="Rogues",[5]="Priests",[6]="Death Knights",[7]="Shamans",[8]="Mages",[9]="Warlocks",[11]="Druids"}
local POWER_OF_CLASS = {[1]="Rage",[4]="Energy",[6]="RunicPower"}   -- everyone else: Mana

-- 2d.4: each class can never pick its own echo (class id -> subclass id)
local BLOCKED = {[4]=20,[1]=21,[2]=22,[3]=23,[5]=24,[6]=25,[7]=26,[8]=27,[9]=28,[11]=29}
-- section 4: recommended (shown first with a gold star); only enabled paths are shown
local RECOMMENDED = {[1]={22,2,18},[2]={21,3,30},[3]={17,14,20},[4]={18,14,13},[5]={6,3,11},
                     [6]={8,4,9},[7]={19,6,5},[8]={4,0,24},[9]={11,9,8},[11]={1,17,30}}

-- All 31 paths (phase 1: only Necromancer enabled). color = theme color for menus (P1).
local PATHS = {
 [0]={name="Arcanist",color="ff9f6cff"},[1]={name="Astromancer",color="ff7fb2ff"},[2]={name="Centurion",color="ffc0a060"},
 [3]={name="Chaplain",color="fffff0a0"},[4]={name="Cryomancer",color="ff80e0ff"},[5]={name="Geomancer",color="ffc08040"},
 [6]={name="Hydromancer",color="ff40a0ff"},[7]={name="Monk",color="ff60ff90"},[8]={name="Necromancer",color="ff8fd36b"},
 [9]={name="Nethermancer",color="ffb060ff"},[10]={name="Pyromancer",color="ffff7030"},[11]={name="Shadowmancer",color="ff9060c0"},
 [12]={name="Siren",color="ff60e0e0"},[13]={name="Time Bender",color="ffe0d060"},[14]={name="Venomancer",color="ff70d040"},
 [15]={name="Witch Doctor",color="ff40c0a0"},[16]={name="Tinker",color="ffd0a040"},[17]={name="Beastcaller",color="ffc08060"},
 [18]={name="Swashbuckler",color="ffff9060"},[19]={name="Stormcaller",color="ff70a0ff"},[20]={name="Shadowblade",color="fffff569"},
 [21]={name="Warlord",color="ffc79c6e"},[22]={name="Crusader",color="fff58cba"},[23]={name="Ranger",color="ffabd473"},
 [24]={name="Cleric",color="ffffffff"},[25]={name="Deathbringer",color="ffc41f3b"},[26]={name="Totemist",color="ff0070de"},
 [27]={name="Archmage",color="ff69ccf0"},[28]={name="Demonologist",color="ff9482c9"},[29]={name="Wildshaper",color="ffff7d0a"},
 [30]={name="Bard",color="ffffb0f0"},
}
-- Necromancer kit (generated ids: subclass_spells.lua from gen_subclass_dbc.py; kept inline so the script is one file)
PATHS[8].enabled = true
PATHS[8].icon    = "Spell_Shadow_RaiseDead"
PATHS[8].slots = {
  { slot=1, name="Cripple",         unlock=10, Mana=950128, Rage=950129, Energy=950130, RunicPower=950131, icon="Spell_Shadow_Cripple",       what="slows an enemy down" },
  { slot=2, name="Bone Armor",      unlock=10, Mana=950132, Rage=950133, Energy=950134, RunicPower=950135, icon="Spell_Shadow_UnholyStrength", what="a bone shield that soaks up damage", bp=61, ppl=24.35 },
  { slot=3, name="Power Release",   unlock=10, Mana=950136, Rage=950137, Energy=950138, RunicPower=950139, icon="Spell_Shadow_ShadowMend",     what="dark magic that hurts over time", bp=53, ppl=16.97 },
  { slot=4, name="Summon Skeleton", unlock=30, Mana=950140, Rage=950141, Energy=950142, RunicPower=950143, icon="Spell_Shadow_RaiseDead",      what="a Skeleton friend for 1 minute", capstone=true },
  { slot=5, name="Raise Ally",      unlock=20, Mana=950541, Rage=950542, Energy=950543, RunicPower=950544, icon="Spell_Shadow_DeadofNight",    what="bring a fallen friend back, even mid-fight", bonus=true },
}
PATHS[8].guardian = 601131
PATHS[8].bundle = { set="Plagueheart Raiment", items={22510,22511,22506,22509,22505,22504,22508,22507},
                    tabard=500509, tabardName="Necromancer Tabard", petSpell=53316, petName="Ghostly Skull", title=186 }
-- Phase 2 kits (generated by gen_p2_sql_lua.py from SPELLS.csv / COS.csv; ids = vrilpath_spells.lua)
PATHS[0].enabled = true
PATHS[0].icon    = "Ability_Mage_ArcaneBarrage"
PATHS[0].slots = {
  { slot=1, name="Mystical Bolt", unlock=10, Mana=950000, Rage=950001, Energy=950002, RunicPower=950003, icon="Spell_Arcane_StudentOfMagic", what="hurts an enemy with magic" },
  { slot=2, name="Force Blast", unlock=10, Mana=950004, Rage=950005, Energy=950006, RunicPower=950007, icon="Spell_Shadow_DeathPact", what="hurts all enemies around you" },
  { slot=3, name="Der'izu Focus", unlock=10, Mana=950008, Rage=950009, Energy=950010, RunicPower=950011, icon="Spell_Arcane_StarFire", what="makes you stronger for a while" },
  { slot=4, name="Arcane Breath", unlock=30, Mana=950012, Rage=950013, Energy=950014, RunicPower=950015, icon="Ability_Mage_ArcaneBarrage", what="hurts enemies in front of you", capstone=true },
}
PATHS[0].bundle = { set="Tirisfal Regalia", items={30206,30205,30207,30210,30196}, tabard=500501, tabardName="Arcanist Tabard", petSpell=35156, petName="Mana Wyrmling", title=178 }
PATHS[1].enabled = true
PATHS[1].icon    = "Spell_Shadow_RainOfFire"
PATHS[1].slots = {
  { slot=1, name="Astral Focus", unlock=10, Mana=950016, Rage=950017, Energy=950018, RunicPower=950019, icon="Spell_Nature_AbolishMagic", what="makes an enemy weaker" },
  { slot=2, name="Wrath of the Astromancer", unlock=10, Mana=950020, Rage=950021, Energy=950022, RunicPower=950023, icon="Spell_Arcane_ArcaneTorrent", what="hurts an enemy over time" },
  { slot=3, name="Lightning Cloud", unlock=10, Mana=950024, Rage=950025, Energy=950026, RunicPower=950027, icon="Spell_Nature_CallStorm", what="hurts enemies in a spot you pick" },
  { slot=4, name="Rain of Fire", unlock=30, Mana=950028, Rage=950029, Energy=950030, RunicPower=950031, icon="Spell_Shadow_RainOfFire", what="hurts enemies in a spot you pick", capstone=true },
}
PATHS[1].bundle = { set="Kirin Tor Garb", items={46249,46250,46251,46252,46253}, tabard=500502, tabardName="Astromancer Tabard", petSpell=75613, petName="Celestial Dragon", title=179 }
PATHS[2].enabled = true
PATHS[2].icon    = "Spell_Nature_LightningOverload"
PATHS[2].slots = {
  { slot=1, name="Blood Heal", unlock=10, Mana=950032, Rage=950033, Energy=950034, RunicPower=950035, icon="Spell_Holy_BlessedLife", what="heals you" },
  { slot=2, name="Spellbreaker", unlock=10, Mana=950036, Rage=950037, Energy=950038, RunicPower=950039, icon="Ability_Warrior_ShieldMastery", what="a hit that stops enemy spells" },
  { slot=3, name="Sonic Strike", unlock=10, Mana=950040, Rage=950041, Energy=950042, RunicPower=950043, icon="Spell_Holy_Silence", what="hurts enemies in front of you" },
  { slot=4, name="Arcane Flurry", unlock=30, Mana=950044, Rage=950045, Energy=950046, RunicPower=950047, icon="Spell_Nature_LightningOverload", what="hurts all enemies around you", capstone=true },
}
PATHS[2].bundle = { set="Lightbringer Battlegear", items={30990,30982,30993,30997,30989,34561,34431,34485}, tabard=500503, tabardName="Centurion Tabard", petSpell=78381, petName="Mini Thor", title=180 }
PATHS[3].enabled = true
PATHS[3].icon    = "Spell_Holy_HolyBolt"
PATHS[3].slots = {
  { slot=1, name="Flame of the Heavens", unlock=10, Mana=950048, Rage=950049, Energy=950050, RunicPower=950051, icon="Ability_Hunter_Readiness", what="makes you stronger for a while" },
  { slot=2, name="Renew", unlock=10, Mana=950052, Rage=950053, Energy=950054, RunicPower=950055, icon="Spell_Holy_Renew", what="heals a friend over time" },
  { slot=3, name="Power of Prayer", unlock=10, Mana=950056, Rage=950057, Energy=950058, RunicPower=950059, icon="INV_Jewelry_Talisman_06", what="makes you stronger for a while" },
  { slot=4, name="Holy Bolt Volley", unlock=30, Mana=950060, Rage=950061, Energy=950062, RunicPower=950063, icon="Spell_Holy_HolyBolt", what="hurts a group of enemies", capstone=true },
  { slot=5, name="Prayer of Elune", unlock=10, Mana=950512, Rage=950513, Energy=950514, RunicPower=950515, icon="Spell_Holy_Resurrection", what="brings a fallen friend back to life", bonus=true },
}
PATHS[3].bundle = { set="Vestments of Absolution", items={31068,31063,31060,31069,31066,34562,34527,34435}, tabard=500504, tabardName="Chaplain Tabard", petSpell=53082, petName="Tyrael's Hilt", title=181 }
PATHS[4].enabled = true
PATHS[4].icon    = "Spell_Frost_FrostNova"
PATHS[4].slots = {
  { slot=1, name="Frost Mist", unlock=10, Mana=950064, Rage=950065, Energy=950066, RunicPower=950067, icon="Spell_Frost_Wisp", what="hurts enemies in a spot you pick" },
  { slot=2, name="Frost Armor", unlock=10, Mana=950068, Rage=950069, Energy=950070, RunicPower=950071, icon="Spell_Frost_FrostArmor02", what="makes you stronger for a while" },
  { slot=3, name="Frost Shock", unlock=10, Mana=950072, Rage=950073, Energy=950074, RunicPower=950075, icon="Spell_Frost_FrostShock", what="hurts an enemy with magic" },
  { slot=4, name="Frost Nova", unlock=30, Mana=950076, Rage=950077, Energy=950078, RunicPower=950079, icon="Spell_Frost_FrostNova", what="hurts and stops enemies nearby", capstone=true },
}
PATHS[4].bundle = { set="Frostfire Regalia", items={22502,22503,22498,22501,22497,22496,22500,22499}, tabard=500505, tabardName="Cryomancer Tabard", petSpell=55068, petName="Unhatched Mr. Chilly", title=182 }
PATHS[5].enabled = true
PATHS[5].icon    = "Spell_Nature_Earthquake"
PATHS[5].slots = {
  { slot=1, name="Quick Flame Ward", unlock=10, Mana=950080, Rage=950081, Energy=950082, RunicPower=950083, icon="Spell_Fire_SealOfFire", what="a shield that soaks up damage" },
  { slot=2, name="Razor Mane", unlock=10, Mana=950084, Rage=950085, Energy=950086, RunicPower=950087, icon="Spell_Nature_Thorns", what="makes you stronger for a while" },
  { slot=3, name="Lightning Bolt", unlock=10, Mana=950088, Rage=950089, Energy=950090, RunicPower=950091, icon="Spell_Nature_Lightning", what="hurts an enemy with magic" },
  { slot=4, name="Summon Earth Rumbler", unlock=30, Mana=950092, Rage=950093, Energy=950094, RunicPower=950095, icon="Spell_Nature_Earthquake", what="calls a friend to fight with you", capstone=true },
}
PATHS[5].guardian = 601130
PATHS[5].bundle = { set="The Earthshatterer", items={22468,22470,22469,22466,22465,22467,22464,22471}, tabard=500506, tabardName="Geomancer Tabard", petSpell=62491, petName="Teldrassil Sproutling", title=183 }
PATHS[6].enabled = true
PATHS[6].icon    = "Spell_Frost_SummonWaterElemental"
PATHS[6].slots = {
  { slot=1, name="Water Nova", unlock=10, Mana=950096, Rage=950097, Energy=950098, RunicPower=950099, icon="Spell_Frost_FrostNova", what="hurts all enemies around you" },
  { slot=2, name="Watery Grave", unlock=10, Mana=950100, Rage=950101, Energy=950102, RunicPower=950103, icon="Spell_Shadow_DemonBreath", what="stuns an enemy" },
  { slot=3, name="Water Blast", unlock=10, Mana=950104, Rage=950105, Energy=950106, RunicPower=950107, icon="Spell_Frost_SummonWaterElemental", what="hurts an enemy with magic" },
  { slot=4, name="Tidal Burst", unlock=30, Mana=950108, Rage=950109, Energy=950110, RunicPower=950111, icon="Spell_Frost_SummonWaterElemental", what="hurts all enemies around you", capstone=true },
}
PATHS[6].bundle = { set="Tidefury Raiment", items={28231,27510,28349,27909,27802}, tabard=500507, tabardName="Hydromancer Tabard", petSpell=28738, petName="Turtle Box", title=184 }
PATHS[7].enabled = true
PATHS[7].icon    = "Spell_Holy_LesserHeal"
PATHS[7].slots = {
  { slot=1, name="Kick", unlock=10, Mana=950112, Rage=950113, Energy=950114, RunicPower=950115, icon="Ability_Kick", what="a hit that stops enemy spells" },
  { slot=2, name="Storm Punch", unlock=10, Mana=950116, Rage=950117, Energy=950118, RunicPower=950119, icon="Spell_Nature_LightningBolt", what="a big weapon hit" },
  { slot=3, name="Rune Punch", unlock=10, Mana=950120, Rage=950121, Energy=950122, RunicPower=950123, icon="INV_Misc_Rune_04", what="a big weapon hit" },
  { slot=4, name="Ringing Slap", unlock=30, Mana=950124, Rage=950125, Energy=950126, RunicPower=950127, icon="Spell_Holy_LesserHeal", what="a big weapon hit", capstone=true },
}
PATHS[7].bundle = { set="Thunderheart Harness", items={31042,31034,31039,31044,31048,34556,34444,34573}, tabard=500508, tabardName="Monk Tabard", petSpell=69541, petName="Pandaren Monk", title=185 }
PATHS[9].enabled = true
PATHS[9].icon    = "Spell_Arcane_MassDispel"
PATHS[9].slots = {
  { slot=1, name="Bloodcrystal Surge", unlock=10, Mana=950144, Rage=950145, Energy=950146, RunicPower=950147, icon="INV_Misc_QirajiCrystal_02", what="makes you stronger for a while" },
  { slot=2, name="Drain Life", unlock=10, Mana=950148, Rage=950149, Energy=950150, RunicPower=950151, icon="Spell_Shadow_LifeDrain02", what="steals health from an enemy" },
  { slot=3, name="Nether Shock", unlock=10, Mana=950152, Rage=950153, Energy=950154, RunicPower=950155, icon="Spell_Shadow_SoulLeech_3", what="hurts an enemy with magic" },
  { slot=4, name="Netherbreath", unlock=30, Mana=950156, Rage=950157, Energy=950158, RunicPower=950159, icon="Spell_Arcane_MassDispel", what="hurts enemies in front of you", capstone=true },
}
PATHS[9].bundle = { set="Voidheart Raiment", items={28963,28968,28966,28967,28964}, tabard=500510, tabardName="Nethermancer Tabard", petSpell=51716, petName="Nether Ray Fry", title=187 }
PATHS[10].enabled = true
PATHS[10].icon    = "Spell_Fire_LavaSpawn"
PATHS[10].slots = {
  { slot=1, name="Fel Fireball", unlock=10, Mana=950160, Rage=950161, Energy=950162, RunicPower=950163, icon="Spell_Fire_FelFlameBolt", what="hurts an enemy with magic" },
  { slot=2, name="Flame Shock", unlock=10, Mana=950164, Rage=950165, Energy=950166, RunicPower=950167, icon="Spell_Fire_FlameShock", what="hurts an enemy over time" },
  { slot=3, name="Mark of Flames", unlock=10, Mana=950168, Rage=950169, Energy=950170, RunicPower=950171, icon="Spell_Fire_Fireball", what="makes an enemy weaker" },
  { slot=4, name="Summon Fire Elemental", unlock=30, Mana=950172, Rage=950173, Energy=950174, RunicPower=950175, icon="Spell_Fire_LavaSpawn", what="calls a friend to fight with you", capstone=true },
}
PATHS[10].guardian = 601132
PATHS[10].bundle = { set="Nemesis Raiment", items={16933,16927,16934,16928,16930,16931,16929,16932}, tabard=500511, tabardName="Pyromancer Tabard", petSpell=46599, petName="Phoenix Hatchling", title=188 }
PATHS[11].enabled = true
PATHS[11].icon    = "Spell_Shadow_Shadowfury"
PATHS[11].slots = {
  { slot=1, name="Dark Mending", unlock=10, Mana=950176, Rage=950177, Energy=950178, RunicPower=950179, icon="Spell_Shadow_ChillTouch", what="heals a friend" },
  { slot=2, name="Shadow Blast", unlock=10, Mana=950180, Rage=950181, Energy=950182, RunicPower=950183, icon="Spell_Shadow_FocusedPower", what="hurts an enemy with magic" },
  { slot=3, name="Shadowguard", unlock=10, Mana=950184, Rage=950185, Energy=950186, RunicPower=950187, icon="Spell_Shadow_RagingScream", what="makes you stronger for a while" },
  { slot=4, name="Shadow Nova", unlock=30, Mana=950188, Rage=950189, Energy=950190, RunicPower=950191, icon="Spell_Shadow_Shadowfury", what="hurts all enemies around you", capstone=true },
}
PATHS[11].bundle = { set="Malefic Raiment", items={31050,31051,31053,31054,31052,34564,34436,34541}, tabard=500512, tabardName="Shadowmancer Tabard", petSpell=51851, petName="Vampiric Batling", title=189 }
PATHS[12].enabled = true
PATHS[12].icon    = "Spell_Shadow_ImpPhaseShift"
PATHS[12].slots = {
  { slot=1, name="Enveloping Winds", unlock=10, Mana=950192, Rage=950193, Energy=950194, RunicPower=950195, icon="Spell_Nature_Cyclone", what="stuns an enemy" },
  { slot=2, name="Ribbon of Souls", unlock=10, Mana=950196, Rage=950197, Energy=950198, RunicPower=950199, icon="Spell_Nature_Lightning", what="hurts an enemy with magic" },
  { slot=3, name="Viscous Shield", unlock=10, Mana=950200, Rage=950201, Energy=950202, RunicPower=950203, icon="Spell_Frost_Wisp", what="a shield that soaks up damage" },
  { slot=4, name="Banshee Shriek", unlock=30, Mana=950204, Rage=950205, Energy=950206, RunicPower=950207, icon="Spell_Shadow_ImpPhaseShift", what="hurts and stops enemies nearby", capstone=true },
}
PATHS[12].bundle = { set="Avatar Regalia", items={30160,30161,30162,30159,30163}, tabard=500513, tabardName="Siren Tabard", petSpell=15067, petName="Sprite Darter Egg", title=190 }
PATHS[13].enabled = true
PATHS[13].icon    = "Spell_Arcane_Arcane01"
PATHS[13].slots = {
  { slot=1, name="Haste Other", unlock=10, Mana=950208, Rage=950209, Energy=950210, RunicPower=950211, icon="Spell_Nature_AstralRecalGroup", what="makes a friend faster" },
  { slot=2, name="Slow", unlock=10, Mana=950212, Rage=950213, Energy=950214, RunicPower=950215, icon="Spell_Nature_Slow", what="makes an enemy weaker" },
  { slot=3, name="Time Shock", unlock=10, Mana=950216, Rage=950217, Energy=950218, RunicPower=950219, icon="Spell_Nature_UnleashedRage", what="hurts an enemy with magic" },
  { slot=4, name="Time Stop", unlock=30, Mana=950220, Rage=950221, Energy=950222, RunicPower=950223, icon="Spell_Arcane_Arcane01", what="hurts and stops enemies nearby", capstone=true },
}
PATHS[13].bundle = { set="Tempest Regalia", items={31056,31055,31058,31059,31057,34574,34447,34557}, tabard=500514, tabardName="Time Bender Tabard", petSpell=10696, petName="Azure Whelpling", title=191 }
PATHS[14].enabled = true
PATHS[14].icon    = "Spell_Nature_NullifyPoison"
PATHS[14].slots = {
  { slot=1, name="Poison Bolt", unlock=10, Mana=950224, Rage=950225, Energy=950226, RunicPower=950227, icon="Spell_Nature_CorrosiveBreath", what="hurts an enemy over time" },
  { slot=2, name="Poison Shield", unlock=10, Mana=950228, Rage=950229, Energy=950230, RunicPower=950231, icon="Spell_Nature_ElementalShields", what="makes you stronger for a while" },
  { slot=3, name="Poisoned Thrust", unlock=10, Mana=950232, Rage=950233, Energy=950234, RunicPower=950235, icon="Ability_Poisons", what="a big weapon hit" },
  { slot=4, name="Leech Poison", unlock=30, Mana=950236, Rage=950237, Energy=950238, RunicPower=950239, icon="Spell_Nature_NullifyPoison", what="steals health from an enemy", capstone=true },
}
PATHS[14].bundle = { set="Corruptor Raiment", items={30211,30212,30213,30215,30214}, tabard=500515, tabardName="Venomancer Tabard", petSpell=61351, petName="Cobra Hatchling", title=192 }
PATHS[15].enabled = true
PATHS[15].icon    = "Spell_Totem_WardOfDraining"
PATHS[15].slots = {
  { slot=1, name="Healing Ward", unlock=10, Mana=950240, Rage=950241, Energy=950242, RunicPower=950243, icon="Spell_Holy_LayOnHands", what="puts down a magic ward" },
  { slot=2, name="Hex", unlock=10, Mana=950244, Rage=950245, Energy=950246, RunicPower=950247, icon="Spell_Nature_Polymorph", what="stops an enemy for a moment" },
  { slot=3, name="Voodoo Doll", unlock=10, Mana=950248, Rage=950249, Energy=950250, RunicPower=950251, icon="INV_Misc_Idol_02", what="hurts an enemy with magic" },
  { slot=4, name="Ward of Zum'rah", unlock=30, Mana=950252, Rage=950253, Energy=950254, RunicPower=950255, icon="Spell_Totem_WardOfDraining", what="puts down a magic ward", capstone=true },
  { slot=5, name="Revive", unlock=10, Mana=950516, Rage=950517, Energy=950518, RunicPower=950519, icon="Spell_Holy_Resurrection", what="brings a fallen friend back to life", bonus=true },
}
PATHS[15].guardian = {601133, 601134}
PATHS[15].bundle = { set="The Five Thunders", items={22097,22101,22102,22095,22099,22098,22100,22096}, tabard=500516, tabardName="Witch Doctor Tabard", petSpell=43918, petName="Mojo", title=193 }
PATHS[16].enabled = true
PATHS[16].icon    = "INV_Egg_05"
PATHS[16].slots = {
  { slot=1, name="Rocket Launch", unlock=10, Mana=950256, Rage=950257, Energy=950258, RunicPower=950259, icon="Spell_Fire_Fireball02", what="hurts an enemy with magic" },
  { slot=2, name="Rockets", unlock=10, Mana=950260, Rage=950261, Energy=950262, RunicPower=950263, icon="INV_Misc_MissileLarge_Red", what="hurts enemies in a spot you pick" },
  { slot=3, name="Gnomish Flame Turret", unlock=10, Mana=950264, Rage=950265, Energy=950266, RunicPower=950267, icon="Spell_Fire_SearingTotem", what="puts down a magic ward" },
  { slot=4, name="Mechanical Dragonling", unlock=30, Mana=950268, Rage=950269, Energy=950270, RunicPower=950271, icon="INV_Egg_05", what="calls a friend to fight with you", capstone=true },
}
PATHS[16].guardian = {601135, 601136}
PATHS[16].bundle = { set="Doomplate Battlegear", items={28403,27497,28225,27870,27771}, tabard=500517, tabardName="Tinker Tabard", petSpell=54187, petName="Clockwork Rocket Bot", title=194 }
PATHS[17].enabled = true
PATHS[17].icon    = "INV_Misc_Bone_06"
PATHS[17].slots = {
  { slot=1, name="Gore", unlock=10, Mana=950272, Rage=950273, Energy=950274, RunicPower=950275, icon="Ability_Gouge", what="a big weapon hit" },
  { slot=2, name="Tendon Rip", unlock=10, Mana=950276, Rage=950277, Energy=950278, RunicPower=950279, icon="Ability_CriticalStrike", what="makes an enemy weaker" },
  { slot=3, name="Battle Roar", unlock=10, Mana=950280, Rage=950281, Energy=950282, RunicPower=950283, icon="Ability_Racial_BloodRage", what="makes the whole team stronger" },
  { slot=4, name="Summon Tamed Raptor", unlock=30, Mana=950284, Rage=950285, Energy=950286, RunicPower=950287, icon="INV_Misc_Bone_06", what="calls a friend to fight with you", capstone=true },
}
PATHS[17].guardian = 601137
PATHS[17].bundle = { set="Beast Lord Armor", items={28228,27474,28275,27874,27801}, tabard=500518, tabardName="Beastcaller Tabard", petSpell=67418, petName="Ravasaur Hatchling", title=195 }
PATHS[18].enabled = true
PATHS[18].icon    = "Spell_Fire_FireBolt02"
PATHS[18].slots = {
  { slot=1, name="Cannon Blast", unlock=10, Mana=950288, Rage=950289, Energy=950290, RunicPower=950291, icon="Spell_Fire_FlameBolt", what="hurts an enemy with magic" },
  { slot=2, name="Grappling Hook", unlock=10, Mana=950292, Rage=950293, Energy=950294, RunicPower=950295, icon="INV_Weapon_Rifle_15", what="jumps at an enemy" },
  { slot=3, name="Summon Blood Parrot", unlock=10, Mana=950296, Rage=950297, Energy=950298, RunicPower=950299, icon="INV_Helmet_66", what="calls a friend to fight with you" },
  { slot=4, name="Cannonball", unlock=30, Mana=950300, Rage=950301, Energy=950302, RunicPower=950303, icon="Spell_Fire_FireBolt02", what="hurts enemies in a spot you pick", capstone=true },
}
PATHS[18].guardian = 601138
PATHS[18].bundle = { set="Bloodfang Armor", items={16910,16906,16911,16905,16907,16908,16909,16832,12185,6796}, tabard=500519, tabardName="Swashbuckler Tabard", petSpell=10683, petName="Parrot Cage (Green Wing Macaw)", title=196 }
PATHS[19].enabled = true
PATHS[19].icon    = "Spell_Lightning_LightningBolt01"
PATHS[19].slots = {
  { slot=1, name="Chain Lightning", unlock=10, Mana=950304, Rage=950305, Energy=950306, RunicPower=950307, icon="Spell_Nature_ChainLightning", what="hurts a group of enemies" },
  { slot=2, name="Thunderstorm", unlock=10, Mana=950308, Rage=950309, Energy=950310, RunicPower=950311, icon="Spell_Nature_StormReach", what="hurts all enemies around you" },
  { slot=3, name="Zephyr", unlock=10, Mana=950312, Rage=950313, Energy=950314, RunicPower=950315, icon="Spell_Nature_Tranquility", what="makes the whole team stronger" },
  { slot=4, name="Ball Lightning", unlock=30, Mana=950316, Rage=950317, Energy=950318, RunicPower=950319, icon="Spell_Lightning_LightningBolt01", what="hurts enemies in a spot you pick", capstone=true },
}
PATHS[19].bundle = { set="Stormcaller's Garb", items={21372,21373,21374,21375,21376}, tabard=500520, tabardName="Stormcaller Tabard", petSpell=45127, petName="Dragon Kite", title=197 }
PATHS[20].enabled = true
PATHS[20].icon    = "Ability_Vanish"
PATHS[20].slots = {
  { slot=1, name="Stealth", unlock=10, Mana=950320, Rage=950321, Energy=950322, RunicPower=950323, icon="Ability_Stealth", what="hides you from enemies" },
  { slot=2, name="Sinister Strike", unlock=10, Mana=950324, Rage=950325, Energy=950326, RunicPower=950327, icon="Spell_Shadow_RitualOfSacrifice", what="a big weapon hit" },
  { slot=3, name="Sprint", unlock=10, Mana=950328, Rage=950329, Energy=950330, RunicPower=950331, icon="Ability_Rogue_Sprint", what="makes you run super fast" },
  { slot=4, name="Vanish", unlock=30, Mana=950332, Rage=950333, Energy=950334, RunicPower=950335, icon="Ability_Vanish", what="vanish in a puff of smoke", capstone=true },
}
PATHS[20].bundle = { set="Bonescythe Armor", items={22476,22477,22478,22479,22480,22481,22482,22483}, tabard=500521, tabardName="Shadowblade Tabard", petSpell=10675, petName="Black Tabby Cat", title=198 }
PATHS[21].enabled = true
PATHS[21].icon    = "Ability_Warrior_Bladestorm"
PATHS[21].slots = {
  { slot=1, name="Charge", unlock=10, Mana=950336, Rage=950337, Energy=950338, RunicPower=950339, icon="Ability_Warrior_Charge", what="jumps at an enemy" },
  { slot=2, name="Heroic Strike", unlock=10, Mana=950340, Rage=950341, Energy=950342, RunicPower=950343, icon="Ability_Rogue_Ambush", what="a big weapon hit" },
  { slot=3, name="Battle Shout", unlock=10, Mana=950344, Rage=950345, Energy=950346, RunicPower=950347, icon="Ability_Warrior_BattleShout", what="makes the whole team stronger" },
  { slot=4, name="Bladestorm", unlock=30, Mana=950348, Rage=950349, Energy=950350, RunicPower=950351, icon="Ability_Warrior_Bladestorm", what="hurts all enemies around you", capstone=true },
}
PATHS[21].bundle = { set="Battlegear of Wrath", items={16959,16960,16961,16962,16963,16964,16965,16966}, tabard=500522, tabardName="Warlord Tabard", petSpell=63318, petName="Murkimus' Little Spear", title=199 }
PATHS[22].enabled = true
PATHS[22].icon    = "Spell_Holy_LayOnHands"
PATHS[22].slots = {
  { slot=1, name="Holy Light", unlock=10, Mana=950352, Rage=950353, Energy=950354, RunicPower=950355, icon="Spell_Holy_HolyBolt", what="heals a friend" },
  { slot=2, name="Judgement", unlock=10, Mana=950356, Rage=950357, Energy=950358, RunicPower=950359, icon="Spell_Holy_RighteousFury", what="hurts an enemy with magic" },
  { slot=3, name="Divine Shield", unlock=10, Mana=950360, Rage=950361, Energy=950362, RunicPower=950363, icon="Spell_Holy_DivineIntervention", what="a bubble that blocks all damage" },
  { slot=4, name="Lay on Hands", unlock=30, Mana=950364, Rage=950365, Energy=950366, RunicPower=950367, icon="Spell_Holy_LayOnHands", what="a giant heal for a friend", capstone=true },
  { slot=5, name="Redemption", unlock=10, Mana=950520, Rage=950521, Energy=950522, RunicPower=950523, icon="Spell_Holy_Resurrection", what="brings a fallen friend back to life", bonus=true },
}
PATHS[22].bundle = { set="Judgement Armor", items={16951,16952,16953,16954,16955,16956,16957,16958}, tabard=500523, tabardName="Crusader Tabard", petSpell=62609, petName="Argent Squire", title=200 }
PATHS[23].enabled = true
PATHS[23].icon    = "Ability_Druid_KingoftheJungle"
PATHS[23].slots = {
  { slot=1, name="Arcane Shot", unlock=10, Mana=950368, Rage=950369, Energy=950370, RunicPower=950371, icon="Ability_ImpalingBolt", what="hurts an enemy with magic" },
  { slot=2, name="Aspect of the Cheetah", unlock=10, Mana=950372, Rage=950373, Energy=950374, RunicPower=950375, icon="Ability_Mount_JungleTiger", what="makes you run super fast" },
  { slot=3, name="Freezing Trap", unlock=10, Mana=950376, Rage=950377, Energy=950378, RunicPower=950379, icon="Spell_Frost_ChainsOfIce", what="hurts and stops enemies nearby" },
  { slot=4, name="Call of the Wild", unlock=30, Mana=950380, Rage=950381, Energy=950382, RunicPower=950383, icon="Ability_Druid_KingoftheJungle", what="calls a friend to fight with you", capstone=true },
}
PATHS[23].guardian = 601139
PATHS[23].bundle = { set="Dragonstalker Armor", items={16935,16936,16937,16938,16939,16940,16941,16942}, tabard=500524, tabardName="Ranger Tabard", petSpell=15999, petName="Worg Carrier", title=201 }
PATHS[24].enabled = true
PATHS[24].icon    = "Spell_Holy_PrayerOfHealing02"
PATHS[24].slots = {
  { slot=1, name="Power Word: Shield", unlock=10, Mana=950384, Rage=950385, Energy=950386, RunicPower=950387, icon="Spell_Holy_PowerWordShield", what="a shield that soaks up damage" },
  { slot=2, name="Renew", unlock=10, Mana=950388, Rage=950389, Energy=950390, RunicPower=950391, icon="Spell_Holy_Renew", what="heals a friend over time" },
  { slot=3, name="Psychic Scream", unlock=10, Mana=950392, Rage=950393, Energy=950394, RunicPower=950395, icon="Spell_Shadow_PsychicScream", what="hurts and stops enemies nearby" },
  { slot=4, name="Prayer of Healing", unlock=30, Mana=950396, Rage=950397, Energy=950398, RunicPower=950399, icon="Spell_Holy_PrayerOfHealing02", what="heals the whole team", capstone=true },
  { slot=5, name="Resurrection", unlock=10, Mana=950524, Rage=950525, Energy=950526, RunicPower=950527, icon="Spell_Holy_Resurrection", what="brings a fallen friend back to life", bonus=true },
}
PATHS[24].bundle = { set="Vestments of Transcendence", items={16919,16920,16921,16922,16923,16924,16925,16926}, tabard=500525, tabardName="Cleric Tabard", petSpell=61725, petName="Spring Rabbit's Foot", title=202 }
PATHS[25].enabled = true
PATHS[25].icon    = "Spell_DeathKnight_ArmyOfTheDead"
PATHS[25].slots = {
  { slot=1, name="Death Grip", unlock=10, Mana=950400, Rage=950401, Energy=950402, RunicPower=950403, icon="Spell_DeathKnight_Strangulate", what="pulls an enemy over to you" },
  { slot=2, name="Icy Touch", unlock=10, Mana=950404, Rage=950405, Energy=950406, RunicPower=950407, icon="Spell_DeathKnight_IceTouch", what="hurts an enemy with magic" },
  { slot=3, name="Anti-Magic Shell", unlock=10, Mana=950408, Rage=950409, Energy=950410, RunicPower=950411, icon="Spell_Shadow_AntiMagicShell", what="a shield that soaks up damage" },
  { slot=4, name="Army of the Dead", unlock=30, Mana=950412, Rage=950413, Energy=950414, RunicPower=950415, icon="Spell_DeathKnight_ArmyOfTheDead", what="calls a friend to fight with you", capstone=true },
}
PATHS[25].guardian = 601140
PATHS[25].bundle = { set="Scourgeborne Battlegear", items={39617,39618,39619,39620,39621}, tabard=500526, tabardName="Deathbringer Tabard", petSpell=52615, petName="Frosty's Collar", title=203 }
PATHS[26].enabled = true
PATHS[26].icon    = "Spell_Nature_BloodLust"
PATHS[26].slots = {
  { slot=1, name="Lightning Bolt", unlock=10, Mana=950416, Rage=950417, Energy=950418, RunicPower=950419, icon="Spell_Nature_Lightning", what="hurts an enemy with magic" },
  { slot=2, name="Windfury", unlock=10, Mana=950420, Rage=950421, Energy=950422, RunicPower=950423, icon="Spell_Nature_Windfury", what="makes the whole team stronger" },
  { slot=3, name="Earthbind Totem", unlock=10, Mana=950424, Rage=950425, Energy=950426, RunicPower=950427, icon="Spell_Nature_StrengthOfEarthTotem02", what="puts down a magic ward" },
  { slot=4, name="Bloodlust", unlock=30, Mana=950428, Rage=950429, Energy=950430, RunicPower=950431, icon="Spell_Nature_BloodLust", what="makes the whole team super fast", capstone=true, alliance={Mana=950480, Rage=950481, Energy=950482, RunicPower=950483, name="Heroism"} },
  { slot=5, name="Ancestral Spirit", unlock=10, Mana=950528, Rage=950529, Energy=950530, RunicPower=950531, icon="Spell_Nature_Regenerate", what="brings a fallen friend back to life", bonus=true },
}
PATHS[26].guardian = 601142
PATHS[26].bundle = { set="The Ten Storms", items={16943,16944,16945,16946,16947,16948,16949,16950}, tabard=500527, tabardName="Totemist Tabard", petSpell=69536, petName="Wind Rider Cub", title=204 }
PATHS[27].enabled = true
PATHS[27].icon    = "Spell_Fire_Fireball02"
PATHS[27].slots = {
  { slot=1, name="Blink", unlock=10, Mana=950432, Rage=950433, Energy=950434, RunicPower=950435, icon="Spell_Arcane_Blink", what="jumps at an enemy" },
  { slot=2, name="Frost Nova", unlock=10, Mana=950436, Rage=950437, Energy=950438, RunicPower=950439, icon="Spell_Frost_FrostNova", what="hurts and stops enemies nearby" },
  { slot=3, name="Polymorph", unlock=10, Mana=950440, Rage=950441, Energy=950442, RunicPower=950443, icon="Spell_Nature_Polymorph", what="stops an enemy for a moment" },
  { slot=4, name="Pyroblast", unlock=30, Mana=950444, Rage=950445, Energy=950446, RunicPower=950447, icon="Spell_Fire_Fireball02", what="hurts an enemy with magic", capstone=true },
}
PATHS[27].bundle = { set="Netherwind Regalia", items={16818,16912,16913,16914,16915,16916,16917,16918}, tabard=500528, tabardName="Archmage Tabard", petSpell=61472, petName="Kirin Tor Familiar", title=205 }
PATHS[28].enabled = true
PATHS[28].icon    = "Spell_Shadow_SummonInfernal"
PATHS[28].slots = {
  { slot=1, name="Corruption", unlock=10, Mana=950448, Rage=950449, Energy=950450, RunicPower=950451, icon="Spell_Shadow_AbominationExplosion", what="hurts an enemy over time" },
  { slot=2, name="Fear", unlock=10, Mana=950452, Rage=950453, Energy=950454, RunicPower=950455, icon="Spell_Shadow_Possession", what="stops an enemy for a moment" },
  { slot=3, name="Create Healthstone", unlock=10, Mana=950456, Rage=950457, Energy=950458, RunicPower=950459, icon="INV_Stone_04", what="makes a healthstone snack" },
  { slot=4, name="Summon Infernal", unlock=30, Mana=950460, Rage=950461, Energy=950462, RunicPower=950463, icon="Spell_Shadow_SummonInfernal", what="calls a friend to fight with you", capstone=true },
}
PATHS[28].guardian = 601141
PATHS[28].bundle = { set="Felheart Raiment", items={16803,16804,16805,16806,16807,16808,16809,16810}, tabard=500529, tabardName="Demonologist Tabard", petSpell=32298, petName="Netherwhelp's Collar", title=206 }
PATHS[29].enabled = true
PATHS[29].icon    = "Ability_Druid_Starfall"
PATHS[29].slots = {
  { slot=1, name="Rejuvenation", unlock=10, Mana=950464, Rage=950465, Energy=950466, RunicPower=950467, icon="Spell_Nature_Rejuvenation", what="heals a friend over time" },
  { slot=2, name="Entangling Roots", unlock=10, Mana=950468, Rage=950469, Energy=950470, RunicPower=950471, icon="Spell_Nature_StrangleVines", what="holds an enemy in place" },
  { slot=3, name="Travel Form", unlock=10, Mana=950472, Rage=950473, Energy=950474, RunicPower=950475, icon="Ability_Druid_TravelForm", what="makes you run super fast" },
  { slot=4, name="Starfall", unlock=30, Mana=950476, Rage=950477, Energy=950478, RunicPower=950479, icon="Ability_Druid_Starfall", what="hurts all enemies around you", capstone=true },
  { slot=5, name="Revive", unlock=10, Mana=950532, Rage=950533, Energy=950534, RunicPower=950535, icon="Ability_Druid_LunarGuidance", what="brings a fallen friend back to life", bonus=true },
}
PATHS[29].bundle = { set="Stormrage Raiment", items={16897,16898,16899,16900,16901,16902,16903,16904}, tabard=500530, tabardName="Wildshaper Tabard", petSpell=45082, petName="Tiny Sporebat", title=207 }
PATHS[30].enabled = true
PATHS[30].icon    = "INV_RoseBouquet01"
PATHS[30].slots = {
  { slot=1, name="Song of Battle", unlock=10, Mana=950495, Rage=950496, Energy=950497, RunicPower=950498, icon="Spell_Holy_LastingDefense", what="makes the whole team stronger" },
  { slot=2, name="Drums of Restoration", unlock=10, Mana=950499, Rage=950500, Energy=950501, RunicPower=950502, icon="INV_Misc_Drum_07", what="heals the team over time" },
  { slot=3, name="Sonic Blast", unlock=10, Mana=950503, Rage=950504, Energy=950505, RunicPower=950506, icon="Spell_Shadow_Teleport", what="hurts and stuns an enemy" },
  { slot=4, name="Dance Party", unlock=30, Mana=950507, Rage=950508, Energy=950509, RunicPower=950510, icon="INV_RoseBouquet01", what="makes the whole team super fast", capstone=true },
  { slot=5, name="Encore", unlock=40, Mana=950536, Rage=950537, Energy=950538, RunicPower=950539, icon="Spell_Holy_Resurrection", what="brings ALL fallen friends back at once", bonus=true },
}
PATHS[30].bundle = { set="Enigma Vestments", items={21344,21347,21346,21343,21345}, tabard=500532, tabardName="Bard Tabard", petSpell=10680, petName="Parrot Cage (Cockatiel)", title=208 }
local RAISE_ALLY = {[950541]=true,[950542]=true,[950543]=true,[950544]=true}

-- P10: Whiz's wise one-liners when the menu opens
local WISDOM = {
 "Patience, young grasshopper.",
 "Every path begins with one small step... and a snack.",
 "A wizard is never late. Except on Tuesdays.",
 "The best spell is the one you remember to cast.",
 "Even a skeleton was once a beginner.",
 "Choose with your heart. Then check your mana.",
 "The stars are wise, but they never do their homework.",
 "Magic is like soup: better when shared.",
}

-- Phase 4: Vril Avatar preview data (plan 17.16) + the two form ranks + two regular-form
-- Ultimates per path (plan 17.6.3 / 17.15.4). AVATAR is non-local on purpose: the sample-page
-- rows are copied literally from the plan so no name drifts.
AVATAR = {
 [0]={f30="Azure Warder",u30="Nullfield",e30="a magic pulse that hurts and hushes enemies near you",ic30="Spell_Nature_Lightning",f50="Arcanist Doan",u50="Detonation",e50="a magic bubble keeps you safe, then BOOM all around you",ic50="Spell_Fire_SelfDestruct"},
 [1]={f30="Sunfury Astromancer",u30="Sunfury Starbolt",e30="a big star bolt at one enemy",ic30="Spell_Holy_SearingLight",f50="High Astromancer Solarian",u50="Blinding Light",e50="a bright flash that dazzles a group of enemies",ic50="Spell_Shadow_ChillTouch"},
 [2]={f30="Scarlet Centurion",u30="Phalanx Slam",e30="slam your shield down and stun enemies around you",ic30="INV_Cask_01",f50="King Varian Wrynn",u50="Heroic Leap",e50="leap into the fight and stun everyone where you land",ic50="INV_Misc_Gem_LionsEye_01"},
 [3]={f30="Scarlet Chaplain",u30="Scarlet Benediction",e30="a big heal for you and your whole party",ic30="Spell_Holy_HolySmite",f50="High Inquisitor Whitemane",u50="Whitemane's Absolution",e50="a huge party heal that also removes a bad spell",ic50="Spell_Magic_MageArmor"},
 [4]={f30="Ice Elemental",u30="Ice Spikes",e30="ice spikes burst up and push enemies away",ic30="Spell_Frost_Glacier",f50="Lady Jaina Proudmoore",u50="Proudmoore's Frostbolt",e50="a giant frostbolt that freezes one enemy",ic50="Spell_Frost_FrostBolt02"},
 [5]={f30="Earth Elemental",u30="Call Boulder",e30="throw a boulder that knocks one enemy down",ic30="Ability_GolemStormBolt",f50="Archaedas",u50="Ground Tremor",e50="shake the ground and stun enemies around you",ic50="Spell_Nature_Earthquake"},
 [6]={f30="Water Elemental",u30="Water Spout",e30="a water spout tosses a group of enemies up",ic30="Spell_Frost_SummonWaterElemental",f50="Hydromancer Velratha",u50="Tidal Wave",e50="a big wave that hits and slows enemies in front",ic50="Spell_Frost_ChillingBlast"},
 [7]={f30="Scarlet Monk",u30="Flurry of Fists",e30="six super-fast punches on one enemy",ic30="Spell_Nature_WispHeal",f50="Coren Direbrew",u50="Barreled!",e50="trap an enemy inside a barrel",ic50="INV_Cask_01"},
 [8]={f30="Scourge Necromancer",u30="Shadowflame",e30="a cone of shadow fire in front of you",ic30="Spell_Shadow_CorruptingWave",f50="Darkmaster Gandling",u50="Shadow Portal",e50="send an enemy into the shadows for a moment",ic50="Spell_Shadow_SealOfKings"},
 [9]={f30="Sunfury Nethermancer",u30="Nether Blast",e30="a nether bolt that knocks one enemy back",ic30="INV_Misc_MonsterClaw_03",f50="High Nethermancer Zerevor",u50="Arcane Bolt Barrage",e50="three quick magic bolts at one enemy",ic50="Spell_Arcane_StarFire"},
 [10]={f30="Greater Fire Elemental",u30="Blast Wave",e30="a wave of fire that hurts and slows enemies near you",ic30="Spell_Holy_Excorcism_02",f50="Pyromancer Loregrain",u50="Molten Blast",e50="a huge fireball at one enemy",ic50="Spell_Fire_Fire"},
 [11]={f30="Shadowmage",u30="Umbral Doom",e30="a shadow curse that hurts over time",ic30="Spell_Shadow_ShadowWordPain",f50="Twilight Lord Kelris",u50="Twilight Slumber",e50="a shadow blast that puts one enemy to sleep",ic50="Spell_Shadow_DreamCoil"},
 [12]={f30="Coilfang Siren",u30="Arcane Flare",e30="a magic flare at one enemy",ic30="Spell_Nature_StarFall",f50="Lady Vashj",u50="Shock Blast",e50="a shock that stuns one enemy",ic50="Spell_Shadow_AuraOfDarkness"},
 [13]={f30="Guardian of Time",u30="Time Step",e30="pop up behind an enemy and strike",ic30="Spell_Nature_WispSplode",f50="Chromie",u50="Temporal Vortex",e50="a time swirl that hurts and slows a group",ic50="INV_Misc_StoneTablet_04"},
 [14]={f30="Cult Plaguebringer",u30="Plague Cloud",e30="a green cloud that hurts enemies inside it",ic30="Spell_Fire_SealOfFire",f50="High Priest Venoxis",u50="Venom Spit",e50="poison that hurts over time and weakens healing",ic50="Spell_Nature_CorrosiveBreath"},
 [15]={f30="Sandfury Witch Doctor",u30="Sandfury Jinx",e30="a jinx that hurts over time and slows",ic30="Spell_Shadow_LifeDrain02",f50="Witch Doctor Zum'rah",u50="Shadow Bolt Volley",e50="shadow bolts at up to 5 enemies",ic50="Spell_Shadow_ShadowBolt"},
 [16]={f30="Gan'arg Tinkerer",u30="Fel Iron Bomb",e30="throw a bomb that stuns one enemy",ic30="Spell_Fire_SelfDestruct",f50="Mimiron",u50="Plasma Blast",e50="a big plasma beam at one enemy",ic50="Spell_Fire_Incinerate"},
 [17]={f30="Beastmaster",u30="Call the Pack",e30="spirit wolves pounce on a group of enemies",ic30="Spell_Holy_DivinePurpose",f50="Rexxar",u50="Stampede",e50="a beast stampede knocks enemies away",ic50="Ability_Hunter_BeastMastery"},
 [18]={f30="Bloodsail Swashbuckler",u30="Drunken Skull Crack",e30="a pirate bonk that stuns one enemy",ic30="INV_Drink_10",f50="Captain Greenskin",u50="Poisoned Harpoon",e50="harpoon an enemy, pull it close and hold it",ic50="Ability_Poisons"},
 [19]={f30="Lightning Elemental",u30="Lightning Ring",e30="a ring of lightning around you",ic30="Spell_Nature_Purge",f50="Stormcaller Brundir",u50="Lightning Whirl",e50="lightning zaps up to 5 enemies",ic50="Ability_Whirlwind"},
 [20]={f30="Twilight Shadowblade",u30="Twilight Ambush",e30="sneak behind an enemy and stun it",ic30="INV_Ammo_Snowball",f50="Veras Darkshadow",u50="Envenom",e50="one big poison strike",ic50="Ability_Rogue_Blind"},
 [21]={f30="Kolkar Battle Lord",u30="Hoof Stomp",e30="stomp to stun enemies around you",ic30="Ability_WarStomp",f50="Garrosh Hellscream",u50="Hellscream",e50="a war cry that scares enemies away",ic50="Spell_Frost_Stun"},
 [22]={f30="Knight of the Silver Hand",u30="Hammer of the Silver Hand",e30="throw a holy hammer that stuns one enemy",ic30="Spell_Holy_SealOfSalvation",f50="Uther the Lightbringer",u50="Lightbringer's Consecration",e50="holy ground that hurts enemies and heals friends",ic50="Spell_Shadow_SiphonMana"},
 [23]={f30="Dark Ranger",u30="Black Arrow",e30="a shadow arrow that hurts over time",ic30="Ability_TheBlackArrow",f50="Lady Sylvanas Windrunner",u50="Shriek of the Highborne",e50="a banshee scream that scares enemies in front",ic50="Spell_Shadow_ShadowBolt"},
 [24]={f30="Aldor Anchorite",u30="Anchorite's Grace",e30="a huge heal and a shield on one friend",ic30="Spell_Holy_PowerWordShield",f50="Prophet Velen",u50="Prophet's Holy Nova",e50="holy light that hurts enemies and heals friends",ic50="Spell_Holy_HolyNova"},
 [25]={f30="Ymirjar Deathbringer",u30="Death Rune",e30="a rune strike that heals you",ic30="INV_Hammer_Unique_Sulfuras",f50="Deathbringer Saurfang",u50="Blood Nova",e50="a burst of blood magic that heals you",ic50="Spell_Shadow_DeathCoil"},
 [26]={f30="Lesser Air Elemental",u30="Air Burst",e30="a gust of wind that pushes enemies away",ic30="Spell_Nature_WispSplode",f50="Thrall",u50="Lava Burst",e50="a blast of lava at one enemy",ic50="Spell_Fire_Volcano"},
 [27]={f30="Scarlet Archmage",u30="Scarlet Fireball",e30="a big fireball at one enemy",ic30="Spell_Fire_FlameBolt",f50="Khadgar",u50="Arcane Volley",e50="magic missiles at up to 5 enemies",ic50="Spell_Arcane_StarFire"},
 [28]={f30="Dreadlord",u30="Carrion Swarm",e30="a swarm of bats that hurts and weakens healing",ic30="Spell_Shadow_CarrionSwarm",f50="Lord Jaraxxus",u50="Incinerate Flesh",e50="green fel fire that burns over time",ic50="Spell_Fire_Incinerate"},
 [29]={f30="Treant",u30="Rootquake",e30="a stomp that roots enemies around you",ic30="Spell_Nature_StrangleVines",f50="Alzzin the Wildshaper",u50="Wither",e50="a curse that hurts over time and slows",ic50="Spell_Nature_NullifyDisease"},
 [30]={f30="Felmusk Satyr",u30="Felmusk Pipes",e30="a pipe tune that makes enemies dizzy",ic30="Ability_GolemThunderClap",f50="Hearthsinger Forresten",u50="Enchanting Lullaby",e50="a lullaby that puts enemies to sleep and heals friends",ic50="Spell_Shadow_SoothingKiss"},
}
for id, a in pairs(AVATAR) do                     -- spells live on the PATHS kit (slots 6-9); AVATAR is preview data only
  PATHS[id].avatar = a
end

------------------------------------------------------------------ Phase 4 kit slots (plan 17.13, 17.6.3, 17.15.4)
-- AVATAR preview rows above carry the plan-exact names/effects/icons for showPath; this block
-- hooks the four learnable slots onto each path's kit so the EXISTING resync teaches them.
-- Lua-side feature flag: Lua cannot read the worldserver conf. The C++ layer reads
-- FamilyLan.VrilForms.Enable from worldserver.conf; this constant must be kept IN SYNC
-- with it (documented in README_phase3_stage2.txt. Both = 1 live, both = 0 off).
local ENABLED_FORMS = true   -- gates the Avatar spell slots (7/6), the Ultimate slots (8/9) and the preview lines

-- spell bases: spell id = base + path_id (0..30)
local FORM30_BASE, FORM50_BASE = 950620, 950549     -- Rank 1 at 30 / Rank 2 at 50 (plan 17.3.2/17.13)
local ULT1_BASE, ULT2_BASE = 950660, 950700         -- Ultimate I at 60 / II at 80 (plan 17.15.4)

-- Phase 4 kit slots per path (17.6.3 / 17.15.4): the existing resync teaches/forgets them
-- and spells_csv stores them, so RESET / the 1-hour switch / class-echo blocks unlearn them
-- with the rest. Bots never learn them (the resync returns early for bots; see selfHeal/resync).
for id = 0, 30 do
  if ENABLED_FORMS then
    table.insert(PATHS[id].slots,
      { slot=6, name="Vril Form: " .. AVATAR[id].f50, unlock=50, icon=AVATAR[id].ic50, what="the level-50 Boss form (2 min), from 17.4", form50=true })
    table.insert(PATHS[id].slots,
      { slot=7, name="Vril Form: " .. AVATAR[id].f30, unlock=30, icon=AVATAR[id].ic30, what="the level-30 form (1 min), from 17.4.2", form30=true })
    table.insert(PATHS[id].slots,
      { slot=8, name=AVATAR[id].u30, unlock=60, icon=AVATAR[id].ic30, what="Avatar Ultimate I: " .. AVATAR[id].e30, ult=true })
    table.insert(PATHS[id].slots,
      { slot=9, name=AVATAR[id].u50, unlock=80, icon=AVATAR[id].ic50, what="Avatar Ultimate II: " .. AVATAR[id].e50, ult=true })
  end
end

------------------------------------------------------------------ helpers
local function now() return os.time() end
local function gl(p) return p:GetGUIDLow() end
local function say(p, msg) p:SendBroadcastMessage(WHIZ_COLOR .. WHIZ .. " whispers: " .. msg .. "|r") end
local function info(p, msg) p:SendBroadcastMessage("|cffffd100[Vril Path]|r " .. msg) end
local function colored(id) local P = PATHS[id]; return "|c" .. P.color .. P.name .. "|r" end
local function powerOf(p) return POWER_OF_CLASS[p:GetClass()] or "Mana" end
local function isGM(p) return p:GetGMRank() >= 1 end

-- Same bot test as 07_racial_mounts.lua (IsPlayerbot / IsRandomBot / headless / bot account names)
local function safeCall(obj, method, ...)          -- same bot test as 07_racial_mounts.lua
  local f = obj and obj[method]
  if type(f) ~= "function" then return nil end
  local ok, r = pcall(f, obj, ...)
  if ok then return r end
  return nil
end
local function IsBot(p)
  if safeCall(p, "IsPlayerbot") == true or safeCall(p, "IsRandomBot") == true then return true end
  if safeCall(p, "GetPlayerIP") == "headless" then return true end
  local acc = safeCall(p, "GetAccountName")
  if type(acc) == "string" then
    local u = string.upper(acc)
    if u:find("^RNDBOT") or u:find("PLAYERBOT") or u:find("^AHBOT") then return true end
  end
  return false
end

local function minutesLeft(sec) if sec < 60 then return sec .. " sec" end return math.ceil(sec / 60) .. " min" end

------------------------------------------------------------------ DB
CharDBExecute([[CREATE TABLE IF NOT EXISTS familylan_subclass (
  guid INT UNSIGNED NOT NULL PRIMARY KEY, subclass_id TINYINT UNSIGNED NOT NULL, class_at_set TINYINT UNSIGNED NOT NULL,
  spells_csv VARCHAR(64) NOT NULL, set_time INT UNSIGNED NOT NULL, changes SMALLINT UNSIGNED NOT NULL DEFAULT 0)]])
-- Phase 4: with slots 6-9 the csv can hit 9 ids ~90 chars; widen the column (stage SQL item 5 widens it too).
CharDBExecute([[ALTER TABLE familylan_subclass MODIFY COLUMN spells_csv VARCHAR(255) NOT NULL]])
-- 16.9.3: one-time login-whisper marker ("I've learned new tricks!..."). Lua-owned, in acore_characters.
-- (character_settings has no free row per character for this; the cd_notified column in
--  familylan_subclass_grants is taken for the path-change cooldown notice, so a fresh table.)
CharDBExecute([[CREATE TABLE IF NOT EXISTS familylan_whiz_intro (
  guid INT UNSIGNED NOT NULL PRIMARY KEY, intwhispered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)]])
CharDBExecute([[CREATE TABLE IF NOT EXISTS familylan_subclass_grants (
  guid INT UNSIGNED NOT NULL PRIMARY KEY, granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, how VARCHAR(8),
  last_change INT UNSIGNED NULL, cd_notified TINYINT NOT NULL DEFAULT 1)]])
CharDBExecute([[CREATE TABLE IF NOT EXISTS familylan_subclass_rewards (
  guid INT UNSIGNED NOT NULL, subclass_id TINYINT UNSIGNED NOT NULL, granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  transmog_ok TINYINT NOT NULL DEFAULT 0, tabard_how VARCHAR(8) NOT NULL DEFAULT 'bag',
  looks_new VARCHAR(255) NOT NULL DEFAULT '', pet_new TINYINT NOT NULL DEFAULT 0, title_new TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (guid, subclass_id))]])

local function getRow(guid)
  local q = CharDBQuery("SELECT subclass_id, class_at_set, spells_csv, set_time FROM familylan_subclass WHERE guid=" .. guid)
  if not q then return nil end
  return { id = q:GetUInt32(0), class = q:GetUInt32(1), csv = q:GetString(2), set_time = q:GetUInt32(3) }
end
local function getLastChange(guid)
  local q = CharDBQuery("SELECT last_change, cd_notified FROM familylan_subclass_grants WHERE guid=" .. guid)
  if not q or q:IsNull(0) then return nil, 1 end
  return q:GetUInt32(0), q:GetUInt32(1)
end
local function touchCooldown(guid)
  CharDBExecute(string.format("INSERT INTO familylan_subclass_grants (guid, how, last_change, cd_notified) VALUES (%d,'menu',%d,0) " ..
    "ON DUPLICATE KEY UPDATE last_change=VALUES(last_change), cd_notified=0", guid, now()))
end
local function cooldownLeft(p)
  local last = getLastChange(gl(p))
  if not last then return 0 end              -- first pick: no cooldown
  local left = last + COOLDOWN - now()
  return left > 0 and left or 0
end
local function hasReward(guid, id)
  return CharDBQuery(string.format("SELECT 1 FROM familylan_subclass_rewards WHERE guid=%d AND subclass_id=%d", guid, id)) ~= nil
end

------------------------------------------------------------------ visibility (computed counts, rev 12)
local function visiblePaths(p)
  local list, blocked = {}, BLOCKED[p:GetClass()]
  for id = 0, 30 do
    local P = PATHS[id]
    if P and P.enabled and id ~= blocked then list[#list + 1] = id end
  end
  return list
end
local function canPick(p, id)
  local P = PATHS[id]
  if not P or not P.enabled then return false, "That Vril Path isn't ready yet." end
  if BLOCKED[p:GetClass()] == id then
    return false, CLASS_PLURAL[p:GetClass()] .. " can't pick " .. P.name .. " - it's your own class!"
  end
  return true
end

------------------------------------------------------------------ teach / reset
local function spellFor(slot, p)
  local t = (slot.alliance and p:IsAlliance()) and slot.alliance or slot   -- Totemist: Heroism for Alliance
  return t[powerOf(p)]
end

-- Phase 4 (17.6.3/17.15.4): slots 6-9 carry their spell id directly (form50/form30/ult flags),
-- not per power type. 950620+id / 950549+id = Vril Avatar Rank 1/2, 950660+id / 950700+id =
-- regular-form Ultimates. Slot-number constants the C++ Avatar layer keys on:
-- spells_csv slots 1-4 = class kit, 5 = bonus (ClassScrolls res), 6 = Rank 2, 7 = Rank 1,
-- 8 = Ultimate I, 9 = Ultimate II.
local function avatarSpellFor(slot, id)
  if slot.form50 then return FORM50_BASE + id end
  if slot.form30 then return FORM30_BASE + id end
  if slot.ult then return (slot.unlock == 60 and ULT1_BASE or ULT2_BASE) + id end
  return nil
end

-- the Phase 4 spell row may not be in the DBC yet (another agent owns rows
-- 950549-950579 / 950620-950650 / 950660+/950700+): skip gracefully and resync later.
local function avatarReady(sid)
  local ok, info = pcall(GetSpellInfo, sid)
  return ok and info ~= nil
end

local function despawnGuardians(p, id)
  local P = PATHS[id]
  if not P or not P.guardian then return end
  local list = type(P.guardian) == "table" and P.guardian or { P.guardian }
  for _, entry in ipairs(list) do
    for _, c in ipairs(p:GetCreaturesInRange(500, entry) or {}) do
      if c:GetOwnerGUID() == p:GetGUID() then c:DespawnOrUnsummon(0) end
    end
  end
end

-- teach every slot whose unlock level is reached; returns list of newly taught slot tables
local function teachEligible(p, id, quiet)
  local P, taught, csv = PATHS[id], {}, {}
  p:SetSkill(SKILL_BASE + id, 0, 1, 1)     -- spellbook tab (3.6); harmless if LearnSpell already added it
  for _, s in ipairs(P.slots) do
    local sid = avatarSpellFor(s, id) or spellFor(s, p)   -- Phase 4 slots 6-9 carry their own spell id
    if not avatarSpellFor(s, id) or avatarReady(sid) then -- missing DBC row: skip gracefully, resync later
      if p:GetLevel() >= s.unlock then
        if not p:HasSpell(sid) then p:LearnSpell(sid); taught[#taught + 1] = s end
        csv[#csv + 1] = tostring(sid)
      end
    else
      info(p, "A " .. P.name .. " spell is still on its way. It will arrive the next time Whiz checks your path.")
    end
  end
  return taught, table.concat(csv, ",")
end

local function resetPath(p, row, why)
  row = row or getRow(gl(p))
  if not row then return end
  for sid in string.gmatch(row.csv, "%d+") do
    sid = tonumber(sid)
    p:RemoveAura(sid)
    if p:HasSpell(sid) then p:RemoveSpell(sid) end
  end
  despawnGuardians(p, row.id)
  p:SetSkill(SKILL_BASE + row.id, 0, 0, 0)
  CharDBExecute("DELETE FROM familylan_subclass WHERE guid=" .. gl(p))
end

local function saveRow(p, id, csv, bumpChanges)
  CharDBExecute(string.format("REPLACE INTO familylan_subclass (guid, subclass_id, class_at_set, spells_csv, set_time, changes) " ..
    "VALUES (%d,%d,%d,'%s',%d,%d)", gl(p), id, p:GetClass(), csv, now(), bumpChanges or 0))
end

local function celebrate(p, bigText)
  p:PlayDirectSound(SOUND_LEVELUP)
  p:CastSpell(p, FIREWORK_SPELL, true)
  p:SendAreaTriggerMessage(bigText)
end

------------------------------------------------------------------ cosmetics bundle (3.9)
local function grantBundle(p, id)
  local P, guid = PATHS[id], gl(p)
  local B = P.bundle
  if not B or hasReward(guid, id) then return end
  local acct = p:GetAccountId()
  -- which looks does the account already have? (for an exact UNDO list)
  local have = {}
  local q = CharDBQuery("SELECT item_template_id FROM mod_transmog_plus_appearances WHERE account_id=" .. acct ..
                        " AND item_template_id IN (" .. table.concat(B.items, ",") .. ")")
  if q then repeat have[q:GetUInt32(0)] = true until not q:NextRow() end
  local newLooks, transmogOk, viaDb = {}, 1, false
  for _, e in ipairs(B.items) do
    if not have[e] then newLooks[#newLooks + 1] = tostring(e) end
    if not have[e] and not p:HasItem(e, 1, true) then
      local it = p:AddItem(e, 1)                 -- mod-transmog-plus pickup hook records the look
      if it then p:RemoveItem(e, 1)
      else
        viaDb = true; transmogOk = 0
        CharDBExecute(string.format("INSERT IGNORE INTO mod_transmog_plus_appearances (account_id, item_template_id) VALUES (%d,%d)", acct, e))
      end
    end
  end
  if viaDb then info(p, "Your new looks will appear after you log out and back in.") end
  local how = "bag"
  if not p:AddItem(B.tabard, 1) then
    how = "mail"
    SendMail("Your " .. B.tabardName .. " has arrived!", "A gift from " .. WHIZ .. ". Wear it proudly!", guid, 0, 61, 0, 0, 0, B.tabard, 1)
    info(p, "Your bags are full, so your " .. B.tabardName .. " is waiting in your mailbox!")
  end
  local petNew = p:HasSpell(B.petSpell) and 0 or 1
  if petNew == 1 then p:LearnSpell(B.petSpell) end
  local titleNew = p:HasTitle(B.title) and 0 or 1
  if titleNew == 1 then p:SetKnownTitle(B.title) end
  CharDBExecute(string.format("INSERT IGNORE INTO familylan_subclass_rewards (guid, subclass_id, transmog_ok, tabard_how, looks_new, pet_new, title_new) " ..
    "VALUES (%d,%d,%d,'%s','%s',%d,%d)", guid, id, transmogOk, how, table.concat(newLooks, ","), petNew, titleNew))
  info(p, "First-pick reward: the " .. B.set .. " looks, the " .. B.tabardName .. ", a " .. B.petName .. " pet and a new title!")
end

------------------------------------------------------------------ SET
local function setPath(p, id, opts)
  opts = opts or {}
  local ok, why = canPick(p, id)
  if not ok and not opts.force then info(p, why); return false end
  local old = getRow(gl(p))
  if old then resetPath(p, old) end
  local taught, csv = teachEligible(p, id)
  saveRow(p, id, csv, old and 1 or 0)
  if not opts.noCooldown then touchCooldown(gl(p)) end
  if not opts.silent then
    celebrate(p, "You are now a Junior " .. PATHS[id].name .. "!")
    info(p, "You are now a Junior " .. colored(id) .. "! Your new spells are in the " .. PATHS[id].name .. " tab of your spellbook.")
  end
  if not opts.noBundle then grantBundle(p, id) end
  return true
end

------------------------------------------------------------------ resync (3.5) + capstone/bonus (3.7, 3.7b)
-- selfHeal ranges (task item c): forget every family-LAN spell between OUR_SPELL_LO and
-- OUR_SPELL_HI that spells_csv does not keep, EXCEPT the ones with no DBC row (a spell that
-- was never teachable can't be on anyone's bar, so it has nothing to be forgotten).
local function selfHeal(p, keep)
  for sid = OUR_SPELL_LO, OUR_SPELL_HI do
    if not keep[sid] and (sid > 950548 or avatarReady(sid)) then   -- Phase 4 ids 950549+ are skipped while their row is missing
      if p:HasSpell(sid) then p:RemoveSpell(sid) end
    end
  end
end

local function resync(p, levelUp)
  if IsBot(p) then selfHeal(p, {}); return end
  local row = getRow(gl(p))
  if not row then selfHeal(p, {}); return end
  if row.class ~= p:GetClass() then
    resetPath(p, row)
    local ok = canPick(p, row.id)
    if not ok then
      info(p, "Your Vril Path " .. colored(row.id) .. " is your own class now, so it was removed. Pick a new one with " .. WHIZ .. " (no waiting)!")
      selfHeal(p, {}); return
    end
    setPath(p, row.id, { noCooldown = true, noBundle = true, silent = true })
    info(p, "Your " .. colored(row.id) .. " spells changed to match your class.")
    row = getRow(gl(p))
  end
  local taught, csv = teachEligible(p, row.id)
  if csv ~= row.csv then saveRow(p, row.id, csv, 0) end
  for _, s in ipairs(taught) do
    if s.capstone then celebrate(p, "Your " .. PATHS[row.id].name .. " power is complete: " .. s.name .. "!")
      info(p, "Your " .. colored(row.id) .. " power is complete: " .. s.name .. "!")
    elseif s.bonus then celebrate(p, "Bonus power unlocked: " .. s.name .. "!")
      info(p, "Bonus power unlocked: " .. s.name .. "!")
    end
  end
  local keep = {}
  for sid in string.gmatch(csv, "%d+") do keep[tonumber(sid)] = true end
  selfHeal(p, keep)
end

local function cooldownNotice(p)
  local last, notified = getLastChange(gl(p))
  if last and notified == 0 and now() >= last + COOLDOWN then
    info(p, "Your Vril Path can change again!")
    p:PlayDirectSound(SOUND_CHIME)
    CharDBExecute("UPDATE familylan_subclass_grants SET cd_notified=1 WHERE guid=" .. gl(p))
  end
end

------------------------------------------------------------------ menu (3.3, P1-P4, P6, P9, P10, P12)
-- release-next (2026-10-28): on the TEST realm GMs need Whiz's lesson too, and the refusal is the red pebble line (00_fam_release_next.lua)
local function questDone(p) return p:GetQuestRewardStatus(QUEST) or (isGM(p) and not (FamRN and FamRN.test())) end
local function lessonMsg(old) if (FamRN and FamRN.test()) then return FamRN.PEBBLE end return old end
local NAV_BACK, NAV_HOME = 1, 1
local function addNav(p, backIntid)
  p:GossipMenuAddItem(0, "« Back", 0, backIntid or 1)
  p:GossipMenuAddItem(0, "⌂ Home", 0, 1)
  p:GossipMenuAddItem(0, "⌂ Whiz menu", 0, 8)   -- 16.2.1 Lua->Whiz bridge: casts 950600 (WhizMenu.cpp shows Main)
end

local function showMain(p)
  p:GossipClearMenu()
  local row = getRow(gl(p))
  local cls = CLASS_NAME[p:GetClass()] or "?"
  p:GossipMenuAddItem(0, "|cff3f2a14Your class: " .. cls .. "   Vril Path: " .. (row and colored(row.id) or "none") .. "|r", 0, 1)
  if FamVrilUI and FamVrilUI.HasAddon and FamVrilUI.HasAddon(p) then   -- 32_vril_ui.lua: only offered when the FamVril addon said hello
    p:GossipMenuAddItem(0, "|cff66ccffOpen the Vril Paths panel|r (tabs, spells, armory)", 0, 10)
  end
  local blocked = BLOCKED[p:GetClass()]
  for _, id in ipairs(RECOMMENDED[p:GetClass()] or {}) do
    if PATHS[id] and PATHS[id].enabled and id ~= blocked then
      p:GossipMenuAddItem(3, "|cffffd100★|r Recommended for " .. CLASS_PLURAL[p:GetClass()] .. ": " .. colored(id), 0, 1000 + id)
    end
  end
  local n = #visiblePaths(p)
  p:GossipMenuAddItem(3, "Browse all " .. n .. " Vril Path" .. (n == 1 and "" or "s"), 0, 100)
  p:GossipMenuAddItem(0, "What's my Vril Path?", 0, 4)
  p:GossipMenuAddItem(0, "My Vril Path collection", 0, 5)
  p:GossipMenuAddItem(0, "⌂ Whiz menu", 0, 8)
  if FamLegendaryArmory then p:GossipMenuAddItem(1, "|cffff8000Legendary Armory|r", 0, 9) end   -- 28_legendary_armory.lua (mods-20261022)
  if row then
    local left = cooldownLeft(p)
    if left > 0 then p:GossipMenuAddItem(0, "Remove my Vril Path (ready in " .. minutesLeft(left) .. ")", 0, 6)
    else p:GossipMenuAddItem(0, "Remove my Vril Path", 0, 3, false, "Remove your Vril Path? Your powers go away until you pick a new one.") end
  end
  p:GossipSendMenu(TXT_MAIN, p, MENU)
end

local function showBrowse(p, page)
  p:GossipClearMenu()
  local list = visiblePaths(p)
  local pages = math.max(1, math.ceil(#list / 5))
  page = math.max(0, math.min(page, pages - 1))
  local rec = {}
  for _, id in ipairs(RECOMMENDED[p:GetClass()] or {}) do rec[id] = true end
  for i = page * 5 + 1, math.min(#list, page * 5 + 5) do
    local id = list[i]
    p:GossipMenuAddItem(3, (rec[id] and "|cffffd100★|r " or "") .. colored(id), 0, 1000 + id)
  end
  if page + 1 < pages then p:GossipMenuAddItem(0, "Next page (" .. (page + 2) .. "/" .. pages .. ")", 0, 100 + page + 1) end
  addNav(p, page > 0 and (100 + page - 1) or 1)
  p:GossipSendMenu(TXT_BROWSE, p, MENU)
end

-- Phase 2 preview "about N" damage math (slots 1-4 only; slots 6-9 have no bp/ppl).

local function scaled(s, lvl) return math.floor((s.bp + 1) + s.ppl * (math.min(lvl, 80) - 10)) end

local function showPath(p, id)
  p:GossipClearMenu()
  local P, lvl = PATHS[id], p:GetLevel()
  for _, s in ipairs(P.slots) do
    if not (s.form30 or s.form50 or s.ult) then   -- Avatar ranks/Ultimates come from the 3 preview lines below
    local badge = s.capstone and ("★ unlocks at level " .. s.unlock) or (s.bonus and ("Bonus, level " .. s.unlock) or ("level " .. s.unlock))
    local line = "|TInterface\\Icons\\" .. s.icon .. ":20|t " .. s.name .. ": " .. s.what
    if s.bp then line = line .. " (about " .. scaled(s, math.max(lvl, s.unlock)) .. " at your level)" end
    if lvl < s.unlock then line = line .. "  |cff808080" .. badge .. "|r" end
    p:GossipMenuAddItem(0, line, 0, 1000 + id)
    end
  end
  local B = P.bundle
  if B then
    if hasReward(gl(p), id) then p:GossipMenuAddItem(0, "First pick reward: already collected", 0, 1000 + id)
    else p:GossipMenuAddItem(0, "First pick reward: " .. B.set .. ", " .. B.tabardName .. ", " .. B.petName .. " pet, title \"the " .. P.name .. "\"", 0, 1000 + id) end
  end
  local row = getRow(gl(p))
  if row and row.id == id then
    p:GossipMenuAddItem(0, "This is your Vril Path!", 0, 1000 + id)
  else
    local ok, why = canPick(p, id)
    local left = cooldownLeft(p)
    if not ok then p:GossipMenuAddItem(0, "|cff808080" .. why .. "|r", 0, 1000 + id)
    elseif p:IsInCombat() then p:GossipMenuAddItem(0, "Finish your fight first!", 0, 1000 + id)
    elseif left > 0 and row then p:GossipMenuAddItem(0, "Change Vril Path (ready in " .. minutesLeft(left) .. ")", 0, 6)
    else p:GossipMenuAddItem(3, "Choose " .. P.name .. "!", 0, 2000 + id, false,
      "Become a " .. P.name .. "? You can change again in 1 hour.") end
  end
  -- Phase 4 preview (17.16): three Vril Avatar lines after the spell slots, gated on the
  -- Lua-side forms flag so a switched-off feature is never advertised. Grey "unlocks at
  -- level N" badge under the level. npct_text body unchanged (17.16: gossip options only).
  if ENABLED_FORMS then
    local a = P.avatar or AVATAR[id]
    local grey = "  |cff808080unlocks at level %d|r"
    local l30 = "Level 30: Vril Avatar - " .. a.f30 .. " (1 min) - Avatar Ultimate: " .. a.u30 .. " - " .. a.e30
    local l50 = "Level 50: Vril Avatar - " .. a.f50 .. " (2 min) - Avatar Ultimate: " .. a.u50 .. " - " .. a.e50
    local l60 = "Level 60/80: Ultimates usable in normal form - " .. a.u30 .. " at 60, " .. a.u50 .. " at 80 (one shared cooldown)"
    p:GossipMenuAddItem(0, (lvl < 30 and "|cff808080" or "") .. "|TInterface\\Icons\\" .. a.ic30 .. ":20|t " ..
      (lvl < 30 and l30 .. string.format(grey, 30) .. "|r" or l30), 0, 1000 + id)
    p:GossipMenuAddItem(0, (lvl < 50 and "|cff808080" or "") .. "|TInterface\\Icons\\" .. a.ic50 .. ":20|t " ..
      (lvl < 50 and l50 .. string.format(grey, 50) .. "|r" or l50), 0, 1000 + id)
    p:GossipMenuAddItem(0, (lvl < 60 and "|cff808080" or "") .. "|TInterface\\Icons\\" .. a.ic50 .. ":20|t " ..
      (lvl < 60 and l60 .. string.format(grey, 60) .. "|r" or l60), 0, 1000 + id)
  end
  addNav(p, 100)
  p:GossipSendMenu(TXT_PREVIEW(id), p, MENU)
end

local function describe(p)
  local row = getRow(gl(p))
  if not row then return "You don't have a Vril Path yet. Talk to " .. WHIZ .. " to pick one!" end
  local P, names = PATHS[row.id], {}
  for _, s in ipairs(PATHS[row.id].baseSlots or P.slots) do
    if not (s.form30 or s.form50 or s.ult) then
      if p:HasSpell(spellFor(s, p)) then names[#names + 1] = s.name
      else names[#names + 1] = s.name .. " (level " .. s.unlock .. ")" end
    end
  end
  local left = cooldownLeft(p)
  return "Your Vril Path: " .. colored(row.id) .. ". Spells: " .. table.concat(names, ", ") .. ". " ..
         (left > 0 and ("You can change it in " .. minutesLeft(left) .. ".") or "You can change it now.")
end

local function showInfo(p)
  p:GossipClearMenu()
  p:GossipMenuAddItem(0, describe(p), 0, 4)
  addNav(p, 1)
  p:GossipSendMenu(TXT_INFO, p, MENU)
end

local function showCollection(p)
  p:GossipClearMenu()
  local guid, owned, total, extra = gl(p), {}, #visiblePaths(p), 0
  local q = CharDBQuery("SELECT subclass_id FROM familylan_subclass_rewards WHERE guid=" .. guid)
  if q then repeat owned[q:GetUInt32(0)] = true until not q:NextRow() end
  local n, blocked = 0, BLOCKED[p:GetClass()]
  for id in pairs(owned) do if id == blocked then extra = extra + 1 else n = n + 1 end end
  p:GossipMenuAddItem(0, "Collected: " .. n .. "/" .. total .. (extra > 0 and (" (+" .. extra .. " bonus)") or ""), 0, 5)
  for id = 0, 30 do
    if owned[id] and PATHS[id].bundle then
      p:GossipMenuAddItem(0, colored(id) .. ": " .. PATHS[id].bundle.set .. ", " .. PATHS[id].bundle.tabardName .. ", " .. PATHS[id].bundle.petName .. ", title", 0, 5)
    end
  end
  p:GossipMenuAddItem(0, "I lost my tabard", 0, 7)
  addNav(p, 1)
  p:GossipSendMenu(TXT_COLLECT, p, MENU)
end

local function lostTabards(p)
  local q = CharDBQuery("SELECT subclass_id FROM familylan_subclass_rewards WHERE guid=" .. gl(p))
  local given = 0
  if q then repeat
    local B = PATHS[q:GetUInt32(0)] and PATHS[q:GetUInt32(0)].bundle
    if B and not p:HasItem(B.tabard, 1, true) then
      if p:AddItem(B.tabard, 1) then given = given + 1 else info(p, "Make room in your bags first!"); return end
    end
  until not q:NextRow() end
  info(p, given > 0 and "Here you go! Try not to lose it this time." or "You already have all your tabards.")
end

local function openMenu(p)
  if IsBot(p) then return end
  if not questDone(p) then say(p, lessonMsg("Patience, Grasshopper. First, my little lesson.")); return end
  cooldownNotice(p)
  say(p, WISDOM[math.random(#WISDOM)])
  if (FamRN and FamRN.test()) and FamVrilUI and FamVrilUI.HasAddon and FamVrilUI.HasAddon(p) then   -- release-next (test realm): Whiz/Tome "Vril Path" opens the panel
    pcall(function() p:GossipComplete() end)
    FamVrilUI.Open(p, "paths")
    return
  end
  showMain(p)
end

------------------------------------------------------------------ Whiz menu bridge (16.2.1): the C++ menu
local function toWhizMenu(p)
  if p:IsInCombat() then info(p, "Finish your fight first!"); return end
  p:CastSpell(p, SPELL_WHIZ_MENU, true)   -- dummy: WhizMenu.cpp's OnSpellCast opens the menu
end

local function OnSelect(event, p, obj, sender, intid, code, menu_id)
  if IsBot(p) then p:GossipComplete(); return end
  if intid == 1 then return showMain(p) end
  if intid >= 100 and intid < 200 then return showBrowse(p, intid - 100) end
  if intid == 4 then return showInfo(p) end
  if intid == 5 then return showCollection(p) end
  if intid == 7 then lostTabards(p); return showCollection(p) end
  if intid == 8 then toWhizMenu(p); return p:GossipComplete() end
  if intid == 9 then if FamLegendaryArmory then return FamLegendaryArmory.Open(p) end return p:GossipComplete() end   -- Legendary Armory
  if intid == 10 then   -- FamVril panel (32_vril_ui.lua)
    p:GossipComplete()
    if FamVrilUI and FamVrilUI.Open then FamVrilUI.Open(p, "paths") end
    return
  end
  if intid == 6 then
    info(p, "You can change your Vril Path again in " .. minutesLeft(cooldownLeft(p)) .. ". Go have an adventure!")
    return p:GossipComplete()
  end
  if intid >= 1000 and intid < 2000 then return showPath(p, intid - 1000) end
  if intid == 3 or (intid >= 2000 and intid < 3000) then
    if p:IsInCombat() then info(p, "Finish your fight first!"); return p:GossipComplete() end
    local left, row = cooldownLeft(p), getRow(gl(p))
    if left > 0 and row then
      info(p, "You can change your Vril Path again in " .. minutesLeft(left) .. ". Go have an adventure!")
      return p:GossipComplete()
    end
    if intid == 3 then
      if row then resetPath(p, row); touchCooldown(gl(p)); info(p, "Your Vril Path is gone. Pick a new one any time!") end
      return p:GossipComplete()
    end
    setPath(p, intid - 2000)
    return p:GossipComplete()
  end
  p:GossipComplete()
end
RegisterPlayerGossipEvent(MENU, 2, OnSelect)

------------------------------------------------------------------ Raise Ally after-effect (2f.3)
local raised = {}   -- [guidLow] = time of the Raise Ally cast
-- FamilyLAN fix 2026-10-21: ALE pushes (event, player, spell, skipCheck), but under load the
-- hook has (rarely) arrived with an extra argument in front, so `spell` held the Player
-- ("GetEntry on bad self: Spell expected, got Player", 21 Oct 16:18 MT). Find the Spell by
-- type and take the Player pushed right before it; skip the cast if either is missing.
local function aleType(v)
  if type(v) ~= "userdata" then return nil end
  local ok, t = pcall(function() return v:GetObjectType() end)
  return ok and t or nil
end
local function OnSpellCast(event, ...)
  local n, args = select("#", ...), {...}
  local p, spell
  for i = 1, n do
    if aleType(args[i]) == "Spell" then
      spell = args[i]
      if i > 1 and aleType(args[i - 1]) == "Player" then p = args[i - 1] end
      break
    end
  end
  if not spell or not p then return end
  local id = spell:GetEntry()  if id == SPELL_TRAIN then
    openMenu(p)
  elseif RAISE_ALLY[id] then
    local t = spell:GetTarget()
    local tp = t and t.ToPlayer and t:ToPlayer()
    if tp then raised[tp:GetGUIDLow()] = now()
    elseif t and t.GetOwnerGUID then raised[GetGUIDLow(t:GetOwnerGUID())] = now() end   -- target was the corpse
  end
end
RegisterPlayerEvent(5, OnSpellCast)
RegisterPlayerEvent(35, function(event, p) raised[gl(p)] = nil end)            -- REPOP: released spirit
RegisterPlayerEvent(36, function(event, p)                                      -- RESURRECT
  local t = raised[gl(p)]
  if t and now() - t <= 60 then
    raised[gl(p)] = nil
    if not p:InArena() then p:CastSpell(p, SPELL_FRENZY, true) end
  end
end)

------------------------------------------------------------------ quest: stillness + silence (3.2b)
local still = {}          -- [guid] = { x,y,z,o,hp, count, ev }
local bananaYellUntil = {}

local function stillMsg(p, kind)
  local M = {
    moved  = "A leaf that flutters cannot hear the wind. Again, from the beginning!",
    turned = "Even your nose must be patient! Start again.",
    jumped = "Hopping is for frogs, young grasshopper. Again!",
    spoke  = "Shhh! Silence is the loudest lesson. Start again.",
    combat = "Even a master can't meditate while being bitten! Deal with it, then begin again.",
  }
  say(p, M[kind])
end

local function questOpen(p) return p:HasQuest(QUEST) and p:GetQuestStatus(QUEST) == QUEST_STATUS_INCOMPLETE end

local function resetStill(p, kind)
  local s = still[gl(p)]
  if not s then return end
  if s.count > 0 and kind then stillMsg(p, kind) end
  s.count = 0
end

local function snapshot(p, s)
  s.x, s.y, s.z, s.o, s.hp = p:GetX(), p:GetY(), p:GetZ(), p:GetO(), p:GetHealth()
end

local function stillTick(eventId, delay, repeats, p)
  local s = still[gl(p)]
  if not s or not questOpen(p) then p:RemoveEventById(eventId); still[gl(p)] = nil; return end
  if p:IsDead() then s.count = 0; snapshot(p, s); return end
  local x, y, z, o, hp = p:GetX(), p:GetY(), p:GetZ(), p:GetO(), p:GetHealth()
  local dxy = math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2)
  local dz = math.abs(z - s.z)
  local dO = math.abs(o - s.o); if dO > math.pi then dO = 2 * math.pi - dO end
  local kind
  if p:IsInCombat() or hp < s.hp then kind = "combat"
  elseif dxy > 0.05 then kind = "moved"
  elseif dz > 0.05 then kind = "jumped"
  elseif dO > 0.02 then kind = "turned"
  elseif p:IsMounted() or p:IsFalling() then kind = "moved" end
  snapshot(p, s)
  if kind then resetStill(p, kind); return end
  s.count = s.count + 1
  if s.count == 60 then say(p, "One minute of stillness... your patience grows.")
  elseif s.count == 120 then say(p, "Two minutes... the pebble is almost yours.")
  elseif s.count >= STILL_SECONDS then
    p:AreaExploredOrEventHappens(QUEST)
    say(p, "The pebble is yours. Come back to me.")
    still[gl(p)] = nil
    p:RemoveEventById(eventId)
  end
end

local function startStill(p, announce)
  if IsBot(p) or not questOpen(p) then return end
  local old = still[gl(p)]
  if old and old.ev then p:RemoveEventById(old.ev) end
  local s = { count = 0 }
  snapshot(p, s)
  still[gl(p)] = s
  s.ev = p:RegisterEvent(stillTick, 1000, 0)
  if announce then say(p, "Stillness, Grasshopper. Three minutes. Not a step, not a word.") end
end

local function onTalk(event, p)
  local g = gl(p)
  if still[g] and not (bananaYellUntil[g] and now() <= bananaYellUntil[g]) then resetStill(p, "spoke") end
  -- no return value on purpose: never changes or blocks the chat (11_ogre_caveman_talk.lua stays in charge)
end
for _, ev in ipairs({18, 19, 20, 21, 22, 24}) do RegisterPlayerEvent(ev, onTalk) end

RegisterPlayerEvent(63, function(event, p, quest)        -- QUEST_ACCEPT
  if quest:GetId() ~= QUEST then return end
  if IsBot(p) then p:RemoveQuest(QUEST); return end
  startStill(p, true)
end)

RegisterPlayerEvent(54, function(event, p, quest)        -- COMPLETE_QUEST (turn-in, verified in README)
  if quest:GetId() ~= QUEST or IsBot(p) then return end
  for _, c in ipairs(p:GetCreaturesInRange(30, MEDIVH_ENTRY) or {}) do
    if c:GetOwnerGUID() == p:GetGUID() then c:SendUnitSay("You have snatched the pebble from my hand, Grasshopper.", 0); break end
  end
  -- 16.9.2: the Tome is no longer the reward (the Whiz menu replaces it); the turn-in just whispers.
  say(p, "Every page of my magic is open to you now, Grasshopper. Talk to me!")
  if p:HasItem(BANANA, 1, true) then p:RemoveItem(BANANA, 1) end   -- safety net (quest ItemDrop1 already removes it)
  still[gl(p)] = nil
end)
RegisterPlayerEvent(38, function(event, p, questId)      -- QUEST_ABANDON: stop the timer
  if questId == QUEST then still[gl(p)] = nil end
end)

------------------------------------------------------------------ Space Banana (3.2b)
local naked = {}   -- [guid] = { saved field values } while the look is active
local function restoreLook(p)
  local saved = naked[gl(p)]
  if not saved then return end
  for i = 0, 18 do
    local f = PLAYER_VISIBLE_ITEM_1_ENTRYID + i * 2
    if p:GetUInt32Value(f) == 0 then p:SetUInt32Value(f, saved[i]) end
  end
  naked[gl(p)] = nil
end

RegisterItemEvent(BANANA, 2, function(event, p, item, target)
  if p:IsInCombat() or p:InBattleground() or p:InArena() then
    info(p, WHIZ .. "'s banana only works when you're not in a fight.")
    return false
  end
  if p:GetDisplayId() ~= p:GetNativeDisplayId() then    -- Shapeshifter form, Hex, shapeshift... (plan 17.5)
    info(p, "Change back first!")
    return false
  end
  local g = gl(p)
  bananaYellUntil[g] = now() + 2
  p:SendUnitYell("I AM THE FIRST MONKEY SHOT INTO SPACE!", 0)
  if not naked[g] then
    local saved = {}
    for i = 0, 18 do
      local f = PLAYER_VISIBLE_ITEM_1_ENTRYID + i * 2
      saved[i] = p:GetUInt32Value(f); p:SetUInt32Value(f, 0)
    end
    naked[g] = saved
    p:RegisterEvent(function(eid, d, r, pl)
      if pl:GetDisplayId() ~= pl:GetNativeDisplayId() then return end   -- transformed: wait, never re-show gear over a form
      if not pl:HasAura(SPELL_MONKEY) then restoreLook(pl); pl:RemoveEventById(eid) end
    end, 1000, 0)
  end
end)

------------------------------------------------------------------ login / level / logout
-- 16.9.3: existing characters (level 10+, quest 6010300 rewarded, not GM) get the one-time
-- "I've learned new tricks!..." whisper on their first login after the feature is live.
-- Marker: familylan_whiz_intro (acore_characters, Lua-managed; created above).
local function whizIntroNotice(p)
  if not questDone(p) or isGM(p) then return end
  local guid = gl(p)
  if CharDBQuery("SELECT 1 FROM familylan_whiz_intro WHERE guid=" .. guid) then return end
  say(p, "I've learned new tricks! Talk to me for a lesson in patience, and every page of my magic opens.")
  CharDBExecute(string.format("REPLACE INTO familylan_whiz_intro (guid) VALUES (%d)", guid))
end

RegisterPlayerEvent(3, function(event, p)                -- LOGIN
  if IsBot(p) then return end
  p:RegisterEvent(function(eid, d, r, pl)
    pl:RemoveAura(SPELL_MONKEY)
    resync(pl)
    cooldownNotice(pl)
    whizIntroNotice(pl)
    if questOpen(pl) then startStill(pl, true) end
  end, 3000, 1)
end)
RegisterPlayerEvent(13, function(event, p, oldLevel)     -- LEVEL_CHANGE
  if IsBot(p) then return end
  resync(p, true)
end)
RegisterPlayerEvent(4, function(event, p)                -- LOGOUT
  local g = gl(p); still[g] = nil; naked[g] = nil; bananaYellUntil[g] = nil; raised[g] = nil
end)

------------------------------------------------------------------ commands: .vrilpath (P9), GM .subclass
RegisterPlayerEvent(42, function(event, p, command)
  local cmd = command:lower()
  if cmd == "vrilpath" then
    if IsBot(p) then return false end
    info(p, describe(p)); return false
  end
  local a, b, c, d = cmd:match("^subclass%s*(%S*)%s*(%S*)%s*(%S*)%s*(%S*)")
  if a == nil then return end
  if not isGM(p) then return end
  local target = (b ~= "" and GetPlayerByName(b:sub(1,1):upper() .. b:sub(2))) or p:GetSelection() and p:GetSelection():ToPlayer() or p
  if a == "info" then info(p, target:GetName() .. ": " .. describe(target))
  elseif a == "reset" then resetPath(target); info(p, "Reset " .. target:GetName() .. ".")
  elseif a == "cdreset" then CharDBExecute("UPDATE familylan_subclass_grants SET last_change=NULL WHERE guid=" .. gl(target)); info(p, "Cooldown cleared for " .. target:GetName() .. ".")
  elseif a == "set" then
    local want
    for id = 0, 30 do if PATHS[id].name:lower():gsub(" ", "") == c:gsub(" ", "") then want = id end end
    if not want then info(p, "Unknown Vril Path: " .. c); return false end
    local ok, why = canPick(target, want)
    if not ok then
      PrintError("[VrilPath] GM " .. p:GetName() .. " tried a blocked SET: " .. target:GetName() .. " -> " .. PATHS[want].name)
      info(p, why .. (d == "force" and " (forced anyway)" or " Add 'force' to override."))
      if d ~= "force" then return false end
    end
    setPath(target, want, { force = (d == "force"), noCooldown = true })
    info(p, "Set " .. target:GetName() .. " to " .. PATHS[want].name .. ".")
  else info(p, ".subclass info|set <name> <path> [force]|reset|cdreset [name]") end
  return false
end)

------------------------------------------------------------------ FamVril panel API (2026-10-27, additive)
-- Used by 32_vril_ui.lua (the FamVril addon's server half). Same rules as the Whiz gossip above: the panel only
-- DISPLAYS and REQUESTS; every check (class, quest, combat, cooldown) runs here. Nothing above this line changed.
FamVrilPaths = {
  PATHS = PATHS, AVATAR = AVATAR, RECOMMENDED = RECOMMENDED, BLOCKED = BLOCKED, CLASS_NAME = CLASS_NAME,
  CLASS_PLURAL = CLASS_PLURAL, COOLDOWN = COOLDOWN, ENABLED_FORMS = ENABLED_FORMS,
  FORM30_BASE = FORM30_BASE, FORM50_BASE = FORM50_BASE, ULT1_BASE = ULT1_BASE, ULT2_BASE = ULT2_BASE,
  IsBot = IsBot, isGM = isGM, getRow = getRow, cooldownLeft = cooldownLeft, canPick = canPick, spellFor = spellFor,
  avatarSpellFor = avatarSpellFor, avatarReady = avatarReady, questDone = questDone, hasReward = hasReward,
  visiblePaths = visiblePaths, scaled = scaled, minutesLeft = minutesLeft, powerOf = powerOf,
}
function FamVrilPaths.choose(p, id)       -- same checks as the "Choose <path>!" gossip item (intid 2000+id)
  if IsBot(p) then return false, "Bots can't pick a Vril Path." end
  id = tonumber(id)
  if not id or not PATHS[id] then return false, "That Vril Path doesn't exist." end
  if not questDone(p) then return false, lessonMsg("Patience, Grasshopper. Finish Whiz's little lesson first!") end
  if p:IsInCombat() then return false, "Finish your fight first!" end
  local row, left = getRow(gl(p)), cooldownLeft(p)
  if row and row.id == id then return false, "That is already your Vril Path!" end
  if left > 0 and row then return false, "You can change your Vril Path again in " .. minutesLeft(left) .. ". Go have an adventure!" end
  local ok, why = canPick(p, id)
  if not ok then return false, why end
  if not setPath(p, id) then return false, "That didn't work. Try again!" end
  pcall(function() p:LearnSpell(706500) end)
  return true, "You are now a Junior " .. PATHS[id].name .. "!"
end
function FamVrilPaths.remove(p)           -- same checks as "Remove my Vril Path" (intid 3)
  if IsBot(p) then return false, "Bots can't change a Vril Path." end
  if not questDone(p) then return false, lessonMsg("Patience, Grasshopper. Finish Whiz's little lesson first!") end
  if p:IsInCombat() then return false, "Finish your fight first!" end
  local row, left = getRow(gl(p)), cooldownLeft(p)
  if not row then return false, "You don't have a Vril Path to remove." end
  if left > 0 then return false, "You can change your Vril Path again in " .. minutesLeft(left) .. ". Go have an adventure!" end
  resetPath(p, row); touchCooldown(gl(p))
  pcall(function() p:RemoveSpell(706500, false, false) end)
  return true, "Your Vril Path is gone. Pick a new one any time!"
end

PrintInfo("[Subclass] Vril Path " .. VP_VERSION .. " loaded " .. (function() local n=0 for i=0,30 do if PATHS[i].enabled then n=n+1 end end return n end)() .. " subclass"
  .. (ENABLED_FORMS and " (Phase 4 Vril Forms ON)" or " (Phase 4 Vril Forms OFF)"))
