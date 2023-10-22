# Saysounds (ft)

# Caution

### This plugin requires [multicolors](https://github.com/Bara/Multi-Colors) to compile!!!

### This plugin tested in CS:GO and L4D2. Other source engine game is not tested but may work.

# Installation

1. Download file as zip from github repo.
2. Extract files.
3. Move `configs` `plugins` `translations` folder to your sourcemod folder. `scripting` is are optional.
4. Modify saysounds.cfg.
5. Done.

# Feature

### Key feature

* Dynamically precaches a sound. You can add  6000+ saysounds (Tested in Lupercalia CS:GO MG servver)
* You can play saysounds as normal or with custom speed/pitch and custom length.
* Formatted message.

### Syntax

* `<sound>`
* `<sound> @<speed>`
* `<sound> %<length>`
* `<sound> @<speed> %<length>`
* `<sound> %<length> @<speed>`

* Sound: Yeah same as other saysounds plugin. e.g. `test` in chat
* speed/pitch: use `@` and specify speed. e.g. `@120`
* length: use `%` and specify sound length in seconds. e.g. `%0.5`

 So we combined the above, will become like this.
 `test @120 %0.5`


### User commands

* `!saysounds`, `!saysound`, `!ssmenu`, `!ss_menu` - Opens settings menu.
* `!ss_volume <0~100>`- Set the saysound volume. If no argument, will work as !ssmenu
* `!ss_speed <50~200>`(You can change max and min range from source file) - Set the saysound speed/pitch. If no argument, will work as !ssmenu
* `!ss_length <0~>` - Set the saysound length in seconds. If no argument, will work as !ssmenu
* `!ss_toggle` - Toggle saysounds.
* `!ss_list` `!sslist` - Show all of saysounds provided in server.
* `!ss_search <string>` `!sss <string>` - Search saysounds.

### Admin commands

* `!ss_ban <player name>` - Ban player from using saysounds. - If no argument, will show a player list menu.
* `!ss_unban <player name>` - Unban player from using saysounds. - If no argument, will show a player list menu.

### ConVar

* `sm_saysounds_enable <0/1>` - Toggle saysounds globally
* `sm_saysounds_interval <seconds>` - Saysounds cooldown per player.
* `sm_saysounds_format_chat <0/1>` - Cancel original message and send formatted message.

# Known issue

* When player use `%<time>` syntax. It will stop all same sound when timer fired. (e.g. If someone use `test %0.1` after someone use `test` with 5 seconds long sound, It stops all test sound after timer fired)

# Todo

* Add temporary ban. (Currently we can only ban permanent)
* Add self saysounds mute.

# Reference plugin from

Thanks for helping

* Parsing the config file.
* Sound list command idea.

[Saysounds (Redux)](https://forums.alliedmods.net/showthread.php?p=2240969)

[Say Sounds](https://forums.alliedmods.net/showthread.php?p=496226)

# Special thanks

### Tester 
* kur4yam1
* valni_nyas
* omoi
* きゃるる
* Lupercalia CS:GO MG server