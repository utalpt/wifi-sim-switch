# WiFi SIM Switch

KernelSU module that gives your two SIMs one setup while you're on WiFi and another when you're not. Everything is configured from the module's **WebUI** in the KernelSU manager.

Built and tested on the Xiaomi 17 Ultra (nezha) running xiaomi.eu HyperOS 3, with KernelSU Next.

**Root solutions:**
- **KernelSU / KernelSU Next / APatch:** everything works, including the WebUI and the card banner.
- **Magisk:** the module, the status on the card and the Action button (Magisk v28+) work, but this hasn't been tested on Magisk yet. Magisk has no WebUI of its own, so use **WebUI X** or **MMRL** to open the settings. The banner isn't shown.

## Install

1. Download `wifisimoff-vX.Y.zip` from [Releases](https://github.com/utalpt/wifi-sim-switch/releases). GitHub's green "Code > Download ZIP" button won't install, because it puts everything inside a folder.
2. Install the zip from the KernelSU (or Magisk) manager and reboot.
3. Open the WebUI from the module card and set up the two profiles.

Updates show up in the manager: the module points to `update.json` in this repo.

## Profiles

There are two profiles, **On WiFi** and **Off WiFi**. Each one sets:

| Setting | Options |
|---|---|
| SIM1 / SIM2 | **Off**, **On** (its own network types), or On with a network type: 5G/4G/3G/2G, 4G/3G/2G, 4G + 2G, 4G only, 2G only |
| Use for: Data / Calls / SMS | Keep, or the SIM that gets it |
| Mobile data | Keep, On, Off |

When WiFi connects or drops, the module applies the whole profile. Example setups:

| Goal | On WiFi | Off WiFi |
|---|---|---|
| Calls SIM + data-only SIM | SIM1 On, SIM2 **Off**, calls/SMS SIM1, mobile data Off | Both On, data SIM2, calls/SMS SIM1, mobile data On |
| One SIM at a time | SIM1 On, SIM2 **Off**, calls/SMS SIM1 | SIM1 **Off**, SIM2 On, data/calls/SMS SIM2 |
| Save battery at home | SIM2 On · 2G only | SIM2 On (own networks) |

Rules:
- At least one SIM always stays on.
- Data, calls and SMS can't point at a SIM that is off in the same profile.
- A SIM that is **Off** has no calls, SMS or Wi-Fi calling.

## How a profile is applied

1. If a SIM has to be turned on or off and the profile manages mobile data, mobile data goes off first. That way no SIM briefly carries data it shouldn't.
2. SIMs that should be on are turned on, and the module waits for them to register (up to 60 s).
3. Network types are set. "On" puts back the SIM's own types if the module had changed them.
4. The data, calls and SMS SIM are set, retrying while a SIM registers. This happens before anything is turned off, so Android doesn't move them on its own.
5. SIMs that should be off are turned off. This is the same mechanism as "Turn off SIM" in Settings.
6. Mobile data is set as the profile says.

Mobile data is controlled **per SIM**, with Android's "carrier" data-enabled reason (`ITelephony.setDataEnabledForReason`), which sits beside the user's own switch. A SIM only gets data when every reason allows it.
- **Off:** mobile data is blocked on every SIM.
- **On:** only the data SIM can use mobile data, and the other is blocked.
- **During a switch:** every SIM is blocked from the start, and the data SIM is unblocked only at the end.

HyperOS keeps switching its global "Mobile data" toggle back on, and the "policy" reason is overwritten by NetworkPolicyManager. Nothing touches the carrier reason on a SIM without a carrier app. The module still checks the blocks every 3 cycles and puts them back if needed. The blocks aren't saved across reboots, so they're set again after every boot. Pausing or uninstalling removes them.

Profiles are declarative. Saving new settings applies the current profile again within one check interval, with no reboot.

## Status on the module card

The service writes its current state into the module's description, which the KernelSU manager shows on the module card:

- `✅ On WiFi · MEO on · NOS off · mobile data off`
- `✅ Off WiFi · MEO on · NOS on · data on NOS`
- `⏸️ Paused - both SIMs on`
- `⚠️ Blocked - confirm the ISub codes in the WebUI`

The card refreshes when you reopen the module list.

## WebUI

- **Now:** WiFi, which profile is applied, and both SIMs with carrier, network types, whether each one is on or off, and which handles calls, SMS and data.
- **Enabled:** pausing turns both SIMs back on with their own network types.
- **Only WiFi with internet:** WiFi that Android didn't validate as having internet (router down, captive portal) counts as off WiFi.
- **On WiFi / Off WiFi:** the two profiles, each with a summary line and warnings.
- **Advanced:** check interval, debounce, ISub transaction codes, and build confirmation.
- **Theme:** Default, Minimal, Acid, Synthwave, Toxic or Ultraviolet. Default and Minimal follow the system light/dark setting. The four neon themes use a terminal look with glow and load IBM Plex from Google Fonts, falling back to the system monospace font when offline. The choice is saved in `/data/adb/wifisimoff/theme`.
- **Log:** the last 80 lines.

## ROM-specific: ISub transaction codes

HyperOS refuses `cmd phone disable-physical-subscription`, even as root. So turning SIMs off/on and choosing the data/calls/SMS SIM go through the `isub` service with `service call`. Transaction codes change between builds, and a wrong code calls a different system method. Because of that:

- **Automatic detection (default):** `isubcodes.dex` is a small helper whose source is `IsubCodes.java`, included. It runs with `app_process` and reads `ISub$Stub` and `ITelephony$Stub` `TRANSACTION_*` straight from the running ROM by reflection. It also checks each method's signature, for example that `setUiccApplicationsEnabled` takes `(boolean, int)`. If all six match, those codes are used. This works on any HyperOS variant (xiaomi.eu, CN, Global, EEA) and other ROMs, with no setup. The result is cached per `framework.jar`.
- **Fallback:** if detection fails, the module uses a built-in list of known `framework.jar` checksums. Failing that, it uses codes you entered and confirmed in the WebUI (Advanced > Confirm codes). Otherwise it shows **Blocked**.
- A build is identified by the checksum of `framework.jar`, not by `ro.build.fingerprint`, which root modules often spoof.
- Network-type-only profiles need no codes.

To run the helper by hand: `su -c "CLASSPATH=/data/adb/modules/wifisimoff/isubcodes.dex app_process / IsubCodes"`

Known builds (`KNOWN_BUILDS` in `common.sh`):

| framework.jar (cksum-size) | ROM |
|---|---|
| `3259115906-43485600` | xiaomi.eu HyperOS 3 OS3.0.309.0, Xiaomi 17 Ultra (nezha) |

Codes for that build:

| Code | Method |
|---|---|
| 31 | `setDefaultDataSubId(int subId)` |
| 34 | `setDefaultVoiceSubId(int subId)` |
| 37 | `setDefaultSmsSubId(int subId)` |
| 46 | `setUiccApplicationsEnabled(boolean enabled, int subId)` |
| 112 | `ITelephony.setDataEnabledForReason(int subId, int reason, boolean enabled, String pkg)` |
| 113 | `ITelephony.isDataEnabledForReason(int subId, int reason)` |

To check a build: `su -c cksum /system/framework/framework.jar`. To find the codes on another build, look in `/system/framework/framework.jar`: class `com.android.internal.telephony.ISub$Stub`, fields `TRANSACTION_<method>`. Or send me your `framework.jar`.

All status reads use `dumpsys isub` and don't depend on these codes.

## Roaming

The voice SIM should never carry data abroad. Set international data roaming to Never (Settings > SIM > Data roaming). The HyperOS national roaming toggle is global and is written to whichever SIM is the data SIM at that moment. To set it on one subscription (code for this build): `su -c service call isub 16 i32 0 i32 <subId>`. Voice and SMS roaming are not affected.

## Files

| Path | Contents |
|---|---|
| `/data/adb/wifisimoff/config.sh` | Settings saved by the WebUI (`KEY=value`, never executed) |
| `/data/adb/wifisimoff/fingerprint` | framework.jar checksum the user confirmed the codes for |
| `/data/adb/wifisimoff/fwid` | framework.jar checksum, computed once per boot |
| `/data/adb/wifisimoff/autocodes2` | Codes detected for that framework.jar (empty if detection failed) |
| `/data/adb/wifisimoff/subid_<slot>` | subId per slot (needed while a SIM is off) |
| `/data/adb/wifisimoff/orig_mask_<slot>` | A SIM's own network types, saved before the module first changes them |
| `/data/adb/wifisimoff/runtime` | Service state shown in the WebUI |
| `/data/adb/wifisimoff/theme` | WebUI theme |
| `/data/adb/modules/wifisimoff/log.txt` | Log, cleared on each boot |

Settings and state live outside the module folder, so they survive updates. v3 settings are converted to profiles automatically on the first boot.

## Action button

Pauses or resumes the module, and returns at once. The running service does the work within one check interval. Pausing turns both SIMs back on with their own network types and lifts the mobile data blocks. Resuming applies the profile for the current WiFi state. The same switch is in the WebUI (Enabled).

## Uninstalling

A turned-off SIM stays off across reboots. On removal, `uninstall.sh` turns both SIMs back on after the next boot completes and deletes `/data/adb/wifisimoff`. To be safe, pause the module in the WebUI before removing it.

## Known limitations

- **No mobile data for about 5-30 s** when a profile turns a SIM on, while it registers.
- **Swapping the SIM cards between slots** means checking the profiles again, since they refer to slots.

## Recovery (manual)

```
su -c service call isub 46 i32 1 i32 <subId>   # turn a SIM back on
su -c service call isub 31 i32 <subId>         # data SIM (once registered)
su -c service call isub 34 i32 <subId>         # calls SIM
su -c service call isub 37 i32 <subId>         # SMS SIM
su -c svc data enable
```

## Building and releasing

`isubcodes.dex` isn't committed. The release workflow compiles it from `IsubCodes.java` (javac + d8), so the binary in each release comes from the public source.

To release a new version:
1. Bump `version` and `versionCode` in `module.prop`.
2. Update `update.json` (version, versionCode, zipUrl) and add a section for the version to `CHANGELOG.md`.
3. Commit, then push a tag with the same name as the version (for example `v6.8`). The workflow checks that the tag matches `module.prop`, builds the zip and publishes the release.

## License

GPL-3.0. See [LICENSE](LICENSE).
