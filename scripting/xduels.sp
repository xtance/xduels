#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

// НАСТРОЙКИ ПЛАГИНА :

#define MAX_DUELS 3
#define GIFT_MONEY 0

int iInvite[MAXPLAYERS+1], iDuels;
bool bOnDuel[MAXPLAYERS+1], bDuel, bMapHasSpawns;
float f1[3],f2[3],fEdit[3],fArena[3];
char szMap[70];

public Plugin myinfo =
{
	name = "XDuels",
	author = "XTANCE",
	description = "Yet Another Duels Plugin",
	version = "1.0",
	url = "https://t.me/xtance"
};

public void OnPluginStart()
{
	bDuel = false;
	
	//Команды
	RegConsoleCmd("sm_duel", XDuel, "Пригласить на дуэль");
	RegConsoleCmd("sm_d", XDuel, "Пригласить на дуэль");
	RegAdminCmd("sm_dt", XDuelTest, ADMFLAG_ROOT, "Телепорт на место дуэли (спавн 1)");
	RegAdminCmd("sm_dspawn", XDuelSpawn, ADMFLAG_ROOT, "Настроить спавны. Конфиг будет в /addons/sourcemod/configs/skyboxduels.txt");
	HookEvent("round_start", RoundStart, EventHookMode_Post);
	HookEvent("player_death", HookPlayerDeath, EventHookMode_Post);
	
	//Блокируем випки и выдавалки оружия
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
	
	for (int i = 1; i<=MaxClients; i++)
	{
		OnClientPostAdminCheck(i);
	}
}

public Action RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (fArena[0] != 0.0 && fArena[1] != 0.0 && fArena[2] != 0.0)
	{
		CreateArena(fArena);
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SetEntityRenderColor(i, 255, 255, 255, 255);
			bOnDuel[i] = false;
		}
	}
	bDuel = false;
	iDuels = 0;
}

public void OnMapStart()
{
	PrecacheModel("models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl", true);
	PrecacheModel("models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl", true);
	bMapHasSpawns = false;
	GetCurrentMap(szMap, sizeof(szMap));
	KeyValues kv = new KeyValues("skybox_duels_spawns");
	char szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
	if(kv.ImportFromFile(szPath))
	{
		KvRewind(kv);
		KvJumpToKey(kv, szMap, true);
		KvGetVector(kv, "1", f1);
		KvGetVector(kv, "2", f2);
		KvGetVector(kv, "arenaPos", fArena);
		if (fArena[0] != 0.0 && fArena[1] != 0.0 && fArena[2] != 0.0)
		{
			f1 = fArena;
			f2 = fArena;
			f1[2] = f1[2]+18.0;
			f2[2] = f2[2]+18.0;
			f2[0] = f2[0]+100.0;
			f2[1] = f2[1]+100.0;
			CreateArena(fArena);
		}
		PrintToServer("[Skybox Duels] Спавн 1 : %.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
		PrintToServer("[Skybox Duels] Спавн 2 : %.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
		PrintToServer("[Skybox Duels] Арена : %.1f | %.1f | %.1f", fArena[0],fArena[1],fArena[2]);
	}
	if (f1[0] != 0.0 || f2[0] != 0.0)
	{
		bMapHasSpawns = true;
	}
}


public Action XDuel(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		PrintToServer("[Skybox Duels] Вам не стоит заниматься дуэлями.");
		return Plugin_Handled;
	}
	if (bDuel)
	{
		PrintToChat(iClient, " \x02>>\x01 Сейчас идёт дуэль, \x02не мешайте!");
		return Plugin_Handled;
	}
	if (iDuels>=MAX_DUELS)
	{
		PrintToChat(iClient, " \x02>>\x01 Максимум дуэлей в раунде : \x02%i!",iDuels);
		return Plugin_Handled;
	}
	if (!bMapHasSpawns)
	{
		PrintToChat(iClient, " \x02>>\x01 На этой карте \x02недоступны дуэли :С");
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
	if (iArgs < 1)
	{
		Handle mduel = CreateMenu(hduel, MenuAction_Cancel);
		SetMenuTitle(mduel, ">> Выберите игрока для дуэли :");
		char szName[MAX_NAME_LENGTH],szUser[4];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(iClient) != GetClientTeam(i))
			{
				FormatEx(szName, sizeof(szName), "%N",i);
				IntToString(i, szUser, sizeof(szUser));
				AddMenuItem(mduel, szUser, szName);
			}
		}
		DisplayMenu(mduel, iClient, MENU_TIME_FOREVER);
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
	if (!StartDuel(iClient, iTarget))
	{
		PrintToChat(iClient, " \x02>>\x01 Не получилось создать дуэль!");
		PrintToChat(iClient, " \x02>>\x01 Напишите \x02!d\x01, чтобы пригласить игрока.");
	}
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
			if (!StartDuel(param1, iSomeone))
			{
				PrintToChat(param1," \x04>>\x01 Вы пригласили \x04%N\x01 на дуэль!",iSomeone);
				PrintToChat(param1," \x04>>\x01 Он должен написать \x04!d %i\x01, чтобы согласиться.",param1);
				PrintToChat(iSomeone," \x04>>\x01 %N приглашает вас \x04на дуэль!",param1);
				PrintToChat(iSomeone," \x04>>\x01 Напишите \x04!d %i\x01, чтобы согласиться.",param1);
			}
		}
	}
	return 0;
}

