#include <amxmodx>
#include <reapi>
#include <json>
#include <hamsandwich>
#include <VipM/ItemsController>

#define MAP_NAME_MAX_LEN 32
#define PLUGIN_NAME_MAX_LEN 64

enum (+= 100) {
	TASK_RESTARTS_AFTER_WARMUP,
	TASK_WARMUP_END,
	TASK_TIMER,
}

enum _:S_WarmupMode {
	WM_Title[64],
	// TODO: WM_Duration, // Разная длительность у разных режимов
	WM_Music[PLATFORM_MAX_PATH],
	// TODO: WM_Cvars[S_CvarData], // Переопределение кваров на время разминки
	Array:WM_Items,
}

enum E_Cvars {
	Cvar_Duration,
	Cvar_RestartsNum,
	Float:Cvar_RestartInterval,
	bool:Cvar_DisableStats,
	bool:Cvar_CleanupMap,
	bool:Cvar_WeaponsPickupBlock,
	bool:Cvar_OncePerMap,
	bool:Cvar_StartAfterSvRestart,
	
	bool:Cvar_DeathMatch_Enable,
	Cvar_DeathMatch_SpawnProtectionDuration,
}
new g_Cvars[E_Cvars];
#define Cvar(%1) g_Cvars[Cvar_%1]

#define Lang(%1) fmt("%l", %1)

new bool:g_bDebug = false;
new g_sDebugFilePath[PLATFORM_MAX_PATH];

new HookChain:fwd_RRound;

new HamHook:fwd_Equip,
	HamHook:fwd_WpnStrip,
	HamHook:fwd_Entity;

new HookChain:fwd_NewRound,
	HookChain:fwd_RoundEnd,
	HookChain:fwd_BlockEntity,
	HookChain:fwd_Spawn,
	HookChain:fwd_GiveC4;

new g_iHud_Stats, g_iHud_Timer;

new Array:g_aDisablePlugins = Invalid_Array;
new Array:g_aMusic = Invalid_Array;

new bool:g_bWarupInProgress = false;
new Array:g_aModes = Invalid_Array;

new g_SelectedMode[S_WarmupMode];

new fwOnStarted;
new fwOnFinished;

new g_iTimer = -1;

public plugin_precache() {
	register_plugin("Random Weapons WarmUP", "3.3.1", "neugomon/h1k3/ArKaNeMaN");
	register_dictionary("rww.ini");
	InitDebug();

	if (IsMapIgnored()) {
		log_amx("[INFO] WarmUP disabled on this map.");
		pause("ad");
		return;
	}

	VipM_IC_Init();

	DisablePluginsLoad();
	WarmupModesLoad();
	MusicLoad();
	RegisterCvars();
	
	fwOnStarted = CreateMultiForward("RWW_OnStarted", ET_IGNORE);
	fwOnFinished = CreateMultiForward("RWW_OnFinished", ET_IGNORE);

	EnableHookChain(fwd_RoundEnd = RegisterHookChain(RG_RoundEnd, "fwdRoundEnd", true));
	DisableHookChain(fwd_NewRound = RegisterHookChain(RG_CSGameRules_CheckMapConditions, "fwdRoundStart", false));
	DisableHookChain(fwd_Spawn = RegisterHookChain(RG_CBasePlayer_Spawn, "fwdPlayerSpawnPost", true));
	DisableHookChain(fwd_GiveC4 = RegisterHookChain(RG_CSGameRules_GiveC4, "fwdGiveC4", false));
	DisableHookChain(fwd_BlockEntity = RegisterHookChain(RG_CBasePlayer_HasRestrictItem, "fwdHasRestrictItemPre", false));
	DisableHookChain(fwd_RRound = RegisterHookChain(RG_CSGameRules_RestartRound, "fwdRestartRound_Pre"));

	DisableHamForward(fwd_Equip = RegisterHam(Ham_Use, "game_player_equip", "CGamePlayerEquip_Use", false));
	DisableHamForward(fwd_WpnStrip = RegisterHam(Ham_Use, "player_weaponstrip", "CStripWeapons_Use", false));
	DisableHamForward(fwd_Entity = RegisterHam(Ham_CS_Restart, "armoury_entity", "CArmoury_Restart", false));

	register_clcmd("drop", "ClCmd_Drop");

	g_iHud_Stats = CreateHudSyncObj();
	g_iHud_Timer = CreateHudSyncObj();

	g_bWarupInProgress = false;
}

