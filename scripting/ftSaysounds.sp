#include <sourcemod>
#include <sdktools>
#include <sdktools_sound>
#include <clientprefs>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.8"

#define SAYSOUND_FLAG_DOWNLOAD        (1 << 0)
#define SAYSOUND_FLAG_CUSTOMVOLUME    (1 << 1)
#define SAYSOUND_FLAG_CUSTOMLENGTH    (1 << 2)

#define SAYSOUND_SOUND_NAME_SIZE 64

#define SAYSOUND_PITCH_MAX 200
#define SAYSOUND_PITCH_MIN 50

#define SAYSOUND_VOLUME_MAX 100
#define SAYSOUND_VOLUME_MIN 0

#define SAYSOUND_LENGTH_MAX 10
#define SAYSOUND_LENGTH_MIN 0

#define SAYSOUND_PREFIX_SPEED "@"
#define SAYSOUND_PREFIX_LENGTH "%"

ConVar g_cSaySoundsEnabled;
ConVar g_cSaySoundsInterval;
ConVar g_cSaySoundsCancelChat;

Handle g_hSoundToggleCookie;
Handle g_hSoundVolumeCookie;
Handle g_hSoundLengthCookie;
Handle g_hSoundPitchCookie;
Handle g_hSoundRestrictionCookie;
Handle g_hSoundRestrictionTimeCookie;

// Plugin cvar related.
bool g_bPluginEnabled;
bool g_bSaySoundsCancelChat;
float g_fSaySoundsInterval;

// Plugin logic related.
float g_fLastSaySound[MAXPLAYERS+1];

// Client prefs (Player setting) related.
bool g_bIsPlayerRestricted[MAXPLAYERS+1];
bool g_bPlayerSoundDisabled[MAXPLAYERS+1];
float g_fPlayerSoundVolume[MAXPLAYERS+1];
float g_fPlayerSoundLength[MAXPLAYERS+1];
float g_fPlayerRestrictionTime[MAXPLAYERS+1];
int g_iPlayerSoundPitch[MAXPLAYERS+1];

// Internal
Handle g_hPath;
Handle g_hSoundName;
Handle g_hLength;
Handle g_hVolume;
Handle g_hFlags;
Handle g_hCheckPreCached;

EngineVersion g_hServerGameEngine;

public Plugin myinfo = 
{
    name = "Say Sounds FT",
    author = "faketuna",
    description = "Plays sound files.\nSpecial thanks for testing plugin >> kur4yam1, valni_nyas, omoi",
    version = PLUGIN_VERSION,
    url = "https://short.f2a.dev/s/github"
};

