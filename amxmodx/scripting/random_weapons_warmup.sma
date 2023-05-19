#include <amxmodx>
#include <reapi>
#include <json>
#include <VipM/ItemsController>

/*■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■*/
#define TIME_RR 	40	// Время разминки
#define NUM_RR		2	// Кол-во рестартов
#define LATENCY		1.5	// Задержка между рестартами
#define DM_MODE		1	// Возрождение после смерти; 0 - отключить (будет длится раунд или до победы)
#define PROTECTED 	2	// Сколько секунд действует защита после возрождения (актуально для DM_MODE); 0 - отключить

#define SOUND			// Музыка под час разминки
#define STOP_PLUGS		// Отключать плагины на время разминки (Файл amxmodx/configs/plugins/RWW/DisablePlugins.json)
#define IGNORE_MAPS			// Отключать этот плагин на указанных картах (Файл amxmodx/configs/plugins/RWW/IgnoredMaps.json)
//#define REMOVE_MAP_WPN    // Удалять ентити мешающие разминке на картах типа: awp_, 35hp_ и т.п. [по умолчанию выкл.]
//#define BLOCK_PICKUP           // Запрет поднятия оружия с земли (не актуально при вкл. #define REMOVE_MAP_WPN) [по умолчанию выкл.]
//#define STOP_STATS		// Отключать запись статистики на время разминки  CSStatsX SQL by serfreeman1337 0.7.4+1 [по умолчанию выкл.]

// TODO: Вынести это всё в квары
/*■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■*/

#if defined REMOVE_MAP_WPN
#include <hamsandwich>
#endif

#define MAP_NAME_MAX_LEN 32
#define PLUGIN_NAME_MAX_LEN 64

enum _:S_WarmupMode {
	WM_Title[64],
	// TODO: WM_Duration, // Разная длительность у разных режимов
	Array:WM_Items,
}

#if defined SOUND
new const soundRR[][] =	// Указывать звук, например 1.mp3
{	
	"sound/rww/RoundStart.mp3",
//	"sound/rww/2.mp3",
//	"sound/rww/3.mp3"
}
#endif

#if DM_MODE == 0
new HookChain:fwd_RRound;
new g_iRound;
#endif

#if defined REMOVE_MAP_WPN
new HamHook:fwd_Equip,
	HamHook:fwd_WpnStrip,
	HamHook:fwd_Entity;
#endif

#if defined STOP_STATS
new g_iHudSync;
#endif
new g_iImmunuty, g_iRespawn, g_iHudSync2;
new HookChain:fwd_NewRound,
	#if defined BLOCK_PICKUP
	HookChain:fwd_BlockEntity,
	#endif
	HookChain:fwd_Spawn,
	HookChain:fwd_GiveC4;

const TASK_TIMER_ID = 33264;

#if defined STOP_PLUGS
new Array:g_aDisablePlugins = Invalid_Array;
#endif

new bool:g_bWarupInProgress = false;
new Array:g_aModes = Invalid_Array;

new g_SelectedMode[S_WarmupMode];

new fwOnStarted;
new fwOnFinished;

