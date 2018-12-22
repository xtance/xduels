#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <autoexecconfig>

#undef REQUIRE_PLUGIN
#tryinclude <vip_core>
#tryinclude <vip_fm>

#pragma semicolon 1
#pragma newdecls required


int iInvite[MAXPLAYERS+1], iDuels, iInvis, iMode, iMax, iMoney, iHealth, iTime, iCount;
bool bOnDuel[MAXPLAYERS+1], bNowDuel, bCanDuel, bNoThrowingKnives;
float f1[3],f2[3],fEdit[3],fArena[3];
char szMap[70];

ConVar g_mode,g_blockvipcommands,g_max,g_money,g_nothrowingknives,g_health,g_time;

ArrayList aArena;

public Plugin myinfo =
{
	name = "XDuels",
	author = "XTANCE",
	description = "Yet Another Duels Plugin",
	version = "1.0",
	url = "https://t.me/xtance"
};

public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iErr_max)
{
	MarkNativeAsOptional("VIPFM_ToggleFeature");
	MarkNativeAsOptional("VIP_IsClientVIP");
	return APLRes_Success;
}

public void OnPluginStart()
{
	AutoExecConfig_SetFile("xduels");
	AutoExecConfig_SetCreateFile(true);
	g_mode = AutoExecConfig_CreateConVar("xduels_mode", "0", "0 = живые и мертвые могут использовать плагин, 1 = только живые, 2 = только мертвые");
	g_max = AutoExecConfig_CreateConVar("xduels_max", "3", "Сколько дуэлей можно сыграть за раунд. Подсчёт ведется глобально, а НЕ отдельно для каждого игрока. Не ставьте 0");
	g_health = AutoExecConfig_CreateConVar("xduels_health", "100", "ХП игрока");
	g_time = AutoExecConfig_CreateConVar("xduels_time", "5", "Отсчёт до начала дуэли");
	g_money = AutoExecConfig_CreateConVar("xduels_money", "0", "Сколько денег получит победитель");
	g_blockvipcommands = AutoExecConfig_CreateConVar("xduels_blockvipcommands", "1", "Блокировать команды !vip !viptest !wp и ещё кучу других на арене (1/0)");
	g_nothrowingknives = AutoExecConfig_CreateConVar("xduels_nothrowingknives", "0", "Отнимать функцию кидательных ножей. Только для VIP от R1KO. Требует : https://hlmod.ru/resources/vip-features-manager.756/ !!! (1/0)");
	AutoExecConfig_ExecuteFile();
	
	aArena = new ArrayList();
	aArena.Clear();
	bNowDuel = false;
	
	RegConsoleCmd("sm_duel", XDuel, "Пригласить на дуэль");
	RegConsoleCmd("sm_d", XDuel, "Пригласить на дуэль");
	RegAdminCmd("sm_dt", XDuelTest, ADMFLAG_ROOT, "Телепорт на место дуэли (1/2)");
	RegAdminCmd("sm_dset", XDuelSpawn, ADMFLAG_ROOT, "Настроить спавны. Конфиг будет в /addons/sourcemod/configs/xduels.ini");
	RegAdminCmd("sm_noduel", XNoDuel, ADMFLAG_ROOT, "Запретить дуэли на один раунд. Используйте в других плагинах через ServerCommand!");
	HookEvent("round_start", RoundStart, EventHookMode_Post);
	HookEvent("round_end", RoundEnd, EventHookMode_Post);
	HookEvent("player_death", HookPlayerDeath, EventHookMode_Post);

	for (int i = 1; i<=MaxClients; i++)
	{
		OnClientPostAdminCheck(i);
	}
}