public void OnPluginStart()
{
    g_cSaySoundsEnabled            = CreateConVar("sm_saysounds_enable", "1", "Toggles say sounds globaly", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cSaySoundsInterval        = CreateConVar("sm_saysounds_interval", "2.0", "Time between each sound to trigger per player. 0.0 to disable", FCVAR_NONE, true, 0.0, true, 30.0);
    g_cSaySoundsCancelChat        = CreateConVar("sm_saysounds_format_chat", "1", "Cancel the chat message when match with saysound.", FCVAR_NONE, true, 0.0, true, 1.0);
    CreateConVar("sm_saysounds_version", PLUGIN_VERSION, "The version of plugin", FCVAR_NOTIFY);

    g_cSaySoundsEnabled.AddChangeHook(OnCvarsChanged);
    g_cSaySoundsInterval.AddChangeHook(OnCvarsChanged);
    g_cSaySoundsCancelChat.AddChangeHook(OnCvarsChanged);

    g_hSoundVolumeCookie            = RegClientCookie("cookie_ss_volume", "Saysound volume", CookieAccess_Protected);
    g_hSoundLengthCookie            = RegClientCookie("cookie_ss_length", "Saysound length", CookieAccess_Protected);
    g_hSoundPitchCookie             = RegClientCookie("cookie_ss_pitch", "Saysound pitch", CookieAccess_Protected);
    g_hSoundRestrictionCookie       = RegClientCookie("cookie_ss_restriction", "Saysound restriction", CookieAccess_Protected);
    g_hSoundRestrictionTimeCookie   = RegClientCookie("cookie_ss_restriction_time", "Saysound restriction time", CookieAccess_Protected);
    g_hSoundToggleCookie            = RegClientCookie("cookie_ss_toggle", "Saysound toggle", CookieAccess_Protected);

    RegConsoleCmd("sm_ss_volume", CommandSSVolume, "Set saysounds volume per player.");
    RegConsoleCmd("sm_ss_speed", CommandSSSpeed, "Set saysounds speed per player.");
    RegConsoleCmd("sm_ss_length", CommandSSLength, "Set saysounds length per player.");
    RegConsoleCmd("sm_ss_toggle", CommandSSToggle, "Toggle saysounds per player.");
    RegConsoleCmd("sm_ssmenu", CommandSSMenu, "Toggle saysounds per player.");
    RegConsoleCmd("sm_saysounds", CommandSSMenu, "Toggle saysounds per player.");
    RegConsoleCmd("sm_saysound", CommandSSMenu, "Toggle saysounds per player.");
    RegConsoleCmd("sm_ss_list", CommandSSList, "Show saysounds list");
    RegConsoleCmd("sm_sslist", CommandSSList, "Show saysounds list");
    RegConsoleCmd("sm_ss_search", CommandSSSearch, "Search and show saysounds list");
    RegConsoleCmd("sm_sss", CommandSSSearch, "Search and show saysounds list");

    RegAdminCmd("sm_ss_ban", CommandSBanUser, ADMFLAG_CHAT, "Ban a specific user.");
    RegAdminCmd("sm_ss_unban", CommandSUnBanUser, ADMFLAG_CHAT, "unban a specific user.");

    AddCommandListener(CommandListenerSay, "say");
    AddCommandListener(CommandListenerSay, "say2");
    AddCommandListener(CommandListenerSay, "say_team");
    ParseConfig();

    LoadTranslations("common.phrases");
    LoadTranslations("ftSaysounds.phrases");

    g_hServerGameEngine = GetEngineVersion();

    SetCookieMenuItem(SoundSettingsMenu, 0 ,"Saysounds");
    for(int i = 1; i <= MaxClients; i++) {
        g_fLastSaySound[i] = GetGameTime();
        if(IsClientConnected(i)) {
            if(AreClientCookiesCached(i)) {
                OnClientCookiesCached(i);
            }
        }
    }
}


public void OnClientCookiesCached(int client) {
    if (IsFakeClient(client)) {
        return;
    }

    char cookieValue[128];
    GetClientCookie(client, g_hSoundVolumeCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_fPlayerSoundVolume[client] = StringToFloat(cookieValue);
    } else {
        g_fPlayerSoundVolume[client] = 1.0;
        SetClientCookie(client, g_hSoundVolumeCookie, "1.0");
    }


    GetClientCookie(client, g_hSoundLengthCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_fPlayerSoundLength[client] = StringToFloat(cookieValue);
        if(StrEqual(cookieValue, "0.0") || StrEqual(cookieValue, "-1.0") || StrEqual(cookieValue, "0") ) {
            g_fPlayerSoundLength[client] = -1.0;
        }
    } else {
        g_fPlayerSoundLength[client] = -1.0;
        SetClientCookie(client, g_hSoundLengthCookie, "-1.0");
    }
    

    GetClientCookie(client, g_hSoundPitchCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_iPlayerSoundPitch[client] = StringToInt(cookieValue);
    } else {
        g_iPlayerSoundPitch[client] = 100;
        SetClientCookie(client, g_hSoundPitchCookie, "100");
    }


    GetClientCookie(client, g_hSoundRestrictionCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_bIsPlayerRestricted[client] = view_as<bool>(StringToInt(cookieValue));
    } else {
        g_bIsPlayerRestricted[client] = false;
        SetClientCookie(client, g_hSoundRestrictionCookie, "false");
    }


    GetClientCookie(client, g_hSoundRestrictionTimeCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_fPlayerRestrictionTime[client] = StringToFloat(cookieValue);
    } else {
        g_fPlayerRestrictionTime[client] = 0.0;
        SetClientCookie(client, g_hSoundRestrictionTimeCookie, "0.0");
    }


    GetClientCookie(client, g_hSoundToggleCookie, cookieValue, sizeof(cookieValue));

    if (!StrEqual(cookieValue, "")) {
        g_bPlayerSoundDisabled[client] = view_as<bool>(StringToInt(cookieValue));
    } else {
        g_bPlayerSoundDisabled[client] = false;
        SetClientCookie(client, g_hSoundToggleCookie, "false");
    }
}

public void OnConfigsExecuted() {
    SyncConVarValues();
}

public void OnMapStart() {
    AddDownloadTableAll();
    for(int i = GetArraySize(g_hCheckPreCached)-1; i >= 0; i--) {
        SetArrayCell(g_hCheckPreCached, i, false);
    }
    for(int i = 1; i <= MaxClients; i++) {
        g_fLastSaySound[i] = GetGameTime();
    }
}

public void SyncConVarValues() {
    g_bPluginEnabled        = GetConVarBool(g_cSaySoundsEnabled);
    g_bSaySoundsCancelChat  = GetConVarBool(g_cSaySoundsCancelChat);
    g_fSaySoundsInterval    = GetConVarFloat(g_cSaySoundsInterval);
}

public void OnCvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    SyncConVarValues();
}