public plugin_init() {
	register_plugin("Random Weapons WarmUP", "3.0.0", "neugomon/h1k3/ArKaNeMaN");

	#if defined IGNORE_MAPS
	if (IsMapIgnored()) {
		// TODO: Добавить лог о том что разминка выключена
		pause("ad");
		return;
	}
	#endif

	#if defined STOP_PLUGS
	DisablePluginsLoad();
	#endif

	WarmupModesLoad();
	
	fwOnStarted = CreateMultiForward("RWW_OnStarted", ET_IGNORE);
	fwOnFinished = CreateMultiForward("RWW_OnFinished", ET_IGNORE);

	RegisterHookChain(RG_RoundEnd, "fwdRoundEnd", true);
	DisableHookChain(fwd_NewRound = RegisterHookChain(RG_CSGameRules_CheckMapConditions, "fwdRoundStart", true));
	DisableHookChain(fwd_Spawn = RegisterHookChain(RG_CBasePlayer_Spawn, "fwdPlayerSpawnPost", true));
	DisableHookChain(fwd_GiveC4 = RegisterHookChain(RG_CSGameRules_GiveC4, "fwdGiveC4", false));

	#if defined REMOVE_MAP_WPN
	DisableHamForward(fwd_Equip = RegisterHam(Ham_Use, "game_player_equip", "CGamePlayerEquip_Use", false));
	DisableHamForward(fwd_WpnStrip = RegisterHam(Ham_Use, "player_weaponstrip", "CStripWeapons_Use", false));
	DisableHamForward(fwd_Entity = RegisterHam(Ham_CS_Restart, "armoury_entity", "CArmoury_Restart", false));
	#endif

	#if DM_MODE == 0
	EnableHookChain(fwd_RRound = RegisterHookChain(RG_CSGameRules_RestartRound, "fwdRestartRound_Pre"));
	#endif

	#if defined BLOCK_PICKUP
	DisableHookChain(fwd_BlockEntity = RegisterHookChain(RG_CBasePlayer_HasRestrictItem, "fwdHasRestrictItemPre", false));
	register_clcmd("drop", "ClCmd_Drop");
	#endif

	g_iImmunuty = get_cvar_pointer("mp_respawn_immunitytime");
	g_iRespawn  = get_cvar_pointer("mp_forcerespawn");
	#if defined STOP_STATS
	g_iHudSync = CreateHudSyncObj();
	#endif
	g_iHudSync2 = CreateHudSyncObj();

	g_bWarupInProgress = false;
}

public plugin_end() {
	if (g_bWarupInProgress) {
		finishWurmUp();
	}
}

#if defined BLOCK_PICKUP
public fwdHasRestrictItemPre() {
	SetHookChainReturn(ATYPE_INTEGER, true);
	return HC_SUPERCEDE;
}

public ClCmd_Drop() {
	return g_bWarupInProgress
		? PLUGIN_HANDLED
		: PLUGIN_CONTINUE;
}
#endif

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

	#if defined REMOVE_MAP_WPN
	EnableHamForward(fwd_Equip);
	EnableHamForward(fwd_WpnStrip);
	EnableHamForward(fwd_Entity);
	#endif

	DisableHookChain(fwd_NewRound);
	EnableHookChain(fwd_Spawn);
	EnableHookChain(fwd_GiveC4);

	set_pcvar_num(g_iRespawn, DM_MODE);
	set_pcvar_num(g_iImmunuty, PROTECTED);

	#if DM_MODE >= 1
	set_cvar_string("mp_round_infinite", "1");
	set_task(1.0, "Show_Timer", .flags = "a", .repeat = TIME_RR);
	#endif

	#if DM_MODE == 0
	set_task(1.0, "Hud_Message", .flags = "a", .repeat = 25 );
	#endif

	#if defined SOUND
	static cmd[64];
	formatex(cmd, 63, "mp3 play ^"%s^"", soundRR[random(sizeof(soundRR))]);
	client_cmd(0, "%s", cmd);
	#endif

	#if defined STOP_STATS
	set_cvar_num("csstats_pause", 1);
	#endif

	#if defined BLOCK_PICKUP
	EnableHookChain(fwd_BlockEntity);
	#endif

	#if defined STOP_PLUGS	
	PluginController(1);
	#endif

	new iRnd = random_num(0, ArraySize(g_aModes) - 1);
	ArrayGetArray(g_aModes, iRnd, g_SelectedMode);
	log_amx("[DEBUG] ArraySize(g_aModes) = %d", ArraySize(g_aModes));
	log_amx("[DEBUG] iRnd = %d", iRnd);
	log_amx("[DEBUG] g_SelectedMode[WM_Title] = %s", g_SelectedMode[WM_Title]);
}

public fwdPlayerSpawnPost(const id) {
	if (!is_user_alive(id)) {
		return;
	}

	#if defined REMOVE_MAP_WPN
	InvisibilityArmourys();
	#endif

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

#if DM_MODE >= 1
public Show_Timer() {
	static timer = -1;

	if (timer == -1) {
		timer = TIME_RR;
	}

	if (--timer == 0) {
		finishWurmUp();
		timer = -1;
		return;
	}

	#if defined STOP_STATS
	set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync, "[Статистика Отключена]");
	#endif
	
	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync2, "Разминка на %s!^nРестарт через %d сек", g_SelectedMode[WM_Title], timer);
}
#endif

