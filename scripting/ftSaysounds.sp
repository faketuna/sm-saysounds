#include <sourcemod>
#include <sdktools>
#include <sdktools_sound>
#include <clientprefs>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.5"

#define SAYSOUND_FLAG_DOWNLOAD        (1 << 0)
#define SAYSOUND_FLAG_CUSTOMVOLUME    (1 << 1)
#define SAYSOUND_FLAG_CUSTOMLENGTH    (1 << 2)

#define SAYSOUND_SOUND_NAME_SIZE 64

#define SAYSOUND_PITCH_MAX 200
#define SAYSOUND_PITCH_MIN 50

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
bool g_fPlayerSoundDisabled[MAXPLAYERS+1];
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


public Plugin myinfo = 
{
    name = "Say Sounds FT",
    author = "faketuna",
    description = "Plays sound files",
    version = PLUGIN_VERSION,
    url = "https://short.f2a.dev/s/github"
};

public void OnPluginStart()
{
    g_cSaySoundsEnabled            = CreateConVar("sm_saysounds_enable", "1", "Toggles say sounds globaly", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cSaySoundsInterval        = CreateConVar("sm_saysounds_interval", "2.0", "Time between each sound to trigger per player. 0.0 to disable", FCVAR_NONE, true, 0.0, true, 30.0);
    g_cSaySoundsCancelChat        = CreateConVar("sm_saysounds_cancel", "1", "Cancel the chat message when match with saysound.", FCVAR_NONE, true, 0.0, true, 1.0);

    g_cSaySoundsEnabled.AddChangeHook(OnCvarsChanged);
    g_cSaySoundsInterval.AddChangeHook(OnCvarsChanged);
    g_cSaySoundsCancelChat.AddChangeHook(OnCvarsChanged);

    g_hSoundVolumeCookie            = RegClientCookie("cookie_ss_volume", "Saysound volume", CookieAccess_Protected);
    g_hSoundLengthCookie            = RegClientCookie("cookie_ss_length", "Saysound length", CookieAccess_Protected);
    g_hSoundPitchCookie             = RegClientCookie("cookie_ss_pitch", "Saysound pitch", CookieAccess_Protected);
    g_hSoundRestrictionCookie       = RegClientCookie("cookie_ss_restriction", "Saysound restriction", CookieAccess_Protected);
    g_hSoundRestrictionTimeCookie   = RegClientCookie("cookie_ss_restriction_time", "Saysound restriction time", CookieAccess_Protected);
    g_hSoundToggleCookie            = RegClientCookie("cookie_ss_toggle", "Saysound toggle", CookieAccess_Protected);

    RegConsoleCmd("sm_ss_volume", CommandSSVolume, "Set say sounds volume per player.");
    RegConsoleCmd("sm_ss_speed", CommandSSSpeed, "Set say sounds volume per player.");

    AddCommandListener(CommandListenerSay, "say");
    AddCommandListener(CommandListenerSay, "say2");
    AddCommandListener(CommandListenerSay, "say_team");
    ParseConfig();

    for(int i = 1; i <= MaxClients; i++) {
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
    } else {
        g_fPlayerSoundLength[client] = 0.0;
        SetClientCookie(client, g_hSoundLengthCookie, "0.0");
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
        g_fPlayerSoundDisabled[client] = view_as<bool>(StringToInt(cookieValue));
    } else {
        g_fPlayerSoundDisabled[client] = false;
        SetClientCookie(client, g_hSoundToggleCookie, "false");
    }
}

public void OnConfigsExecuted() {
    SyncConVarValues();
}

public void OnMapStart() {
    PrecacheSounds();
}

public void SyncConVarValues() {
    g_bPluginEnabled        = GetConVarBool(g_cSaySoundsEnabled);
    g_bSaySoundsCancelChat  = GetConVarBool(g_cSaySoundsInterval);
    g_fSaySoundsInterval    = GetConVarFloat(g_cSaySoundsInterval);
}

public void OnCvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    SyncConVarValues();
}