public plugin_end() {
	if (g_bWarupInProgress) {
		finishWarmUp();
	}
}

public fwdHasRestrictItemPre() {
	SetHookChainReturn(ATYPE_BOOL, true);
	return HC_SUPERCEDE;
}

public ClCmd_Drop() {
	return (g_bWarupInProgress && Cvar(WeaponsPickupBlock))
		? PLUGIN_HANDLED
		: PLUGIN_CONTINUE;
}

public fwdRoundEnd(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay) {
	if (g_bWarupInProgress) {

		return;
	}

	static bool:bWasStarted;

	if (Cvar(OncePerMap) && bWasStarted) {
		return;
	}

	if (
		event == ROUND_GAME_COMMENCE
		|| (Cvar(StartAfterSvRestart) && event == ROUND_GAME_RESTART)
	) {
		ExecuteForward(fwOnStarted);
		bWasStarted = true;
		g_bWarupInProgress = true;

		// Выключаем, т.к. далее будет рестарт с commence
		// Чтобы оно не сработало ещё раз
		DisableHookChain(fwd_RoundEnd);

		// Включаем хук нового раунда, чтобы при рестарте строкой ниже началась разминка
		EnableHookChain(fwd_NewRound);

		RestartGame();
	}
}

public fwdRoundStart() {
	RemoveAllTasks();

	if (Cvar(CleanupMap)) {
		DebugLog("    *clean map*");
		EnableHamForward(fwd_Equip);
		EnableHamForward(fwd_WpnStrip);
		EnableHamForward(fwd_Entity);
	}

	// До следующей разминки оно нам не надо
	// Поэтому выключаем
	DisableHookChain(fwd_NewRound);

	EnableHookChain(fwd_RRound);
	EnableHookChain(fwd_Spawn);
	EnableHookChain(fwd_GiveC4);
	
	set_cvar_num("mp_forcerespawn", Cvar(DeathMatch_Enable));
	set_cvar_num("mp_respawn_immunitytime", Cvar(DeathMatch_SpawnProtectionDuration));

	if (Cvar(DeathMatch_Enable)) {
		set_cvar_num("mp_round_infinite", 1);

		g_iTimer = Cvar(Duration);
		set_task(1.0, "Show_Timer", TASK_TIMER, .flags = "a", .repeat = Cvar(Duration));
	} else {
		set_task(1.0, "Hud_Message", TASK_TIMER, .flags = "a", .repeat = 25 );
	}

	if (Cvar(DisableStats)) {
		set_cvar_num("csstats_pause", 1);
	}

	if (Cvar(WeaponsPickupBlock)) {
		EnableHookChain(fwd_BlockEntity);
	}

	PluginController(true);

	new rnd = random_num(0, ArraySize(g_aModes) - 1);
	ArrayGetArray(g_aModes, rnd, g_SelectedMode);
	DebugLog("    rnd = %d (%s)", rnd, g_SelectedMode[WM_Title]);

	PlayWarmupMusic();
}

PlayWarmupMusic() {
	if (g_SelectedMode[WM_Music][0]) {
		client_cmd(0, "mp3 play ^"%s^"", g_SelectedMode[WM_Music]);
	} else if (g_aMusic != Invalid_Array && ArraySize(g_aMusic)) {
		new sMusicPath[PLATFORM_MAX_PATH];
		ArrayGetString(g_aMusic, random_num(0, ArraySize(g_aMusic) - 1), sMusicPath, charsmax(sMusicPath));
		client_cmd(0, "mp3 play ^"%s^"", sMusicPath);
	}
}