#if DM_MODE == 0
public fwdRestartRound_Pre() {
	g_iRound++;

	if (g_iRound >= 2) {
		DisableHookChain(fwd_RRound);
		finishWurmUp();
	}
}

public Hud_Message() {
	#if defined STOP_STATS
	set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync, "[Статистика Отключена]");
	#endif

	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 0.9, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync2, "Разминка на %s!", g_SelectedMode[WM_Title]);
}
#endif

public SV_Restart() {
	set_cvar_num("sv_restart", 1);
	set_task(2.0, "End_RR");
}

public End_RR() {
	#if defined STOP_STATS
	set_hudmessage(255, 0, 0, .x = -1.0, .y = 0.05, .holdtime = 5.0, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync, "[Статистика Включена]");
	#endif

	set_hudmessage(135, 206, 235, .x = -1.0, .y = 0.08, .holdtime = 5.0, .channel = -1);
	ShowSyncHudMsg(0, g_iHudSync2, "Разминка окончена!");

	for (new i = 1; i <= MaxClients; i++) {
		if (is_user_alive(i)) {
			rg_remove_items_by_slot(i, PRIMARY_WEAPON_SLOT);
		}
	}
}

#if defined REMOVE_MAP_WPN
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
#endif

finishWurmUp() {
	g_bWarupInProgress = false;
			  
	BuyZone_ToogleSolid(SOLID_TRIGGER);

	#if defined REMOVE_MAP_WPN
	DisableHamForward(fwd_Equip);
	DisableHamForward(fwd_WpnStrip);
	DisableHamForward(fwd_Entity);
	#endif

	DisableHookChain(fwd_Spawn);
	DisableHookChain(fwd_GiveC4);

	set_cvar_string("mp_forcerespawn", "0");
	set_cvar_string("mp_respawn_immunitytime", "0");
	set_cvar_string("mp_round_infinite", "0");

	#if defined STOP_STATS
	set_cvar_num("csstats_pause", 0);
	#endif

	#if defined BLOCK_PICKUP
	DisableHookChain(fwd_BlockEntity);
	#endif

	#if defined STOP_PLUGS   
	PluginController(0);
	#endif
	
	ExecuteForward(fwOnFinished);

	#if NUM_RR > 1       
	set_task(LATENCY, "SV_Restart", .flags = "a", .repeat = NUM_RR - 1);
	#endif
	SV_Restart();

	// Не совсем понял какой именно таск надо убивать)
	remove_task(TASK_TIMER_ID);
}

stock PluginController(stop) {
	new sPluginName[PLUGIN_NAME_MAX_LEN];
	for (new i; i < ArraySize(g_aDisablePlugins); i++) {
		ArrayGetString(g_aDisablePlugins, i, sPluginName, charsmax(sPluginName));

		if (stop) {
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

		log_amx("[DEBUG] PUSH Mode{WM_Title='%s', count(WM_Items)=%d}", Mode[WM_Title], ArraySize(Mode[WM_Items]));
		ArrayPushArray(g_aModes, Mode);
		log_amx("[DEBUG] PUSH ArraySize(g_aModes) = %d", ArraySize(g_aModes));
	}
	
	json_free(jModes);
}

stock DisablePluginsLoad() {
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

stock bool:IsMapIgnored() {
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

stock BuyZone_ToogleSolid(const solid) {
	new entityIndex = 0;
	while ((entityIndex = rg_find_ent_by_class(entityIndex, "func_buyzone"))) {
		set_entvar(entityIndex, var_solid, solid);
	}
}

stock JSON:Json_GetFile(const sPath[]) {
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

stock GetConfigPath(const sPath[]) {
    static __amxx_configsdir[PLATFORM_MAX_PATH];
    if (!__amxx_configsdir[0]) {
        get_localinfo("amxx_configsdir", __amxx_configsdir, charsmax(__amxx_configsdir));
    }
    
    return fmt("%s/plugins/RWW/%s", __amxx_configsdir, sPath);
}