public Action CommandListenerSay(int client, const char[] command, int argc) {
    if(client != 0) {
        if(!g_bPluginEnabled) {
            return Plugin_Continue;
        }
        if(g_bIsPlayerRestricted[client]) {
            return Plugin_Continue;
        }
        char arg1[32];
        GetCmdArg(1, arg1, sizeof(arg1));

        char cBuff[4][6];
        int cArgs = ExplodeString(arg1, " ", cBuff, 4, 6);

        //TODO()
        // Add check arg is valid saysound
        int si = GetSaySoundIndex(cBuff[0]);
        if(si == -1) {
            return Plugin_Continue;
        }
        
        switch(cArgs) {
            case 1: {
                TrySaySound(client, cBuff[0], si, -1, -1.0);
                if(g_bSaySoundsCancelChat) {
                    return Plugin_Handled;
                }
            }
            case 2: {
                if(StrContains(cBuff[1], "@") != -1) {
                    int p = ProcessPitch(cBuff[1]);

                    TrySaySound(client, cBuff[0], si, p, -1.0);

                    if(g_bSaySoundsCancelChat) {
                        return Plugin_Handled;
                    }
                }
                else if(StrContains(cBuff[1], "%") != -1) {
                    float l = ProcessLength(cBuff[1]);

                    TrySaySound(client, cBuff[0], si, 100, l);

                    if(g_bSaySoundsCancelChat) {
                        return Plugin_Handled;
                    }
                }
            }
            case 3: {
                int p = 100;
                float l = 0.0;
                if(StrContains(cBuff[1], "@") != -1) {
                    p = ProcessPitch(cBuff[1]);
                    l = ProcessLength(cBuff[2]);
                } else {
                    p = ProcessPitch(cBuff[2]);
                    l = ProcessLength(cBuff[1]);
                }
                TrySaySound(client, cBuff[0], si, p, l);
                if(g_bSaySoundsCancelChat) {
                    return Plugin_Handled;
                }
            }
            default: {return Plugin_Continue;}
        }
    }
    return Plugin_Continue;
}

void TrySaySound(int client, char[] soundName, int saySoundIndex, int pitch = 100, float length = 0.0) {
    if(pitch == -1) {
        pitch = g_iPlayerSoundPitch[client];
    }
    if(length == -1.0) {
        length == g_fPlayerSoundLength[client];
    }
    char fileLocation[PLATFORM_MAX_PATH];

    GetArrayString(g_hPath, saySoundIndex, fileLocation, sizeof(fileLocation));


    for(int i = 1; i <= MaxClients; i++) {
        if(!IsClientInGame(i) || g_fPlayerSoundDisabled[i]) {
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
    ReplaceString(ag, sizeof(ag), "@", "");

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
    ReplaceString(ag, sizeof(ag), "%", "");

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
        if(StrEqual(buff, soundName)) {
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

    char soundListFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM,soundListFile,sizeof(soundListFile),"configs/ftSaysounds.cfg");
    if(!FileExists(soundListFile)) {
        PrintToServer("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nFILE NOT FOUND");
        SetFailState("ftSaysounds.cfg failed to parse! Reason: File doesn't exist!");
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

                Format(fileLocation, sizeof(fileLocation), "*%s", fileLocation);
                PushArrayString(g_hPath, fileLocation);
                PushArrayCell(g_hLength, duration);
                PushArrayCell(g_hVolume, volume);
                PushArrayCell(g_hFlags, flags);
                PushArrayString(g_hSoundName, soundName);
            }
        } while(KvGotoNextKey(listFile));
    } else {
        PrintToServer("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nSUBKEY NOT FOUND");
        SetFailState("ftSaysounds.cfg failed to parse! Reason: No subkeys found!");
    }
}

void PrecacheSounds() {
    char soundFile[PLATFORM_MAX_PATH], buffer[PLATFORM_MAX_PATH];
    int flags;

    for(int i = GetArraySize(g_hPath) - 1; i >= 0; i--) {
        GetArrayString(g_hPath, i, soundFile, sizeof(soundFile));
        flags = GetArrayCell(g_hFlags, i);
        AddToStringTable(FindStringTable("soundprecache"), soundFile);

        if(flags & SAYSOUND_FLAG_DOWNLOAD) {
            FormatEx(buffer, sizeof(buffer), "sound/%s", soundFile);
            AddFileToDownloadsTable(buffer);
        }
    }
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

public Action CommandSSVolume(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(!IsOnlyDicimal(arg1)) {
            CPrintToChat(client, "TODO() Invalid arguments.");
            return Plugin_Handled;
        }

        g_fPlayerSoundVolume[client] = float(StringToInt(arg1)) / 100;
        CPrintToChat(client, "TODO() Success to set volume");
        return Plugin_Handled;
    }

    // TODO Pref menu
    return Plugin_Handled;
}

public Action CommandSSSpeed(int client, int args) {
    if(args >= 1) {
        char arg1[4];
        GetCmdArg(1, arg1, sizeof(arg1));
        if(!IsOnlyDicimal(arg1)) {
            CPrintToChat(client, "TODO() Invalid arguments.");
            return Plugin_Handled;
        }

        g_iPlayerSoundPitch[client] = StringToInt(arg1);
        SetClientCookie(client, g_hSoundPitchCookie, arg1);
        CPrintToChat(client, "TODO() Success to set speed");
        return Plugin_Handled;
    }

    // TODO Pref menu
    return Plugin_Handled;
}