public Action CommandListenerSay(int client, const char[] command, int argc) {
    if(client == 0) {
        return Plugin_Handled;
    }
    if(!g_bPluginEnabled) {
        return Plugin_Continue;
    }
    if(g_bIsPlayerRestricted[client]) {
        return Plugin_Continue;
    }

    char arg1[128], arg2[32], arg3[32];
    GetCmdArg(1, arg1, sizeof(arg1));
    GetCmdArg(2, arg2, sizeof(arg2));
    GetCmdArg(3, arg3, sizeof(arg3));

    char cBuff[4][32];
    int cArgs = ExplodeString(arg1, " ", cBuff, 4, 32);

    if(cArgs == 1 && !StrEqual(arg2, "")) {
        cArgs = 2;
        if(!StrEqual(arg3, "")) {
            cArgs = 3;
        }
    } else {
        strcopy(arg1, sizeof(arg1), cBuff[0]);
        strcopy(arg2, sizeof(arg2), cBuff[1]);
        strcopy(arg3, sizeof(arg3), cBuff[2]);
    }

    if(cArgs > 1 && StrContains(arg2, SAYSOUND_PREFIX_SPEED) == -1 && StrContains(arg2, SAYSOUND_PREFIX_LENGTH) == -1) {
        return Plugin_Continue;
    }

    int si = GetSaySoundIndex(cBuff[0]);
    if(si == -1) {
        return Plugin_Continue;
    }

    if(!TryPrecacheSound(si)) {
        return Plugin_Continue;
    }

    float ft = GetGameTime() - g_fLastSaySound[client];
    char buff[4];
    Format(buff, sizeof(buff), "%.1f", g_fSaySoundsInterval-ft);
    if(ft <= g_fSaySoundsInterval && g_fSaySoundsInterval != 0.0) {
        CPrintToChat(client, "%t%t", "ss prefix", "ss dont spam", buff);
        if(g_bSaySoundsCancelChat) {
            return Plugin_Handled;
        }
        return Plugin_Continue;
    }
    switch(cArgs) {
        case 1: {
            TrySaySound(client, arg1, si, -1, -1.0);
            if(g_bSaySoundsCancelChat) {
                return Plugin_Handled;
            }
        }
        case 2: {
            if(StrContains(arg2, SAYSOUND_PREFIX_SPEED) != -1) {
                int p = ProcessPitch(arg2);

                TrySaySound(client, arg1, si, p, -1.0);

                if(g_bSaySoundsCancelChat) {
                    return Plugin_Handled;
                }
            }
            else if(StrContains(arg2, SAYSOUND_PREFIX_LENGTH) != -1) {
                float l = ProcessLength(arg2);

                TrySaySound(client, arg1, si, 100, l);

                if(g_bSaySoundsCancelChat) {
                    return Plugin_Handled;
                }
            }
        }
        case 3: {
            int p = 100;
            float l = 0.0;
            if(StrContains(arg2, SAYSOUND_PREFIX_SPEED) != -1) {
                p = ProcessPitch(arg2);
                l = ProcessLength(arg3);
            } else {
                p = ProcessPitch(arg3);
                l = ProcessLength(arg2);
            }
            TrySaySound(client, arg1, si, p, l);
            if(g_bSaySoundsCancelChat) {
                return Plugin_Handled;
            }
        }
        default: {return Plugin_Continue;}
    }
    return Plugin_Continue;
}

void TrySaySound(int client, char[] soundName, int saySoundIndex, int pitch = 100, float length = 0.0) {
    if(pitch == -1) {
        pitch = g_iPlayerSoundPitch[client];
    }
    if(length == -1.0) {
        length = g_fPlayerSoundLength[client];
    }
    char fileLocation[PLATFORM_MAX_PATH];

    GetArrayString(g_hPath, saySoundIndex, fileLocation, sizeof(fileLocation));

    g_fLastSaySound[client] = GetGameTime();
    for(int i = 1; i <= MaxClients; i++) {
        if(!IsClientInGame(i) || g_bPlayerSoundDisabled[i]) {
            continue;
        }
        EmitSoundToClient(
            i,
            fileLocation,
            SOUND_FROM_PLAYER,
            SNDCHAN_STATIC,
            SNDLEVEL_NORMAL,
            SND_NOFLAGS,
            g_fPlayerSoundVolume[i],
            pitch,
            0,
            NULL_VECTOR,
            NULL_VECTOR,
            true,
            0.0
        );
    }
    if(length != -1.0) {
        DataPack pack;
        CreateDataTimer(length, StopSoundTimer, pack);
        pack.WriteString(fileLocation);
    }
    if(g_bSaySoundsCancelChat) {
        if(pitch != -1 && pitch != 100 && length != -1.0) {
            CPrintToChatAll("{purple}%N {default}played {lightgreen}%s {lightred}(Speed: %d | seconds: %.1f)", client, soundName, pitch, length);
            return;
        }
        if(pitch != -1 && pitch != 100) {
            CPrintToChatAll("{purple}%N {default}played {lightgreen}%s {lightred}(Speed: %d)", client, soundName, pitch);
            return;
        }
        if(length != -1.0) {
            CPrintToChatAll("{purple}%N {default}played {lightgreen}%s {lightred}(seconds: %.1f)", client, soundName, length);
            return;
        } else {
            CPrintToChatAll("{purple}%N {default}played {lightgreen}%s", client, soundName);
            return;
        }
    }
}

int ProcessPitch(const char[] argText) {
    char ag[6];
    strcopy(ag, sizeof(ag), argText);
    ReplaceString(ag, sizeof(ag), SAYSOUND_PREFIX_SPEED, "");

    if(StrEqual(ag, "")) {return -1;}
    if(!IsOnlyDicimal(ag)) { return -1;}

    int p = StringToInt(ag);
    if(p > SAYSOUND_PITCH_MAX || SAYSOUND_PITCH_MIN > p) {
        return -1;
    }
    return p;
}

