#include <amxmodx>
#include <reapi>
#include <json>
#include <hamsandwich>
#include <VipM/ItemsController>

// #define SOUND

#define MAP_NAME_MAX_LEN 32
#define PLUGIN_NAME_MAX_LEN 64

enum _:S_WarmupMode {
	WM_Title[64],
	// TODO: WM_Duration, // Разная длительность у разных режимов
	Array:WM_Items,
}

enum E_Cvars {
	Cvar_Duration,
	Cvar_RestartsNum,
	Float:Cvar_RestartInterval,
	bool:Cvar_DisableStats,
	bool:Cvar_CleanupMap,
	bool:Cvar_WeaponsPickupBlock,
	
	bool:Cvar_DeathMatch_Enable,
	Cvar_DeathMatch_SpawnProtectionDuration,
}
new g_Cvars[E_Cvars];
#define Cvar(%1) g_Cvars[Cvar_%1]

#define Lang(%1) fmt("%l", %1)

#if defined SOUND
// TODO: Вынести в JSON файл
new const soundRR[][] =	// Указывать звук, например 1.mp3
{	
	"sound/rww/RoundStart.mp3",
//	"sound/rww/2.mp3",
//	"sound/rww/3.mp3"
}
#endif

new HookChain:fwd_RRound;
new g_iRound;

new HamHook:fwd_Equip,
	HamHook:fwd_WpnStrip,
	HamHook:fwd_Entity;

new HookChain:fwd_NewRound,
	HookChain:fwd_BlockEntity,
	HookChain:fwd_Spawn,
	HookChain:fwd_GiveC4;

new g_iHud_Stats, g_iHud_Timer;
new g_iCvar_ImmunutyTime, g_iCvar_ForceRespawn;

new Array:g_aDisablePlugins = Invalid_Array;

new bool:g_bWarupInProgress = false;
new Array:g_aModes = Invalid_Array;

new g_SelectedMode[S_WarmupMode];

new fwOnStarted;
new fwOnFinished;

public plugin_init() {
	register_plugin("Random Weapons WarmUP", "3.0.0", "neugomon/h1k3/ArKaNeMaN");
	register_dictionary("rww.ini");

	if (IsMapIgnored()) {
		log_amx("[INFO] WarmUP disabled on this map.");
		pause("ad");
		return;
	}

	DisablePluginsLoad();
	WarmupModesLoad();
	RegisterCvars();
	
	fwOnStarted = CreateMultiForward("RWW_OnStarted", ET_IGNORE);
	fwOnFinished = CreateMultiForward("RWW_OnFinished", ET_IGNORE);

	RegisterHookChain(RG_RoundEnd, "fwdRoundEnd", true);
	DisableHookChain(fwd_NewRound = RegisterHookChain(RG_CSGameRules_CheckMapConditions, "fwdRoundStart", true));
	DisableHookChain(fwd_Spawn = RegisterHookChain(RG_CBasePlayer_Spawn, "fwdPlayerSpawnPost", true));
	DisableHookChain(fwd_GiveC4 = RegisterHookChain(RG_CSGameRules_GiveC4, "fwdGiveC4", false));
	DisableHookChain(fwd_BlockEntity = RegisterHookChain(RG_CBasePlayer_HasRestrictItem, "fwdHasRestrictItemPre", false));
	EnableHookChain(fwd_RRound = RegisterHookChain(RG_CSGameRules_RestartRound, "fwdRestartRound_Pre"));

	DisableHamForward(fwd_Equip = RegisterHam(Ham_Use, "game_player_equip", "CGamePlayerEquip_Use", false));
	DisableHamForward(fwd_WpnStrip = RegisterHam(Ham_Use, "player_weaponstrip", "CStripWeapons_Use", false));
	DisableHamForward(fwd_Entity = RegisterHam(Ham_CS_Restart, "armoury_entity", "CArmoury_Restart", false));

	register_clcmd("drop", "ClCmd_Drop");

	g_iCvar_ImmunutyTime = get_cvar_pointer("mp_respawn_immunitytime");
	g_iCvar_ForceRespawn  = get_cvar_pointer("mp_forcerespawn");

	g_iHud_Stats = CreateHudSyncObj();
	g_iHud_Timer = CreateHudSyncObj();

	g_bWarupInProgress = false;
}

public plugin_end() {
	if (g_bWarupInProgress) {
		finishWurmUp();
	}
}


public fwdHasRestrictItemPre() {
	SetHookChainReturn(ATYPE_INTEGER, true);
	return HC_SUPERCEDE;
}

public ClCmd_Drop() {
	return (g_bWarupInProgress && Cvar(WeaponsPickupBlock))
		? PLUGIN_HANDLED
		: PLUGIN_CONTINUE;
}