public void OnConfigsExecuted()
{
	if (g_blockvipcommands.BoolValue)
	{
		AddCommandListener(XNoVip,"sm_vip");
		AddCommandListener(XNoVip,"sm_viptest");
		AddCommandListener(XNoVip,"sm_testvip");
		AddCommandListener(XNoVip,"sm_premium");
		AddCommandListener(XNoVip,"sm_wp");
		AddCommandListener(XNoVip,"sm_weaponmenu");
		AddCommandListener(XNoVip,"sm_grenades");
		AddCommandListener(XNoVip,"sm_pistols");
		AddCommandListener(XNoVip,"sm_guns");
		AddCommandListener(XNoVip,"sm_zeus");
	}
	bNoThrowingKnives = g_nothrowingknives.BoolValue;
	iMode = g_mode.IntValue;
	iMax = g_max.IntValue;
	iMoney = g_money.IntValue;
	iHealth = g_health.IntValue;
	iTime = g_time.IntValue;
	iCount = iTime;
}

public Action RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (fArena[0] != 0.0 && fArena[1] != 0.0 && fArena[2] != 0.0)
	{
		CreateArena(fArena);
		AdjustSpawns();
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SetEntityRenderColor(i, 255, 255, 255, 255);
			bOnDuel[i] = false;
		}
	}
	bNowDuel = false;
}

public Action RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	bCanDuel = false;
	iDuels = 0;
}

public void OnMapStart()
{
	PrecacheModel("models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl", true);
	PrecacheModel("models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl", true);
	bCanDuel = false;
	GetCurrentMap(szMap, sizeof(szMap));
	PrintToChatAll(" \x02>>\x01 Арена пересоздастся при старте раунда!");
	KeyValues kv = new KeyValues("xduels");
	char szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
	if(kv.ImportFromFile(szPath))
	{
		KvRewind(kv);
		KvJumpToKey(kv, szMap, true);
		KvGetVector(kv, "arenaPos", fArena);
	}
	delete kv;
	if (fArena[0] != 0.0 && fArena[1] != 0.0 && fArena[2] != 0.0)
	{
		CreateArena(fArena);
		AdjustSpawns();
	}
}

public Action XNoDuel(int iClient, int iArgs)
{
	iDuels = iMax;
	ReplyToCommand(iClient, ">> Дуэли отключены на раунд!");
	return Plugin_Handled;
}

public Action XDuel(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		PrintToServer("[XDuels] Вам не стоит заниматься дуэлями.");
		return Plugin_Handled;
	}
	if (!bCanDuel)
	{
		PrintToChat(iClient, " \x02>>\x01 Дуэли временно недоступны!");
		return Plugin_Handled;
	}
	if (iDuels>=iMax)
	{
		PrintToChat(iClient, " \x02>>\x01 Максимум дуэлей в раунде : \x02%i!",iDuels);
		return Plugin_Handled;
	}
	if (GameRules_GetProp("m_bWarmupPeriod") == 1)
	{
		PrintToChat(iClient, " \x02>>\x01 На разминке \x02дуэль невозможна!");
		return Plugin_Handled;
	}
	if (GetClientTeam(iClient) < 2)
	{
		PrintToChat(iClient, " \x02>>\x01 Зайдите за \x02СТ или Т!");
		return Plugin_Handled;
	}
	if (!IsClientOk(iClient))
	{
		return Plugin_Handled;
	}
	if (iArgs < 1)
	{
		Menu mduel = new Menu(hduel, MenuAction_Cancel);
		mduel.SetTitle(">> Выберите игрока для дуэли :");
		char szName[MAX_NAME_LENGTH],szUser[4];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (iMode == 0)
			{
				if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(iClient) != GetClientTeam(i))
				{
					FormatEx(szName, sizeof(szName), "%N",i);
					IntToString(i, szUser, sizeof(szUser));
					mduel.AddItem(szUser, szName);
				}
			}
			else if (iMode == 1)
			{
				if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(iClient) != GetClientTeam(i) && IsPlayerAlive(i))
				{
					FormatEx(szName, sizeof(szName), "%N",i);
					IntToString(i, szUser, sizeof(szUser));
					mduel.AddItem(szUser, szName);
				}
			}
			else if (iMode == 2)
			{
				if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(iClient) != GetClientTeam(i) && !IsPlayerAlive(i))
				{
					FormatEx(szName, sizeof(szName), "%N",i);
					IntToString(i, szUser, sizeof(szUser));
					mduel.AddItem(szUser, szName);
				}
			}
			else
			{
				mduel.AddItem("1337",  "Настройте xduels_mode в /cfg/sourcemod/xduels.cfg!");
			}
		}
		mduel.Display(iClient, MENU_TIME_FOREVER);
		return Plugin_Handled;
	}
	char szArg[16];
	GetCmdArgString(szArg, sizeof(szArg));
	char szTarget[16];
	int iLen = BreakString(szArg, szTarget, sizeof(szTarget));
	if (iLen == -1)
	{
		iLen = 0;
		szArg[0] = '\0';
	}
	iInvite[iClient] = StringToInt(szTarget);
	int iTarget = iInvite[iClient];
	StartDuel(iClient, iTarget);
	return Plugin_Handled;
}