public fwdPlayerSpawnPost(const id) {
	// DebugLog("fwdPlayerSpawnPost(%d(%n)) [begin]", id, id);
	
	if (!is_user_alive(id)) {
		// DebugLog("    *player is dead*");
		return;
	}

	if (Cvar(CleanupMap)) {
		// DebugLog("    *InvisibilityArmourys*");
		InvisibilityArmourys();
	}

	BuyZone_ToogleSolid(SOLID_NOT);
	rg_remove_all_items(id);
	set_member_game(m_bMapHasBuyZone, true);

	// А надо ли выдавать нож, если это явно не указано в кфг?
	rg_give_item(id, "weapon_knife");

	VipM_IC_GiveItems(id, g_SelectedMode[WM_Items]);
	
	// DebugLog("fwdPlayerSpawnPost(%d(%n)) [end]", id, id);
}

public fwdGiveC4() {
	// DebugLog("fwdGiveC4()");
	return HC_SUPERCEDE;
}

public Show_Timer() {
	DebugLog("Show_Timer() [begin]");

	if (--g_iTimer <= 0) {
		DebugLog("    *finishWarmUp (--g_iTimer == 0)*");
		finishWarmUp();
		
		DebugLog("Show_Timer() [end]");
		return;
	}
	DebugLog("    --g_iTimer = %d", g_iTimer);

	if (Cvar(DisableStats)) {
		DebugLog("    *show disable stats hud*");
		set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 0.9, .channel = -1);
		ShowSyncHudMsg(0, g_iHud_Stats, "%l", "RWW_HUD_STATS_OFF");
	}
	
	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHud_Timer, "%l", "RWW_HUD_DM_TIMER", g_SelectedMode[WM_Title], g_iTimer);
	
	DebugLog("Show_Timer() [end]");
}

public fwdRestartRound_Pre() {
	DebugLog("fwdRestartRound_Pre()");
	finishWarmUp();
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
	new pArmoury = NULLENT;
	while ((pArmoury = rg_find_ent_by_class(pArmoury, "armoury_entity"))) {
		if (get_member(pArmoury, m_Armoury_iCount) > 0) {
			set_entvar(pArmoury, var_effects, get_entvar(pArmoury, var_effects) | EF_NODRAW);
			set_entvar(pArmoury, var_solid, SOLID_NOT);
			set_member(pArmoury, m_Armoury_iCount, 0);
		}
	}
}

finishWarmUp() {
	g_bWarupInProgress = false;
	RemoveAllTasks();

	BuyZone_ToogleSolid(SOLID_TRIGGER);
	if (Cvar(CleanupMap)) {
		DisableHamForward(fwd_Equip);
		DisableHamForward(fwd_WpnStrip);
		DisableHamForward(fwd_Entity);
	}

	DisableHookChain(fwd_Spawn);
	DisableHookChain(fwd_GiveC4);
	DisableHookChain(fwd_RRound);

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
		set_task(Cvar(RestartInterval), "@Task_Restart", TASK_RESTARTS_AFTER_WARMUP, .flags = "a", .repeat = Cvar(RestartsNum) - 1);
	}
	set_task(Cvar(RestartInterval) * float(Cvar(RestartsNum) - 1) + 0.1, "@Task_WarmupEnd", TASK_WARMUP_END);
}

RemoveAllTasks() {
	remove_task(TASK_RESTARTS_AFTER_WARMUP);
	remove_task(TASK_WARMUP_END);
	remove_task(TASK_TIMER);
}

@Task_Restart() {
	DebugLog("Task_Restart()");
	RestartGame();
}