float ProcessLength(const char[] argText) {
    char ag[6];
    strcopy(ag, sizeof(ag), argText);
    ReplaceString(ag, sizeof(ag), SAYSOUND_PREFIX_LENGTH, "");

    char check[6];
    strcopy(check, sizeof(check), ag);
    ReplaceString(check, sizeof(check), ".", "");
    if(StrEqual(check, "")) {return -1.0;}
    if(!IsOnlyDicimal(check)) { return -1.0;}

    float l = StringToFloat(ag);
    if(l < SAYSOUND_LENGTH_MIN || l > SAYSOUND_LENGTH_MAX) {
        return -1.0;
    }
    return l;
}

public Action StopSoundTimer(Handle timer, DataPack pack) {
    char soundPath[PLATFORM_MAX_PATH];
    pack.Reset();
    pack.ReadString(soundPath, sizeof(soundPath));
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i)) {
            StopSound(i, SNDCHAN_STATIC, soundPath);
        }

    }
    return Plugin_Stop;
}

int GetSaySoundIndex(const char[] soundName) {
    char buff[SAYSOUND_SOUND_NAME_SIZE];
    for(int i = 0; i < GetArraySize(g_hSoundName); i++) {
        GetArrayString(g_hSoundName, i, buff, sizeof(buff));
        if(StrEqual(buff, soundName, false)) {
            return i;
        }
    }
    return -1;
}

void ParseConfig() {
    g_hPath        = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    g_hLength       = CreateArray();
    g_hSoundName    = CreateArray(ByteCountToCells(SAYSOUND_SOUND_NAME_SIZE));
    g_hVolume        = CreateArray();
    g_hFlags       = CreateArray();
    g_hCheckPreCached = CreateArray();

    char soundListFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM,soundListFile,sizeof(soundListFile),"configs/saysounds.cfg");
    if(!FileExists(soundListFile)) {
        SetFailState("saysounds.cfg failed to parse! Reason: File doesn't exist!");
    }
    Handle listFile = CreateKeyValues("soundlist");
    FileToKeyValues(listFile, soundListFile);
    KvRewind(listFile);

    if(KvGotoFirstSubKey(listFile)) {
        char fileLocation[PLATFORM_MAX_PATH], soundName[SAYSOUND_SOUND_NAME_SIZE];
        float duration, volume;

        do {
            KvGetString(listFile, "file", fileLocation, sizeof(fileLocation), "");
            if(fileLocation[0] != '\0') {
                KvGetSectionName(listFile, soundName, sizeof(soundName));
                int flags = 0;
                if(KvGetNum(listFile, "download", 0)) {
                    flags |= SAYSOUND_FLAG_DOWNLOAD;
                }

                duration = KvGetFloat(listFile, "duration", 0.0);
                if(duration) {
                    flags |= SAYSOUND_FLAG_CUSTOMLENGTH;
                }

                volume = KvGetFloat(listFile, "volume", 0.0);
                if(volume) {
                    flags |= SAYSOUND_FLAG_CUSTOMVOLUME;
                    if(volume > 2.0) {
                        volume = 2.0;
                    } 
                }
                if(g_hServerGameEngine == Engine_CSGO) {
                    Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                } else {
                    Format(fileLocation, sizeof(fileLocation), "%s", fileLocation);
                }
                PushArrayString(g_hPath, fileLocation);
                PushArrayCell(g_hLength, duration);
                PushArrayCell(g_hVolume, volume);
                PushArrayCell(g_hFlags, flags);
                PushArrayString(g_hSoundName, soundName);
                PushArrayCell(g_hCheckPreCached, false);
            }
        } while(KvGotoNextKey(listFile));
    } else {
        SetFailState("saysounds.cfg failed to parse! Reason: No subkeys found!");
    }
}

void AddDownloadTableAll() {
    char soundFile[PLATFORM_MAX_PATH], buffer[PLATFORM_MAX_PATH];
    int flags;
    for(int i = GetArraySize(g_hPath) - 1; i >= 0; i--) {
        GetArrayString(g_hPath, i, soundFile, sizeof(soundFile));
        flags = GetArrayCell(g_hFlags, i);
        if(flags & SAYSOUND_FLAG_DOWNLOAD) {
            FormatEx(buffer, sizeof(buffer), "sound/%s", soundFile);
            AddFileToDownloadsTable(buffer);
        }
    }
}

bool TryPrecacheSound(int index) {
    if(!GetArrayCell(g_hCheckPreCached, index)) {
        char soundFile[PLATFORM_MAX_PATH];
        GetArrayString(g_hPath, index, soundFile, sizeof(soundFile));
        if(g_hServerGameEngine == Engine_CSGO) {
            AddToStringTable(FindStringTable("soundprecache"), soundFile);
        } else {
            PrecacheSound(soundFile);
        }
        SetArrayCell(g_hCheckPreCached, index, true);
    }
    return GetArrayCell(g_hCheckPreCached, index);
}

bool IsOnlyDicimal(char[] string) {
    for(int i = 0; i < strlen(string); i++) {
        if (!IsCharNumeric(string[i])) {
            return false;
        }
    }
    return true;
}