public int hduel(Menu mduel, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char item[32];
			mduel.GetItem(param2, item, sizeof(item));
			int iSomeone;
			iSomeone = StringToInt(item);
			iInvite[param1] = iSomeone;
			StartDuel(param1, iSomeone);
		}
	}
	return 0;
}

public Action XDuelTest(int iClient, int iArgs)
{
	if ((iClient < 1) || (GetClientTeam(iClient) < 2))
	{
		PrintToServer("[XDuels] Произошёл фейл.");
		return Plugin_Handled;
	}
	if (iArgs < 1)
	{
		PrintToChat(iClient, " \x02>>\x01 !d 1 или !d 2 для \x02теста спавна!");
	}
	char szSpawn[4];
	GetCmdArgString(szSpawn, sizeof(szSpawn));
	if (StrEqual(szSpawn,"1",false))
	{
		CS_RespawnPlayer(iClient);
		TeleportEntity(iClient, f1, NULL_VECTOR, NULL_VECTOR);
		bOnDuel[iClient] = true;
	}
	else if (StrEqual(szSpawn,"2",false))
	{	
		CS_RespawnPlayer(iClient);
		TeleportEntity(iClient, f2, NULL_VECTOR, NULL_VECTOR);
		bOnDuel[iClient] = true;
	}

	PrintToChat(iClient, " \x02>>\x01 Первый спавн : \x02%.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
	PrintToChat(iClient, " \x02>>\x01 Второй спавн : \x02%.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
	return Plugin_Handled;
}

public Action XDuelSpawn(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		PrintToServer("[XDuels] Редактор не доступен в консоли.");
		return Plugin_Handled;
	}
	Menu mspawn = new Menu(hspawn, MenuAction_Cancel);
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fEdit);
	mspawn.SetTitle("Настройка Арены :");
	mspawn.AddItem("itemarena","Создать арену");
	mspawn.AddItem("itemx"," ",ITEMDRAW_SPACER);
	mspawn.AddItem("itemremove","Удалить арену");
	mspawn.AddItem("itemy"," ",ITEMDRAW_SPACER);
	mspawn.AddItem("itemtrans","Прозрачность");
	mspawn.AddItem("itemmove","Перемещение");
	mspawn.Display(iClient, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int hspawn(Menu mspawn, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			KeyValues kv = new KeyValues("xduels");
			char szPath[256];
			BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
			if(kv.ImportFromFile(szPath))
			{
				KvRewind(kv);
				KvJumpToKey(kv, szMap, true);
				KvGetVector(kv, "arenaPos", fArena);
			}
			KvRewind(kv);
			char item[32];
			mspawn.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "itemarena"))
			{
				fArena = fEdit;
				fArena[0] = fArena[0]-75.0;
				fArena[1] = fArena[1]-75.0;
				fArena[2] = fArena[2]-25.0;
				CreateArena(fArena);
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "arenaPos", fArena);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				AdjustSpawns();
				bCanDuel = true;
				delete kv;
			}
			if (StrEqual(item, "itemremove"))
			{
				int iEnt;
				if (aArena.Length < 1)
				{
					PrintToChat(param1," \x02>>\x01 Нет арены, либо плагин перезагрузился!");
				}
				for (int i = 0; i <= (aArena.Length - 1); i++)
				{
					iEnt = aArena.Get(i);
					if (IsValidEntity(iEnt))
					{
						AcceptEntityInput(iEnt, "Kill");
					}
				}
				aArena.Clear();
				fArena[0] = 0.0;
				fArena[1] = 0.0;
				fArena[2] = 0.0;
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "arenaPos", fArena);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				bCanDuel = false;
				delete kv;
			}
			if (StrEqual(item, "itemtrans"))
			{
				int iEnt;
				if (aArena.Length < 1)
				{
					PrintToChat(param1," \x02>>\x01 Нет арены, либо плагин перезагрузился!");
				}
				if (iInvis != 1)
				{
					for (int i = 0; i <= (aArena.Length - 1); i++)
					{
						iEnt = aArena.Get(i);
						if (IsValidEntity(iEnt))
						{
							SetEntityRenderMode(iEnt, RENDER_NONE);
						}
					}
					PrintToChat(param1," \x02>>\x01 Режим арены : \x02невидимая!");
					KvJumpToKey(kv, szMap, true);
					KvSetNum(kv, "invis", 1);
					KvRewind(kv);
					kv.ExportToFile(szPath);
					iInvis = 1;
					delete kv;
				}
				else
				{
					for (int i = 0; i <= (aArena.Length - 1); i++)
					{
						iEnt = aArena.Get(i);
						if (IsValidEntity(iEnt))
						{
							SetEntityRenderMode(iEnt, RENDER_NORMAL);
						}
					}
					PrintToChat(param1," \x02>>\x01 Режим арены : \x02видимая!");
					PrintToChat(param1," \x02>>\x01 Возможно, придётся подождать.");
					KvJumpToKey(kv, szMap, true);
					KvSetNum(kv, "invis", 0);
					KvRewind(kv);
					kv.ExportToFile(szPath);
					iInvis = 0;
					delete kv;
				}
			}
			if (StrEqual(item, "itemmove"))
			{
				XMove(param1);
			}
		}
	}
	return 0;
}

