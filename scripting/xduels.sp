#include <sourcemod>
#include <cstrike>
#include <sdktools>

// НАСТРОЙКИ ПЛАГИНА :

#define MAX_DUELS 3
#define GIFT_MONEY 1500

int iInvite[MAXPLAYERS+1], iDuels;
bool bOnDuel[MAXPLAYERS+1], bDuel, bMapHasSpawns;
float f1[3],f2[3],fEdit[3];
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
}

public Action RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			bOnDuel[i] = false;
		}
	}
	bDuel = false;
	iDuels = 0;
}

public void OnMapStart()
{
	GetCurrentMap(szMap, sizeof(szMap));
	KeyValues kv = new KeyValues("skybox_duels_spawns");
	char szPath[256]
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
	if(kv.ImportFromFile(szPath))
	{
		KvRewind(kv);
		KvJumpToKey(kv, szMap, true);
		KvGetVector(kv, "1", f1);
		KvGetVector(kv, "2", f2);
		PrintToServer("[Skybox Duels] Спавн 1 : %.1f | %.1f | %.1f", f1[0],f1[1],f1[2]);
		PrintToServer("[Skybox Duels] Спавн 2 : %.1f | %.1f | %.1f", f2[0],f2[1],f2[2]);
		bMapHasSpawns = true;
	}
	if (f1[0] == 0.0 || f2[0] == 0.0)
	{
		bMapHasSpawns = false;
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
		PrintToChat(iClient, " \x02>>\x01 Дуэль невозможна!");
		PrintToChat(iClient, " \x02>>\x01 Напишите \x02!duel\x01, чтобы пригласить игрока.");
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
				PrintToChat(param1," \x04>>\x01 Он должен написать \x04!duel %i\x01, чтобы согласиться.",param1);
				PrintToChat(iSomeone," \x04>>\x01 %N приглашает вас \x04на дуэль!",param1);
				PrintToChat(iSomeone," \x04>>\x01 Напишите \x04!duel %i\x01, чтобы согласиться.",param1);
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
	RemoveWeapon(iClient);
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
	Handle mspawn = CreateMenu(hspawn, MenuAction_Cancel);
	char szTitle[300];
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", fEdit);
	Format(szTitle, sizeof(szTitle), "Карта : %s\nПозиция : %.1f | %.1f | %.1f\nКакой это спавн?",szMap,fEdit[0],fEdit[1],fEdit[2]);
	SetMenuTitle(mspawn, szTitle);
	AddMenuItem(mspawn, "item1", "Первый");
	AddMenuItem(mspawn, "item2", "Второй");
	DisplayMenu(mspawn, iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int hspawn(Menu mspawn, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			KeyValues kv = new KeyValues("skybox_duels_spawns");
			char szPath[256]
			BuildPath(Path_SM, szPath, sizeof(szPath), "configs/duels.ini");
			if(kv.ImportFromFile(szPath))
			{
				KvRewind(kv);
				KvJumpToKey(kv, szMap, true);
				KvGetVector(kv, "1", f1);
				KvGetVector(kv, "2", f2);
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
			}
		}
	}
	return 0;
}


public void OnClientPostAdminCheck(int iClient) 
{
	if (IsClientInGame(iClient))
	{
		iInvite[iClient] = -1;
		bOnDuel[iClient] = false;
	}
}

void RemoveWeapon(int iClient)
{
	for(int i = 0, iEntity; i < 5; i++)
	{
		while((iEntity = GetPlayerWeaponSlot(iClient, i)) != -1)
		{
			RemovePlayerItem(iClient, iEntity);
			AcceptEntityInput(iEntity, "Kill");
		}
	}
	GivePlayerItem(iClient, "weapon_knife");
}

bool StartDuel(iClient, iTarget)
{
	if ((1 < iClient <= MAXPLAYERS+1) && (1 < iTarget <= MAXPLAYERS+1))
	{
		if (IsClientInGame(iTarget) && IsClientInGame(iClient) && GetClientTeam(iTarget) > 1 && GetClientTeam(iTarget) > 1)
		{
			if ((iClient == iInvite[iTarget]) && (iTarget == iInvite[iClient]) && (GetClientTeam(iClient) != GetClientTeam(iTarget)))
			{
				PrintToChatAll(" \x09>>\x01 Дуэль началась!");
				PrintToChatAll(" \x09>>\x01 %N \x09VS. \x01%N!",iClient, iTarget);
				CS_RespawnPlayer(iTarget);
				CS_RespawnPlayer(iClient);
				TeleportEntity(iTarget, f1, NULL_VECTOR, NULL_VECTOR);
				TeleportEntity(iClient, f2, NULL_VECTOR, NULL_VECTOR);
				bDuel = true;
				iDuels++;
				
				RemoveWeapon(iClient);
				RemoveWeapon(iTarget);
				bOnDuel[iClient] = true;
				bOnDuel[iTarget] = true;
				return true;
			}
			else return false;
		}
		else return false;
	}
	else return false;
}

public Action HookPlayerDeath(Handle event, const char[] szName, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	if (bOnDuel[iClient])
	{
		bOnDuel[iClient] = false;
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && bOnDuel[i])
			{
				RequestFrame(XWin, i);
				iInvite[i] = 0;
			}
		}
		bDuel = false;
		iInvite[iClient] = 0;
	}
	return Plugin_Continue;
}

public void XWin(i)
{
	PrintToChatAll(" \x09>>\x01 %N выиграл дуэль.", i);
	if (GIFT_MONEY)
	{
		PrintToChatAll(" \x09>>\x01 Он получил \x09$%i в награду!", GIFT_MONEY);
		XGift(i, GIFT_MONEY);
	}
	CS_RespawnPlayer(i);
	bOnDuel[i] = false;
}

public Action XNoVip(iClient, const char[] szCmd, argc)
{
	if (bOnDuel[iClient])
	{
		RequestFrame(XBlock, iClient);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void XBlock(i)
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

void XGift(i, iMoney) {
    int iStartMoney = GetEntProp(i, Prop_Send, "m_iAccount");
    iStartMoney += iMoney;
    if (iStartMoney > 16000) iStartMoney = 16000;
    SetEntProp(i, Prop_Send, "m_iAccount", iStartMoney);
}