// USER COMMAND AREA

public Action CommandSSList(int client, int args) {
    DisplaySSListMenu(client);
    return Plugin_Handled;
}

public Action CommandSSSearch(int client, int args) {
    if(args == 0) {
        CPrintToChat(client, "%t%t", "ss prefix", "ss cmd search usage");
        return Plugin_Handled;
    }
    char buff[SAYSOUND_SOUND_NAME_SIZE];
    GetCmdArg(1, buff, sizeof(buff));
    if(strlen(buff) < 3) {
        CPrintToChat(client, "%t%t", "ss prefix", "ss cmd search minimum chars");
        return Plugin_Handled;
    }
    
    DisplaySSSResultMenu(client, buff);
    return Plugin_Handled;
}

public Action CommandSSMenu(int client, int args) {
    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

public Action CommandSSVolume(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(!IsOnlyDicimal(arg1)) {
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd invalid arguments");
            return Plugin_Handled;
        }
        int arg = StringToInt(arg1);
        if(arg > SAYSOUND_VOLUME_MAX || SAYSOUND_VOLUME_MIN > arg) {
            char buff[8];
            Format(buff, sizeof(buff), "%d", arg);
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd value out of range", buff);
            return Plugin_Handled;
        }

        g_fPlayerSoundVolume[client] = float(StringToInt(arg1)) / 100;
        char buff[6];
        FloatToString(g_fPlayerSoundVolume[client], buff, sizeof(buff));
        SetClientCookie(client, g_hSoundVolumeCookie, buff);
        CPrintToChat(client, "%t%t", "ss prefix", "ss cmd set volume", arg1);
        return Plugin_Handled;
    }

    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

public Action CommandSSSpeed(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(!IsOnlyDicimal(arg1)) {
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd invalid arguments");
            return Plugin_Handled;
        }

        int arg = StringToInt(arg1);
        if(arg > SAYSOUND_PITCH_MAX || SAYSOUND_PITCH_MIN > arg) {
            char buff[8];
            Format(buff, sizeof(buff), "%d", arg);
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd value out of range", buff);
            return Plugin_Handled;
        }

        g_iPlayerSoundPitch[client] = arg;
        SetClientCookie(client, g_hSoundPitchCookie, arg1);
        CPrintToChat(client, "%t%t", "ss prefix", "ss cmd set speed", arg1);
        return Plugin_Handled;
    }

    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

public Action CommandSSLength(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        
        char check[6];
        strcopy(check, sizeof(check), arg1);
        ReplaceString(check, sizeof(check), ".", "");
        if(!IsOnlyDicimal(check)) {
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd length cleared");
            SetClientCookie(client, g_hSoundLengthCookie, "-1.0");
            g_fPlayerSoundLength[client] = -1.0;
            return Plugin_Handled;
        }
        float c = StringToFloat(arg1);
        if(c > float(SAYSOUND_LENGTH_MAX) || c < float(SAYSOUND_LENGTH_MIN)) {
            char buff[8];
            Format(buff, sizeof(buff), "%.1f", c);
            CPrintToChat(client, "%t%t", "ss prefix", "ss cmd value out of range", buff);
            return Plugin_Handled;
        }
        g_fPlayerSoundLength[client] = StringToFloat(arg1);
        SetClientCookie(client, g_hSoundLengthCookie, arg1);
        CPrintToChat(client, "%t%t", "ss prefix", "ss cmd set length", arg1);
        return Plugin_Handled;
    }

    DisplaySettingsMenu(client);
    return Plugin_Handled;
}

public Action CommandSSToggle(int client, int args) {
    g_bPlayerSoundDisabled[client] = !g_bPlayerSoundDisabled[client];
    SetClientCookie(client, g_hSoundToggleCookie, g_bPlayerSoundDisabled[client] ? "1" : "0");
    CPrintToChat(client, "%t%t", "ss prefix", g_bPlayerSoundDisabled[client] ? "ss cmd toggle disable" : "ss cmd toggle enable");
    return Plugin_Handled;
}


// USER MANAGEMENT COMMAND AREA

public Action CommandSBanUser(int client, int args) {
    if(args >= 1) {
        char target[65];
        char targetName[MAX_TARGET_LENGTH];
        int targetList[MAXPLAYERS];
        int targetCount;
        bool tn_is_ml;

        GetCmdArg(1, target, sizeof(target));
        targetCount = ProcessTargetString(
            target,
            client,
            targetList,
            MAXPLAYERS,
            0,
            targetName,
            sizeof(targetName),
            tn_is_ml
        );

        if(targetCount <= -1) {
            ReplyToTargetError(client, targetCount);
            DisplayBanSuggesion(client, target, false);
            return Plugin_Handled;
        } else if(targetCount == 0) {
            ReplyToTargetError(client, targetCount);
            return Plugin_Handled;
        }
        if(targetCount == 1) {
            char buff[MAX_TARGET_LENGTH];
            GetClientName(targetList[0], buff, sizeof(buff));
            if(g_bIsPlayerRestricted[targetList[0]]) {
                CPrintToChat(client, "%t%t", "ss prefix", "ss user already banned", buff);
                return Plugin_Handled;
            }

            CPrintToChat(client, "%t%t", "ss prefix", "ss user banned", buff);
            g_bIsPlayerRestricted[targetList[0]] = true;
            SetClientCookie(targetList[0], g_hSoundRestrictionCookie, "1");
            return Plugin_Handled;
        }
        return Plugin_Handled;
    }

    DisplayBanSuggesion(client, "", false);
    return Plugin_Handled;
}