#if defined SOUND
public plugin_precache() {
	for (new i = 0; i < sizeof(soundRR); i++) {
		precache_generic(soundRR[i]);
	}
}
#endif

public fwdRoundEnd(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay) {
	if (event == ROUND_GAME_COMMENCE) {
		EnableHookChain(fwd_NewRound);
		ExecuteForward(fwOnStarted);
	}
}

public fwdRoundStart() {
	g_bWarupInProgress = true;

	if (Cvar(CleanupMap)) {
		EnableHamForward(fwd_Equip);
		EnableHamForward(fwd_WpnStrip);
		EnableHamForward(fwd_Entity);
	}

	DisableHookChain(fwd_NewRound);
	EnableHookChain(fwd_Spawn);
	EnableHookChain(fwd_GiveC4);

	set_pcvar_num(g_iCvar_ForceRespawn, Cvar(DeathMatch_Enable));
	set_pcvar_num(g_iCvar_ImmunutyTime, Cvar(DeathMatch_SpawnProtectionDuration));

	if (Cvar(DeathMatch_Enable)) {
		set_cvar_num("mp_round_infinite", 1);
		set_task(1.0, "Show_Timer", .flags = "a", .repeat = Cvar(Duration));
	} else {
		set_task(1.0, "Hud_Message", .flags = "a", .repeat = 25 );
	}

	#if defined SOUND
	static cmd[64];
	formatex(cmd, 63, "mp3 play ^"%s^"", soundRR[random(sizeof(soundRR))]);
	client_cmd(0, "%s", cmd);
	#endif

	if (Cvar(DisableStats)) {
		set_cvar_num("csstats_pause", 1);
	}

	if (Cvar(WeaponsPickupBlock)) {
		EnableHookChain(fwd_BlockEntity);
	}

	PluginController(true);

	new iRnd = random_num(0, ArraySize(g_aModes) - 1);
	ArrayGetArray(g_aModes, iRnd, g_SelectedMode);
}

public fwdPlayerSpawnPost(const id) {
	if (!is_user_alive(id)) {
		return;
	}

	if (Cvar(CleanupMap)) {
		InvisibilityArmourys();
	}

	BuyZone_ToogleSolid(SOLID_NOT);
	rg_remove_all_items(id);
	set_member_game(m_bMapHasBuyZone, true);

	// А надо ли выдавать нож, если это явно не указано в кфг?
	rg_give_item(id, "weapon_knife");

	VipM_IC_GiveItems(id, g_SelectedMode[WM_Items]);
}

public fwdGiveC4() {
	return HC_SUPERCEDE;
}

public Show_Timer() {
	static timer = -1;

	if (timer < 0) {
		timer = Cvar(Duration);
	}

	if (--timer == 0) {
		finishWurmUp();
		timer = -1;
		return;
	}

	if (Cvar(DisableStats)) {
		set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 0.9, .channel = -1);
		ShowSyncHudMsg(0, g_iHud_Stats, "%l", "RWW_HUD_STATS_OFF");
	}
	
	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHud_Timer, "%l", "RWW_HUD_DM_TIMER", g_SelectedMode[WM_Title], timer);
}

public fwdRestartRound_Pre() {
	g_iRound++;

	if (g_iRound >= 2) {
		DisableHookChain(fwd_RRound);
		finishWurmUp();
	}
}

public Hud_Message() {
	if (Cvar(DisableStats)) {
		set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 0.9, .channel = -1);
		ShowSyncHudMsg(0, g_iHud_Stats, "%l", "RWW_HUD_STATS_OFF");
	}

	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHud_Timer, "%l", "RWW_HUD_NOT_DM", g_SelectedMode[WM_Title]);
}

public CArmoury_Restart(const pArmoury) {
	return HAM_SUPERCEDE;
}

public CGamePlayerEquip_Use() {
	return HAM_SUPERCEDE;
}

public CStripWeapons_Use() {
	return HAM_SUPERCEDE;
}

InvisibilityArmourys() {
	new pArmoury = NULLENT
	while ((pArmoury = rg_find_ent_by_class(pArmoury, "armoury_entity"))) {
		if (get_member(pArmoury, m_Armoury_iCount) > 0) {
			set_entvar(pArmoury, var_effects, get_entvar(pArmoury, var_effects) | EF_NODRAW)
			set_entvar(pArmoury, var_solid, SOLID_NOT)
			set_member(pArmoury, m_Armoury_iCount, 0)
		}
	}
}