void XMove(int iClient)
{
	Menu mmove = new Menu(hmove, MenuAction_Cancel);
	mmove.SetTitle("Перемещение");
	mmove.AddItem("itemxplus","Вправо [X+]");
	mmove.AddItem("itemxminus","Влево  [X-]");
	mmove.AddItem("itemyplus","Вперёд [Y+]");
	mmove.AddItem("itemyminus","Назад  [Y-]");
	mmove.AddItem("itemzplus","Вверх  [Z+]");
	mmove.AddItem("itemzminus","Вниз   [Z-]");
	mmove.AddItem("itemok","Сохранить изменения");
	mmove.Display(iClient, MENU_TIME_FOREVER);
}

public int hmove(Menu mmove, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			bCanDuel = false;
			char item[32];
			mmove.GetItem(param2, item, sizeof(item));
			int iXYZ, iEnt;
			float fAdd;
			if (StrEqual(item, "itemxplus"))
			{
				iXYZ = 0;
				fAdd = 10.0;
			}
			if (StrEqual(item, "itemxminus"))
			{
				iXYZ = 0;
				fAdd = -10.0;
			}
			if (StrEqual(item, "itemyplus"))
			{
				iXYZ = 1;
				fAdd = 10.0;
			}
			if (StrEqual(item, "itemyminus"))
			{
				iXYZ = 1;
				fAdd = -10.0;
			}
			if (StrEqual(item, "itemzplus"))
			{
				iXYZ = 2;
				fAdd = 10.0;
			}
			if (StrEqual(item, "itemzminus"))
			{
				iXYZ = 2;
				fAdd = -10.0;
			}
			if (StrEqual(item, "itemok"))
			{
				fAdd = 0.0;
				KeyValues kv = new KeyValues("xduels");
				char szPath[256];
				BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
				if(kv.ImportFromFile(szPath))
				{
					KvRewind(kv);
				}
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "arenaPos", fArena);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				delete kv;
				bCanDuel = true;
				PrintToChat(param1, " \x04>>\x01 Изменения записаны. \x04Дуэли доступны!");
			}
			if (fAdd != 0.0)
			{
				for (int i = 0; i <= (aArena.Length - 1); i++)
				{
					iEnt = aArena.Get(i);
					if (IsValidEntity(iEnt))
					{
						float fPos[3];
						GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
						fPos[iXYZ]+=fAdd;
						TeleportEntity(iEnt, fPos, NULL_VECTOR, NULL_VECTOR);
					}
				}
				fArena[iXYZ]+=fAdd;
				AdjustSpawns();
				XMove(param1);
			}
		}
	}
	return 0;
}