public Action CommandSUnBanUser(int client, int args) {
    if(args >= 1) {
        char target[65];
        char targetName[MAX_TARGET_LENGTH];
        int targetList[MAXPLAYERS];
        int targetCount;
        bool tn_is_ml;

        GetCmdArg(1, target, sizeof(target));
        targetCount = ProcessTargetString(
            target,
            client,
            targetList,
            MAXPLAYERS,
            0,
            targetName,
            sizeof(targetName),
            tn_is_ml
        );

        if(targetCount <= -1) {
            ReplyToTargetError(client, targetCount);
            DisplayBanSuggesion(client, target, true);
            return Plugin_Handled;
        } else if(targetCount == 0) {
            ReplyToTargetError(client, targetCount);
            return Plugin_Handled;
        }
        if(targetCount == 1) {
            char buff[MAX_TARGET_LENGTH];
            GetClientName(targetList[0], buff, sizeof(buff));
            if(!g_bIsPlayerRestricted[targetList[0]]) {
                CPrintToChat(client, "%t%t", "ss prefix", "ss user not banned", buff);
                return Plugin_Handled;
            }

            CPrintToChat(client, "%t%t", "ss prefix", "ss user unbanned", buff);
            g_bIsPlayerRestricted[targetList[0]] = false;
            SetClientCookie(targetList[0], g_hSoundRestrictionCookie, "0");
            return Plugin_Handled;
        }
        return Plugin_Handled;
    }

    DisplayBanSuggesion(client, "", true);
    return Plugin_Handled;
}



// MENU HANDLER AREA

void DisplaySSListMenu(int client)
{
    SetGlobalTransTarget(client);
    Menu prefmenu = CreateMenu(SSListMenuHanlder, MENU_ACTIONS_DEFAULT);

    char menuTitle[64];
    Format(menuTitle, sizeof(menuTitle), "%t", "ss menu list");
    prefmenu.SetTitle(menuTitle);
    int size = GetArraySize(g_hSoundName);
    char buff[SAYSOUND_SOUND_NAME_SIZE];
    for(int i = 0; i < size; i++) {
        GetArrayString(g_hSoundName, i, buff, sizeof(buff));
        prefmenu.AddItem(buff, buff);
    }
    prefmenu.Display(client, MENU_TIME_FOREVER);
}


public int SSListMenuHanlder(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[SAYSOUND_SOUND_NAME_SIZE];
        GetMenuItem(prefmenu, item, preference, sizeof(preference));
        FakeClientCommand(client, "say %s", preference);
    }
    else if (actions == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCookieMenu(client);
        }
    }
    else if (actions == MenuAction_End)
    {
        CloseHandle(prefmenu);
    }
    return 0;
}


void DisplaySSSResultMenu(int client, char[] search)
{
    SetGlobalTransTarget(client);
    Menu prefmenu = CreateMenu(SSListMenuHanlder, MENU_ACTIONS_DEFAULT);

    int size = GetArraySize(g_hSoundName);
    int found = 0;
    char buff[SAYSOUND_SOUND_NAME_SIZE];
    for(int i = 0; i < size; i++) {
        GetArrayString(g_hSoundName, i, buff, sizeof(buff));
        if(StrContains(buff, search, false) >= 0) {
            prefmenu.AddItem(buff, buff);
            found++;
        }
    }
    char menuTitle[64];
    Format(menuTitle, sizeof(menuTitle), "%t", "ss menu search found", search, found);
    prefmenu.SetTitle(menuTitle);

    if(found == 0) {
        CPrintToChat(client, "%t%t", "ss prefix", "ss menu search not found", search);
        CloseHandle(prefmenu);
        return;
    }
    prefmenu.Display(client, MENU_TIME_FOREVER);
}


public int SSSResultMenuHanlder(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[SAYSOUND_SOUND_NAME_SIZE];
        GetMenuItem(prefmenu, item, preference, sizeof(preference));
        FakeClientCommand(client, "say %s", preference);
    }
    else if (actions == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCookieMenu(client);
        }
    }
    else if (actions == MenuAction_End)
    {
        CloseHandle(prefmenu);
    }
    return 0;
}