finishWurmUp() {
	g_bWarupInProgress = false;

	BuyZone_ToogleSolid(SOLID_TRIGGER);

	if (Cvar(CleanupMap)) {
		DisableHamForward(fwd_Equip);
		DisableHamForward(fwd_WpnStrip);
		DisableHamForward(fwd_Entity);
	}

	DisableHookChain(fwd_Spawn);
	DisableHookChain(fwd_GiveC4);

	set_cvar_num("mp_forcerespawn", 0);
	set_cvar_num("mp_respawn_immunitytime", 0);
	set_cvar_num("mp_round_infinite", 0);

	if (Cvar(DisableStats)) {
		set_cvar_num("csstats_pause", 0);
	}

	if (Cvar(WeaponsPickupBlock)) {
		DisableHookChain(fwd_BlockEntity);
	}

	PluginController(false);
	
	ExecuteForward(fwOnFinished);

	@Task_Restart();
	if (Cvar(RestartsNum) > 1) {
		set_task(Cvar(RestartInterval), "@Task_Restart", .flags = "a", .repeat = Cvar(RestartsNum) - 1);
	}
	set_task(Cvar(RestartInterval) * float(Cvar(RestartsNum) - 1), "@Task_WarmupEnd");
}

@Task_Restart() {
	set_member_game(m_bCompleteReset, true);
	rg_restart_round();
}

@Task_WarmupEnd() {
	if (Cvar(DisableStats)) {
		set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 5.0, .channel = -1);
		ShowSyncHudMsg(0, g_iHud_Stats, "%l", "RWW_HUD_STATS_ON");
	}

	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 5.0, .channel = -1);
	ShowSyncHudMsg(0, g_iHud_Timer, "%l", "RWW_HUD_WARMUP_END");
}

PluginController(const bool:bState) {
	if (g_aDisablePlugins == Invalid_Array) {
		return;
	}

	new sPluginName[PLUGIN_NAME_MAX_LEN];
	for (new i; i < ArraySize(g_aDisablePlugins); i++) {
		ArrayGetString(g_aDisablePlugins, i, sPluginName, charsmax(sPluginName));

		if (bState) {
			pause("ac", sPluginName);
		} else {
			unpause("ac", sPluginName);
		}
	}	
}

WarmupModesLoad() {
	g_aModes = ArrayCreate(S_WarmupMode, 4);

	new JSON:jModes = Json_GetFile(GetConfigPath("Modes.json"));

	if (jModes == Invalid_JSON) {
		set_fail_state("Can't load warmup modes from config file.");
		return;
	}

	if (!json_is_array(jModes)) {
		log_amx("[ERROR] File '%s' must contains array of warmup modes.", GetConfigPath("Modes.json"));
		set_fail_state("Can't load warmup modes from config file.");
		json_free(jModes);
		return;
	}
	
	for (new i = 0, ii = json_array_get_count(jModes); i < ii; i++) {
		new Mode[S_WarmupMode];
		
		new JSON:jMode = json_array_get_value(jModes, i);

		if (!json_is_object(jMode)) {
			log_amx("[WARNING] Warmup mode must be object. File '%s', item #%d", GetConfigPath("Modes.json"), i);
			json_free(jMode);
			continue;
		}

		json_object_get_string(jMode, "Title", Mode[WM_Title], charsmax(Mode[WM_Title]));
		Mode[WM_Items] = VipM_IC_JsonGetItems(json_object_get_value(jMode, "Items"));

		if (Mode[WM_Items] == Invalid_Array) {
			log_amx("[WARNING] Warmup items array is empty. File '%s', item #%d", GetConfigPath("Modes.json"), i);
			json_free(jMode);
			continue;
		}

		json_free(jMode);

		ArrayPushArray(g_aModes, Mode);
	}
	
	json_free(jModes);
}

DisablePluginsLoad() {
	g_aDisablePlugins = ArrayCreate(PLUGIN_NAME_MAX_LEN, 4);

	new JSON:jDisablePlugins = Json_GetFile(GetConfigPath("DisablePlugins.json"));

	if (jDisablePlugins == Invalid_JSON) {
		log_amx("[WARNING] Disabling plugins will be skipped.");
		return;
	}

	if (!json_is_array(jDisablePlugins)) {
		log_amx("[ERROR] File '%s' must contains array of plugin names.", GetConfigPath("DisablePlugins.json"));
		log_amx("[WARNING] Disabling plugins will be skipped.");
		json_free(jDisablePlugins);
		return;
	}
	
	new sPluginName[PLUGIN_NAME_MAX_LEN];
	for (new i = 0, ii = json_array_get_count(jDisablePlugins); i < ii; i++) {
		json_array_get_string(jDisablePlugins, i, sPluginName, charsmax(sPluginName));

		if (!is_plugin_loaded(sPluginName)) {
			log_amx("[WARNING] Plugin '%s' is not loaded.", sPluginName);
			continue;
		}

		ArrayPushString(g_aDisablePlugins, sPluginName);
	}
	
	json_free(jDisablePlugins);
}