void AdjustSpawns()
{
	f1 = fArena;
	f2 = fArena;
	f1[2] = f1[2]+20.0;
	f2[2] = f2[2]+20.0;
	f1[0] = f1[0]+150.0;
	f1[1] = f1[1]+150.0;
	f2[0] = f2[0]-30.0;
	f2[1] = f2[1]-30.0;
}

void CreateArena(float fInitPos[3])
{
	int iEnt;
	for (int i = 0; i <= (aArena.Length - 1); i++)
	{
		iEnt = aArena.Get(i);
		if (IsValidEntity(iEnt))
		{
			AcceptEntityInput(iEnt, "Kill");
		}
	}
	aArena.Clear();
	
	float fPos[3],fAng[3];
	fPos = fInitPos;
	fAng[0] = 0.0;
	fAng[1] = 0.0;
	fAng[2] = 0.0;
	
	//Делаем пол
	aArena.Push(CreateWall(fPos, fAng));
	fPos[0]+=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	fPos[1]+=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	fPos[0]-=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	
	//Делаем потолок
	fPos = fInitPos;
	fPos[2]+=140.0;
	aArena.Push(CreateWall(fPos, fAng));
	fPos[0]+=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	fPos[1]+=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	fPos[0]-=125.0;
	aArena.Push(CreateWall(fPos, fAng));
	
	//Делаем стены
	fPos = fInitPos;
	fPos[2]+=15.0;
	fPos[0]-=65.0;
	fPos[1]-=67.0;
	aArena.Push(CreateFence(fPos, fAng));
	fPos[0]+=255.0;
	aArena.Push(CreateFence(fPos, fAng));
	fAng[1] = 90.0;
	fPos = fInitPos;
	fPos[2]+=15.0;
	fPos[0]+=255.0;
	fPos[0]-=65.0;
	fPos[1]-=65.0;
	aArena.Push(CreateFence(fPos, fAng));
	fPos[1]+=255.0;
	aArena.Push(CreateFence(fPos, fAng));
	bCanDuel = true;
	PrintToConsoleAll("\n\n>> Арена создана (%i) !",aArena.Length);
}

int CreateWall(float fPos[3], float fAng[3])
{
	int Entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(Entity, "model",  "models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl");
	DispatchKeyValue(Entity, "solid",   "6");
	SetEntityModel(Entity, "models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl");
	DispatchSpawn(Entity);
	if (iInvis == 1)
	{
		SetEntityRenderMode(Entity, RENDER_NONE);
	}
	else
	{
		SetEntityRenderMode(Entity, RENDER_NORMAL);
	}
	TeleportEntity(Entity, fPos, fAng, NULL_VECTOR);
	return Entity;
}