void DisplaySettingsMenu(int client)
{
    SetGlobalTransTarget(client);
    Menu prefmenu = CreateMenu(SoundSettingHandler, MENU_ACTIONS_DEFAULT);

    char menuTitle[64];
    Format(menuTitle, sizeof(menuTitle), "%t", "ss menu title");
    prefmenu.SetTitle(menuTitle);

    char isRestricted[64], restrectionExpireDate[64], soundDisabled[64], soundVolume[64], soundLength[64] , soundPitch[64];

    Format(isRestricted, sizeof(isRestricted), "%t%t","ss menu restricted", g_bIsPlayerRestricted[client] ? "Yes" : "No");
    prefmenu.AddItem("ss_pref_is_restricted", isRestricted);
    if(g_bIsPlayerRestricted[client]) {
        Format(restrectionExpireDate, sizeof(restrectionExpireDate), "%t%f","ss menu expire", g_fPlayerRestrictionTime[client]);
        prefmenu.AddItem("ss_pref_restriction_expire", restrectionExpireDate);
    }

    Format(soundDisabled, sizeof(soundDisabled), "%t%t","ss menu disable saysounds", g_bPlayerSoundDisabled[client] ? "Yes" : "No");
    prefmenu.AddItem("ss_pref_disable", soundDisabled);

    Format(soundVolume, sizeof(soundVolume), "%t%.0f%","ss menu volume", g_fPlayerSoundVolume[client] * 100);
    switch (RoundToZero((g_fPlayerSoundVolume[client]*100)))
    {
        case 10: { prefmenu.AddItem("ss_pref_volume_100", soundVolume);}
        case 20: { prefmenu.AddItem("ss_pref_volume_10", soundVolume);}
        case 30: { prefmenu.AddItem("ss_pref_volume_20", soundVolume);}
        case 40: { prefmenu.AddItem("ss_pref_volume_30", soundVolume);}
        case 50: { prefmenu.AddItem("ss_pref_volume_40", soundVolume);}
        case 60: { prefmenu.AddItem("ss_pref_volume_50", soundVolume);}
        case 70: { prefmenu.AddItem("ss_pref_volume_60", soundVolume);}
        case 80: { prefmenu.AddItem("ss_pref_volume_70", soundVolume);}
        case 90: { prefmenu.AddItem("ss_pref_volume_80", soundVolume);}
        case 100: { prefmenu.AddItem("ss_pref_volume_90", soundVolume);}
        default: { prefmenu.AddItem("ss_pref_volume_100", soundVolume);}
    }

    Format(soundLength, sizeof(soundLength), "%t%.1fs","ss menu length", g_fPlayerSoundLength[client]);
    switch (RoundToZero(g_fPlayerSoundLength[client]))
    {
        case 1: { prefmenu.AddItem("ss_pref_length_0", soundLength);}
        case 2: { prefmenu.AddItem("ss_pref_length_1", soundLength);}
        case 3: { prefmenu.AddItem("ss_pref_length_2", soundLength);}
        case 4: { prefmenu.AddItem("ss_pref_length_3", soundLength);}
        case 5: { prefmenu.AddItem("ss_pref_length_4", soundLength);}
        default: {
            Format(soundLength, sizeof(soundLength), "%tDisabled", "ss menu length");
            prefmenu.AddItem("ss_pref_length_5", soundLength);
        }
    }

    Format(soundPitch, sizeof(soundPitch), "%t%d%", "ss menu speed",g_iPlayerSoundPitch[client]);
    switch (g_iPlayerSoundPitch[client])
    {
        case 50: { prefmenu.AddItem("ss_pref_speed_150", soundPitch);}
        case 60: { prefmenu.AddItem("ss_pref_speed_50", soundPitch);}
        case 70: { prefmenu.AddItem("ss_pref_speed_60", soundPitch);}
        case 80: { prefmenu.AddItem("ss_pref_speed_70", soundPitch);}
        case 90: { prefmenu.AddItem("ss_pref_speed_80", soundPitch);}
        case 100: { prefmenu.AddItem("ss_pref_speed_90", soundPitch);}
        case 110: { prefmenu.AddItem("ss_pref_speed_100", soundPitch);}
        case 120: { prefmenu.AddItem("ss_pref_speed_110", soundPitch);}
        case 130: { prefmenu.AddItem("ss_pref_speed_120", soundPitch);}
        case 140: { prefmenu.AddItem("ss_pref_speed_130", soundPitch);}
        case 150: { prefmenu.AddItem("ss_pref_speed_140", soundPitch);}
        default: { prefmenu.AddItem("ss_pref_speed_100", soundPitch);}
    }
    prefmenu.ExitBackButton = true;
    prefmenu.Display(client, MENU_TIME_FOREVER);
}

public int SoundSettingHandler(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[32];
        GetMenuItem(prefmenu, item, preference, sizeof(preference));
        if(StrEqual(preference, "ss_pref_disable"))
        {
            g_bPlayerSoundDisabled[client] = !g_bPlayerSoundDisabled[client];
            SetClientCookie(client, g_hSoundToggleCookie, g_bPlayerSoundDisabled[client] ? "1" : "0");
        }
        if(StrContains(preference, "ss_pref_volume_") >= 0)
        {
            ReplaceString(preference, sizeof(preference), "ss_pref_volume_", "");
            int val = StringToInt(preference);
            g_fPlayerSoundVolume[client] = float(val) / 100;
            char buff[6];
            FloatToString(g_fPlayerSoundVolume[client], buff, sizeof(buff));
            SetClientCookie(client, g_hSoundVolumeCookie, buff);
        }
        if(StrContains(preference, "ss_pref_length_") >= 0)
        {
            ReplaceString(preference, sizeof(preference), "ss_pref_length_", "");
            int val = StringToInt(preference);
            if(val == 0) {
                g_fPlayerSoundLength[client] = -1.0;
            } else {
                g_fPlayerSoundLength[client] = float(val);
            }
            SetClientCookie(client, g_hSoundLengthCookie, preference);
        }
        if(StrContains(preference, "ss_pref_speed_") >= 0)
        {
            ReplaceString(preference, sizeof(preference), "ss_pref_speed_", "");
            int val = StringToInt(preference);
            g_iPlayerSoundPitch[client] = val;
            SetClientCookie(client, g_hSoundPitchCookie, preference);
        }
        DisplaySettingsMenu(client);
    }
    else if (actions == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCookieMenu(client);
        }
    }
    else if (actions == MenuAction_End)
    {
        CloseHandle(prefmenu);
    }
    return 0;
}