@Task_WarmupEnd() {
	DebugLog("Task_WarmupEnd()");
	DebugLog("    Cvar(DisableStats) = %s", Cvar(DisableStats) ? "true" : "false");

	if (Cvar(DisableStats)) {
		set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 5.0, .channel = -1);
		ShowSyncHudMsg(0, g_iHud_Stats, "%l", "RWW_HUD_STATS_ON");
	}

	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 5.0, .channel = -1);
	ShowSyncHudMsg(0, g_iHud_Timer, "%l", "RWW_HUD_WARMUP_END");
	
	// После всех рестартов включаем обратно хук RoundEnd
	// Чтобы можно было ловить следующий commence
	EnableHookChain(fwd_RoundEnd);
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
	new const MODES_FILE_PATH[] = "Modes.json";

	g_aModes = ArrayCreate(S_WarmupMode, 4);

	new JSON:jModes = Json_GetFile(GetConfigPath(MODES_FILE_PATH));

	if (jModes == Invalid_JSON) {
		set_fail_state("Can't load warmup modes from config file.");
		return;
	}

	if (!json_is_array(jModes)) {
		log_amx("[ERROR] File '%s' must contains array of warmup modes.", GetConfigPath(MODES_FILE_PATH));
		set_fail_state("Can't load warmup modes from config file.");
		json_free(jModes);
		return;
	}
	
	for (new i = 0, ii = json_array_get_count(jModes); i < ii; i++) {
		new Mode[S_WarmupMode];
		
		new JSON:jMode = json_array_get_value(jModes, i);
		if (!json_is_object(jMode)) {
			log_amx("[WARNING] Warmup mode must be object. File '%s', item #%d.", GetConfigPath(MODES_FILE_PATH), i);
			json_free(jMode);
			continue;
		}

		json_object_get_string(jMode, "Title", Mode[WM_Title], charsmax(Mode[WM_Title]));

		Mode[WM_Items] = VipM_IC_JsonGetItems(json_object_get_value(jMode, "Items"));
		if (Mode[WM_Items] == Invalid_Array) {
			log_amx("[WARNING] Warmup items array is empty. File '%s', item #%d.", GetConfigPath(MODES_FILE_PATH), i);
			json_free(jMode);
			continue;
		}

		if (json_object_has_value(jMode, "Music", JSONString)) {
			json_object_get_string(jMode, "Music", Mode[WM_Music], charsmax(Mode[WM_Music]));
			if (!file_exists(Mode[WM_Music])) {
				log_amx("[WARNING] Music file '%s' not found. File '%s', item #%d.", GetConfigPath(MODES_FILE_PATH), i);
				Mode[WM_Music][0] = 0;
			}
		} else {
			Mode[WM_Music][0] = 0;
		}

		json_free(jMode);

		ArrayPushArray(g_aModes, Mode);
	}
	
	json_free(jModes);
}