int CreateFence(float fPos[3], float fAng[3])
{
	int Entity = CreateEntityByName("prop_dynamic");
	DispatchKeyValue(Entity, "model",  "models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl");
	DispatchKeyValue(Entity, "solid",   "6");
	SetEntityModel(Entity, "models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl");
	DispatchSpawn(Entity);
	if (iInvis == 1)
	{
		SetEntityRenderMode(Entity, RENDER_NONE);
	}
	else
	{
		SetEntityRenderMode(Entity, RENDER_NORMAL);
	}
	TeleportEntity(Entity, fPos, fAng, NULL_VECTOR);
	return Entity;
}

public void OnClientPostAdminCheck(int iClient) 
{
	if (IsClientInGame(iClient))
	{
		iInvite[iClient] = -1;
		bOnDuel[iClient] = false;
		SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}
bool IsValidCl(int i)
{
	if (IsClientInGame(i) && (GetClientTeam(i) > 1) && (1<=i<=MAXPLAYERS) && !IsFakeClient(i))
		return true;
	else return false;
}

bool IsClientOk(int i)
{
	if (iMode == 0)
	{
		return true;
	}
	else if (!IsPlayerAlive(i) && iMode == 1)
	{
		PrintToChat(i, " \x02>>\x01 Дуэли могут играть только живые игроки!");
		return false;
	}
	else if (IsPlayerAlive(i) && iMode == 2)
	{
		PrintToChat(i, " \x02>>\x01 Дуэли могут играть только мёртвые игроки!");
		return false;
	}
	else
	{
		return true;
	}
}

void StartDuel(int iClient, int iTarget)
{
	if ((!IsValidCl(iClient)) || (!IsValidCl(iTarget)))
	{
		//
	}
	else if (!((iClient == iInvite[iTarget]) && (iTarget == iInvite[iClient])))
	{
		PrintToChat(iClient," \x04>>\x01 Вы пригласили \x04%N\x01 на дуэль!",iTarget);
		PrintToChat(iClient," \x04>>\x01 Он должен написать \x04!d %i\x01, чтобы согласиться.",iClient);
		PrintToChat(iTarget," \x04>>\x01 %N приглашает вас \x04на дуэль!",iClient);
		PrintToChat(iTarget," \x04>>\x01 Напишите \x04!d %i\x01, чтобы согласиться.",iClient);
	}
	else if ((!IsClientOk(iClient)) || (!IsClientOk(iTarget)))
	{
		//
	}
	else if (bNowDuel)
	{
		PrintToChat(iClient, " \x02>>\x01 Сейчас идёт дуэль, \x02не мешайте!");
		PrintToChat(iTarget, " \x02>>\x01 Сейчас идёт дуэль, \x02не мешайте!");
	}
	else if (GetClientTeam(iClient) == GetClientTeam(iTarget))
	{
		PrintToChat(iClient, " \x02>>\x01 Нельзя играть дуэль \x02с тиммейтом\x01 (%N)", iTarget);
		PrintToChat(iTarget, " \x02>>\x01 Нельзя играть дуэль \x02с тиммейтом\x01 (%N)", iClient);
	}
	else
	{
		PrintToChatAll(" \x09>>\x01 Дуэль началась!");
		PrintToChatAll(" \x09>>\x01 %N \x09VS. \x01%N!",iClient, iTarget);
		CS_RespawnPlayer(iTarget);
		CS_RespawnPlayer(iClient);
		SetEntPropFloat(iTarget, Prop_Send, "m_flLaggedMovementValue", 0.0);
		SetEntPropFloat(iClient, Prop_Send, "m_flLaggedMovementValue", 0.0);
		TeleportEntity(iTarget, f1, NULL_VECTOR, NULL_VECTOR);
		TeleportEntity(iClient, f2, NULL_VECTOR, NULL_VECTOR);
		FakeClientCommand(iTarget, "use weapon_knife");
		FakeClientCommand(iClient, "use weapon_knife");
		SetEntityRenderColor(iClient, 255, 0, 0, 255);
		SetEntityRenderColor(iTarget, 0, 255, 0, 255);
		if (bNoThrowingKnives)
		{
			if(VIP_IsClientVIP(iClient))
			{
				VIPFM_ToggleFeature(iClient, false, "ThrowingKnives");
			}
			if(VIP_IsClientVIP(iTarget))
			{
				VIPFM_ToggleFeature(iTarget, false, "ThrowingKnives");
			}
		}
		bNowDuel = true;
		iDuels++;
		bOnDuel[iClient] = true;
		bOnDuel[iTarget] = true;
		CreateTimer(1.0, Timer_GetReady, _, TIMER_REPEAT);
	}
}

public Action Timer_GetReady(Handle timer)
{
	if (iCount <= 0)
	{
		iCount = iTime;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (bOnDuel[i])
			{
				PrintHintText(i,">> <font color='#ff0000'>Дуэль началась!!");
				SetEntityHealth(i, iHealth);
				SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
			}
		}
		return Plugin_Stop;
	}
	
	char szReady[400];
	FormatEx(szReady, sizeof(szReady), ">> <font color='#00cc99'>Дуэль начнётся через <font color='#00ff00'>%i секунд!", iCount);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (bOnDuel[i])
		{
			PrintHintText(i,szReady);
			SetEntityHealth(i, 1337);
			ClientCommand(i, "play buttons/button17.wav");
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 0.0);
		}
	}
	iCount--;
 
	return Plugin_Continue;
}