public Action XDuelTest(int iClient, int iArgs)
{
	if ((iClient < 1) || (GetClientTeam(iClient) < 2))
	{
		PrintToServer("[Skybox Duels] Произошёл фейл.");
		return Plugin_Handled;
	}
	CS_RespawnPlayer(iClient);
	TeleportEntity(iClient, f1, NULL_VECTOR, NULL_VECTOR);
	bOnDuel[iClient] = true;
	//RemoveWeapon(iClient);
	PrintToChat(iClient, " \x02>>\x01 Первый спавн : \x02%.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
	PrintToChat(iClient, " \x02>>\x01 Второй спавн : \x02%.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
	return Plugin_Handled;
}

public Action XDuelSpawn(int iClient, int iArgs)
{
	if (iClient < 1)
	{
		PrintToServer("[Skybox Duels] Редактор не доступен консоли.");
		return Plugin_Handled;
	}
	Menu mspawn = new Menu(hspawn, MenuAction_Cancel);
	char szTitle[300];
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fEdit);
	Format(szTitle, sizeof(szTitle), "XDuels имеет два режима работы : \nЕсли выбрать арену, спавны сделаются сами.\nЕсли выбрать спавн, арена пропадёт!");
	mspawn.SetTitle("%s",szTitle);
	mspawn.AddItem("itemarena","Создать арену");
	mspawn.AddItem("itemx"," ",ITEMDRAW_SPACER);
	mspawn.AddItem("itemy"," ",ITEMDRAW_SPACER);
	mspawn.AddItem("item1","Создать первый спавн");
	mspawn.AddItem("item2","Создать второй спавн");
	mspawn.Display(iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int hspawn(Menu mspawn, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			KeyValues kv = new KeyValues("skybox_duels_spawns");
			char szPath[256];
			BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
			if(kv.ImportFromFile(szPath))
			{
				KvRewind(kv);
				KvJumpToKey(kv, szMap, true);
				KvGetVector(kv, "1", f1);
				KvGetVector(kv, "2", f2);
				KvGetVector(kv, "arenaPos", fArena);
			}
			KvRewind(kv);
			char item[16];
			mspawn.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "item1"))
			{
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "1", fEdit);
				KvSetVector(kv, "2", f2);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				PrintToChat(param1, " \x04>>\x01 Записал 1 спавн в configs/duels.ini!");
				PrintToChat(param1, " \x02>>\x01 Первый спавн : \x02%.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
				PrintToChat(param1, " \x02>>\x01 Второй спавн : \x02%.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
				f1 = fEdit;
				bMapHasSpawns = true;
				float f[3];
				fArena = f;
			}
			else if (StrEqual(item, "item2"))
			{
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "1", f1);
				KvSetVector(kv, "2", fEdit);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				PrintToChat(param1, " \x04>>\x01 Записал 2 спавн в configs/duels.ini!");
				PrintToChat(param1, " \x02>>\x01 Первый спавн : \x02%.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
				PrintToChat(param1, " \x02>>\x01 Второй спавн : \x02%.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
				f2 = fEdit;
				bMapHasSpawns = true;
				float f[3];
				fArena = f;
			}
			else if (StrEqual(item, "itemarena"))
			{
				fArena = fEdit;
				CreateArena(fArena);
				KvJumpToKey(kv, szMap, true);
				KvSetVector(kv, "arenaPos", fArena);
				KvRewind(kv);
				kv.ExportToFile(szPath);
				f1 = fArena;
				f2 = fArena;
				f1[2] = f1[2]+18.0;
				f2[2] = f2[2]+18.0;
				f2[0] = f2[0]+100.0;
				f2[1] = f2[1]+100.0;
				bMapHasSpawns = true;
			}
		}
	}
	return 0;
}

void CreateArena(float fInitPos[3])
{
	int iEnt;
	float fPos[3],fAng[3];
	//GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fPos);
	
	fPos = fInitPos;
	
	fAng[0] = 0.0;
	fAng[1] = 0.0;
	fAng[2] = 0.0;
	
	iEnt = CreateWall(fPos, fAng);
	fPos[0] = fPos[0]+125.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[1] = fPos[1]+125.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[0] = fPos[0]-125.0;
	iEnt = CreateWall(fPos, fAng);
	
	fPos = fInitPos;
	
	fPos[2] = fPos[2] + 130.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[0] = fPos[0]+125.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[1] = fPos[1]+125.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[0] = fPos[0]-125.0;
	iEnt = CreateWall(fPos, fAng);
	fPos[2] = fPos[2] - 120.0;
	
	fPos = fInitPos;
	
	fPos[0] = fPos[0]-65.0;
	fPos[1] = fPos[1]-65.0;
	iEnt = CreateFence(fPos, fAng);
	fPos[0] = fPos[0]+250.0;
	iEnt = CreateFence(fPos, fAng);
	fAng[1] = 90.0;
	iEnt = CreateFence(fPos, fAng);
	fPos[1] = fPos[1]+250.0;
	iEnt = CreateFence(fPos, fAng);
}

int CreateWall(float fPos[3], float fAng[3])
{
	int Entity = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(Entity, "model",  "models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl");
	DispatchKeyValue(Entity, "solid",   "6");//6
	SetEntityModel(Entity, "models/props/de_nuke/hr_nuke/nuke_bombsite_target/nuke_bombsite_trolley.mdl");
	DispatchSpawn(Entity);
	AcceptEntityInput(Entity, "DisableShadow");
	SetEntityRenderMode(Entity, RENDER_NORMAL);
	TeleportEntity(Entity, fPos, fAng, NULL_VECTOR);
	return Entity;
}

int CreateFence(float fPos[3], float fAng[3])
{
	int Entity = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(Entity, "model",  "models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl");
	DispatchKeyValue(Entity, "solid",   "6");//6
	SetEntityModel(Entity, "models/props/de_nuke/hr_nuke/chainlink_fence_001/chainlink_fence_001b_256.mdl");
	DispatchSpawn(Entity);
	AcceptEntityInput(Entity, "DisableShadow");
	SetEntityRenderMode(Entity, RENDER_NORMAL);
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

bool StartDuel(int iClient, int iTarget)
{
	if (!bDuel && IsValidCl(iTarget) && IsValidCl(iClient))
	{
		if ((iClient == iInvite[iTarget]) && (iTarget == iInvite[iClient]) && (GetClientTeam(iClient) != GetClientTeam(iTarget)))
		{
			PrintToChatAll(" \x09>>\x01 Дуэль началась!");
			PrintToChatAll(" \x09>>\x01 %N \x09VS. \x01%N!",iClient, iTarget);
			CS_RespawnPlayer(iTarget);
			CS_RespawnPlayer(iClient);
			TeleportEntity(iTarget, f1, NULL_VECTOR, NULL_VECTOR);
			TeleportEntity(iClient, f2, NULL_VECTOR, NULL_VECTOR);
			FakeClientCommand(iTarget, "use weapon_knife");
			FakeClientCommand(iClient, "use weapon_knife");
			SetEntityRenderColor(iClient, 255, 0, 0, 255);
			SetEntityRenderColor(iTarget, 0, 255, 0, 255);
			bDuel = true;
			iDuels++;
			bOnDuel[iClient] = true;
			bOnDuel[iTarget] = true;
			return true;
		}
		else
			return false;
	}
	else
		return false;
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
		bDuel = false;
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
		if (GIFT_MONEY)
		{
			PrintToChatAll(" \x09>>\x01 Он получил \x09$%i в награду!", GIFT_MONEY);
			XGift(i, GIFT_MONEY);
		}
		bOnDuel[i] = false;
		
		CS_RespawnPlayer(i);
	}
	//TeleportEntity(i, fT[i], NULL_VECTOR, NULL_VECTOR);
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

void XGift(int i, int iMoney) {
    int iStartMoney = GetEntProp(i, Prop_Send, "m_iAccount");
    iStartMoney += iMoney;
    if (iStartMoney > 16000) iStartMoney = 16000;
    SetEntProp(i, Prop_Send, "m_iAccount", iStartMoney);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom){
	
	if ((attacker<=MAXPLAYERS) && (victim<=MAXPLAYERS))
	{
		if (((damagetype & DMG_BULLET) || (attacker!=inflictor)) && (bOnDuel[victim] != bOnDuel[attacker] || bOnDuel[victim]))
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