bool:IsMapIgnored() {
	new JSON:jIgnoredMaps = Json_GetFile(GetConfigPath("IgnoredMaps.json"));

	if (jIgnoredMaps == Invalid_JSON) {
		log_amx("[WARNING] Check for ignored maps will be skipped.");
		return false;
	}

	if (!json_is_array(jIgnoredMaps)) {
		log_amx("[ERROR] File '%s' must contains array of map names.", GetConfigPath("IgnoredMaps.json"));
		log_amx("[WARNING] Check for ignored maps will be skipped.");
		json_free(jIgnoredMaps);
		return false;
	}

	new sMapName[MAP_NAME_MAX_LEN];
	rh_get_mapname(sMapName, charsmax(sMapName), MNT_TRUE);
	
	new sIgnoredMapName[MAP_NAME_MAX_LEN];
	for (new i = 0, ii = json_array_get_count(jIgnoredMaps); i < ii; i++) {
		json_array_get_string(jIgnoredMaps, i, sIgnoredMapName, charsmax(sIgnoredMapName));

		if (equali(sMapName, sIgnoredMapName, strlen(sIgnoredMapName))) {
			json_free(jIgnoredMaps);
			return true;
		}
	}

	json_free(jIgnoredMaps);
	return false;
}

BuyZone_ToogleSolid(const solid) {
	new entityIndex = 0;
	while ((entityIndex = rg_find_ent_by_class(entityIndex, "func_buyzone"))) {
		set_entvar(entityIndex, var_solid, solid);
	}
}

JSON:Json_GetFile(const sPath[]) {
	if (!file_exists(sPath)) {
		log_amx("[ERROR] File '%s' not found.", sPath);
		return Invalid_JSON;
	}

	new JSON:jFile = json_parse(sPath, true, true);

	if (jFile == Invalid_JSON) {
		log_amx("[ERROR] JSON syntax error in '%s'.", sPath);
		return Invalid_JSON;
	}

	return jFile;
}

GetConfigPath(const sPath[]) {
	static __amxx_configsdir[PLATFORM_MAX_PATH];
	if (!__amxx_configsdir[0]) {
		get_localinfo("amxx_configsdir", __amxx_configsdir, charsmax(__amxx_configsdir));
	}
	
	return fmt("%s/plugins/RWW/%s", __amxx_configsdir, sPath);
}

RegisterCvars() {
	bind_pcvar_num(create_cvar(
		"RWW_Duration", "40", FCVAR_NONE,
		Lang("RWW_CVAR_DURATION"),
		true, 1.0
	), Cvar(Duration));

	bind_pcvar_num(create_cvar(
		"RWW_RestartsNum", "2", FCVAR_NONE,
		Lang("RWW_CVAR_RESTARTS_NUM"),
		true, 1.0
	), Cvar(RestartsNum));

	bind_pcvar_float(create_cvar(
		"RWW_RestartInterval", "1.5", FCVAR_NONE,
		Lang("RWW_CVAR_RESTART_INTERVAL"),
		true, 1.0
	), Cvar(RestartInterval));

	bind_pcvar_num(create_cvar(
		"RWW_CleanupMap", "0", FCVAR_NONE,
		Lang("RWW_CVAR_CLEANUP_MAP"),
		true, 0.0, true, 1.0
	), Cvar(CleanupMap));

	bind_pcvar_num(create_cvar(
		"RWW_WeaponsPickupBlock", "0", FCVAR_NONE,
		Lang("RWW_CVAR_WEAPONS_PICKUP_BLOCK"),
		true, 0.0, true, 1.0
	), Cvar(WeaponsPickupBlock));

	bind_pcvar_num(create_cvar(
		"RWW_DisableStats", "0", FCVAR_NONE,
		Lang("RWW_CVAR_DISABLE_STATS"),
		true, 0.0, true, 1.0
	), Cvar(DisableStats));


	bind_pcvar_num(create_cvar(
		"RWW_DeathMatch_Enable", "1", FCVAR_NONE,
		Lang("RWW_CVAR_DM_ENABLE"),
		true, 0.0, true, 1.0
	), Cvar(DeathMatch_Enable));

	bind_pcvar_num(create_cvar(
		"RWW_DeathMatch_SpawnProtectionDuration", "2", FCVAR_NONE,
		Lang("RWW_CVAR_DM_SPAWN_PROTECTION_DURATION"),
		true, 0.0
	), Cvar(DeathMatch_SpawnProtectionDuration));

	AutoExecConfig(true, "Cvars", "RWW");
}