public void SoundSettingsMenu(int client, CookieMenuAction actions, any info, char[] buffer, int maxlen)
{
    if (actions == CookieMenuAction_DisplayOption)
    {
        Format(buffer, maxlen, "Saysounds");
    }
    
    if (actions == CookieMenuAction_SelectOption)
    {
        DisplaySettingsMenu(client);
    }
}



// ADMIN USER BAN/UNBAN SUGGESION

void DisplayBanSuggesion(int client, char[] search, bool invertSuggesion = false)
{
    SetGlobalTransTarget(client);
    Menu prefmenu = CreateMenu(BanHandler, MENU_ACTIONS_DEFAULT);

    char menuTitle[64];
    Format(menuTitle, sizeof(menuTitle), "%t", "ss admin ban menu");
    if(invertSuggesion) {
        Format(menuTitle, sizeof(menuTitle), "%t", "ss admin unban menu");
    }
    prefmenu.SetTitle(menuTitle);
    if(StrEqual(search, "")) {
        if(invertSuggesion) {
            for(int i = 1; i <= MaxClients; i++) {
                if(IsClientConnected(i) && !IsFakeClient(i)) {
                    if(g_bIsPlayerRestricted[i]) {
                        char buff[MAX_TARGET_LENGTH];
                        Format(buff, sizeof(buff), "%N", i);
                        prefmenu.AddItem(buff, buff);
                    }
                }
            }
        }
        else {
            for(int i = 1; i <= MaxClients; i++) {
                if(IsClientConnected(i) && !IsFakeClient(i)) {
                    if(!g_bIsPlayerRestricted[i]) {
                        char buff[MAX_TARGET_LENGTH];
                        Format(buff, sizeof(buff), "%N", i);
                        prefmenu.AddItem(buff, buff);
                    }
                }
            }
        }
    } else {
        char nBuff[MAX_NAME_LENGTH];
        if(invertSuggesion) {
            for(int i = 1; i <= MaxClients; i++) {
                if(IsClientConnected(i) && !IsFakeClient(i)) {
                    GetClientName(client, nBuff, sizeof(nBuff));
                    if(StrContains(nBuff, search) >= 0) {
                        if(g_bIsPlayerRestricted[i]) {
                            prefmenu.AddItem(nBuff, nBuff);
                        }
                    }
                }
            }
        } 
        else {
            for(int i = 1; i <= MaxClients; i++) {
                if(IsClientConnected(i) && !IsFakeClient(i)) {
                    GetClientName(client, nBuff, sizeof(nBuff));
                    if(StrContains(nBuff, search) >= 0) {
                        if(!g_bIsPlayerRestricted[i]) {
                            prefmenu.AddItem(nBuff, nBuff);
                        }
                    }
                }
            }
        }
    }

    
    prefmenu.Display(client, MENU_TIME_FOREVER);
}

public int BanHandler(Menu prefmenu, MenuAction actions, int client, int item)
{
    SetGlobalTransTarget(client);
    if (actions == MenuAction_Select)
    {
        char preference[MAX_TARGET_LENGTH];
        GetMenuItem(prefmenu, item, preference, sizeof(preference));

        char targetName[MAX_TARGET_LENGTH];
        int targetList[MAXPLAYERS];
        int targetCount;
        bool tn_is_ml;

        targetCount = ProcessTargetString(
            preference,
            client,
            targetList,
            MAXPLAYERS,
            0,
            targetName,
            sizeof(targetName),
            tn_is_ml
        );

        if(targetCount == 1) {
            g_bIsPlayerRestricted[targetList[0]] = !g_bIsPlayerRestricted[targetList[0]];
            SetClientCookie(client, g_hSoundRestrictionCookie, g_bIsPlayerRestricted[targetList[0]] ? "1" : "0");
            CPrintToChat(client, "%t%t", "ss prefix", g_bIsPlayerRestricted[targetList[0]] ? "ss user banned" : "ss user unbanned", preference);
        }

        
    }
    else if (actions == MenuAction_Cancel)
    {
        if (item == MenuCancel_ExitBack)
        {
            ShowCookieMenu(client);
        }
    }
    else if (actions == MenuAction_End)
    {
        CloseHandle(prefmenu);
    }
    return 0;
}