DisablePluginsLoad() {
	g_aDisablePlugins = ArrayCreate(PLUGIN_NAME_MAX_LEN, 4);

	new JSON:jDisablePlugins = Json_GetFile(GetConfigPath("DisablePlugins.json"), "[]");

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

MusicLoad() {
	new const MUSIC_FILE_PATH[] = "Music.json";
	g_aMusic = ArrayCreate(PLATFORM_MAX_PATH, 4);

	new JSON:jMusic = Json_GetFile(GetConfigPath(MUSIC_FILE_PATH), "[]");

	if (jMusic == Invalid_JSON) {
		log_amx("[WARNING] Can't load music for warm-up.");
		return;
	}

	if (!json_is_array(jMusic)) {
		log_amx("[ERROR] File '%s' must contains array of .mp3 file paths.", GetConfigPath(MUSIC_FILE_PATH));
		log_amx("[WARNING] Can't load music for warm-up.");
		json_free(jMusic);
		return;
	}
	
	new sMusicPath[PLUGIN_NAME_MAX_LEN];
	for (new i = 0, ii = json_array_get_count(jMusic); i < ii; i++) {
		json_array_get_string(jMusic, i, sMusicPath, charsmax(sMusicPath));

		if (!file_exists(sMusicPath)) {
			log_amx("[WARNING] Music file '%s' not found.", sMusicPath);
			continue;
		}

		precache_generic(sMusicPath);
		ArrayPushString(g_aMusic, sMusicPath);
	}
	
	json_free(jMusic);
}

bool:IsMapIgnored() {
	new JSON:jIgnoredMaps = Json_GetFile(GetConfigPath("IgnoredMaps.json"), "[]");

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

RestartGame() {
	set_member_game(m_bCompleteReset, true);
	set_member_game(m_bGameStarted, true);

	rg_round_end(
		.tmDelay = 0.0,
		.st = WINSTATUS_NONE,
		.event = ROUND_GAME_COMMENCE,
		.message = "",
		.sentence = "",
		.trigger = true
	);
	rg_restart_round();
}

JSON:Json_GetFile(const sPath[], const sDefaultContent[] = NULL_STRING) {
	if (!file_exists(sPath)) {
		if (!sDefaultContent[0]) {
			log_amx("[ERROR] File '%s' not found.", sPath);
			return Invalid_JSON;
		}

		write_file(sPath, sDefaultContent);
		log_amx("[INFO] File '%s' not found and was created with default content.", sPath);
	}

	new JSON:jFile = json_parse(sPath, true, true);

	if (jFile == Invalid_JSON) {
		log_amx("[ERROR] JSON syntax error in '%s'.", sPath);
		return Invalid_JSON;
	}

	return jFile;
}

GetConfigPath(const sPath[] = NULL_STRING) {
	static __amxx_configsdir[PLATFORM_MAX_PATH];
	if (!__amxx_configsdir[0]) {
		get_localinfo("amxx_configsdir", __amxx_configsdir, charsmax(__amxx_configsdir));
	}
	
	new sOut[PLATFORM_MAX_PATH];
	formatex(sOut, charsmax(sOut), "%s/plugins/RWW%s%s", __amxx_configsdir, sPath[0] ? "/" : "", sPath);

	return sOut;
}

InitDebug(const bool:bForceEnable = false) {
	g_bDebug = bForceEnable || bool:(plugin_flags() & AMX_FLAG_DEBUG);

	if (!g_bDebug) {
		return;
	}
	
	get_localinfo("amxx_logs", g_sDebugFilePath, charsmax(g_sDebugFilePath));
	add(g_sDebugFilePath, charsmax(g_sDebugFilePath), "/RWW/");
	if (!dir_exists(g_sDebugFilePath)) {
		mkdir(g_sDebugFilePath);
	}

	new sFileName[64];
	get_time("%Y-%m-%d.log", sFileName, charsmax(sFileName));
	add(g_sDebugFilePath, charsmax(g_sDebugFilePath), sFileName);

	new sMapName[MAP_NAME_MAX_LEN];
	rh_get_mapname(sMapName, charsmax(sMapName), MNT_TRUE);

	log_amx("Debug mode enabled (%s)", g_sDebugFilePath);
	log_to_file(g_sDebugFilePath, "--- Start debug logging (Map: %s) ---", sMapName);
}

DebugLog(const sFmt[], any:...) {
	if (!g_bDebug) {
		return;
	}

	static sMsg[512];

	vformat(sMsg, charsmax(sMsg), sFmt, 2);
	format(sMsg, charsmax(sMsg), "[RWW][DEBUG] %s", sMsg);

	log_to_file(g_sDebugFilePath, "%s", sMsg);
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
		"RWW_OncePerMap", "1", FCVAR_NONE,
		Lang("RWW_CVAR_ONCE_PER_MAP"),
		true, 0.0, true, 1.0
	), Cvar(OncePerMap));

	bind_pcvar_num(create_cvar(
		"RWW_StartAfterSvRestart", "0", FCVAR_NONE,
		Lang("RWW_CVAR_START_AFTER_SV_RESTART"),
		true, 0.0, true, 1.0
	), Cvar(StartAfterSvRestart));


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

public plugin_natives() {
	register_native("RWW_IsWarmupInProgress", "@_IsWarmupInProgress");
}

bool:@_IsWarmupInProgress() {
	return g_bWarupInProgress;
}