public Action HookPlayerDeath(Handle event, const char[] szName, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	if (bOnDuel[iClient])
	{
		bOnDuel[iClient] = false;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidCl(i) && bOnDuel[i])
			{
				RequestFrame(XWin, i);
				iInvite[i] = -1;
			}
		}
		bNowDuel = false;
		iInvite[iClient] = -1;
	}
	return Plugin_Continue;
}

public void XWin(int i)
{
	if (IsValidCl(i))
	{
		PrintToChatAll(" \x09>>\x01 %N выиграл дуэль.", i);
		SetEntityRenderColor(i, 255, 255, 255, 255);
		if (iMoney > 0)
		{
			PrintToChatAll(" \x09>>\x01 Он получил \x09$%i в награду!", iMoney);
			XGift(i, iMoney);
		}
		bOnDuel[i] = false;
		
		CS_RespawnPlayer(i);
		SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
		if (bNoThrowingKnives)
		{
			if(VIP_IsClientVIP(i))
			{
				VIPFM_ToggleFeature(i, true, "ThrowingKnives");
			}
		}
	}
}


public Action XNoVip(int iClient, const char[] szCmd, int iArgc)
{
	if (bOnDuel[iClient])
	{
		RequestFrame(XBlock, iClient);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void XBlock(int i)
{
	Panel panel = new Panel();
	panel.SetTitle("Данная команда недоступна на дуэли!\n");
	panel.DrawItem("Понятно");
	panel.DrawItem("Тоже понятно, но под другой цифрой");
	panel.DrawItem("Ничего не понятно");
	panel.Send(i, PanelHandler1, 10);
	delete panel;
}

public int PanelHandler1(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		//
	}
}

void XGift(int i, int fAddMoney) {
    int iStartMoney = GetEntProp(i, Prop_Send, "m_iAccount");
    iStartMoney += fAddMoney;
    if (iStartMoney > 16000) iStartMoney = 16000;
    SetEntProp(i, Prop_Send, "m_iAccount", iStartMoney);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom){
	
	if ((attacker<=MAXPLAYERS) && (victim<=MAXPLAYERS))
	{
		if ((!(damagetype & DMG_SLASH)) && (bOnDuel[victim] != bOnDuel[attacker] || bOnDuel[victim]))
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
