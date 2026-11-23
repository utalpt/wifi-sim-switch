# Shared code - sourced by service.sh, status.sh, action.sh and uninstall.sh

STATE=${WSS_STATE:-/data/adb/wifisimoff}   # survives module updates
CONF=$STATE/config.sh                      # written by the WebUI
RUNTIME=$STATE/runtime                     # current service state, read by the WebUI
LOG=$MODDIR/log.txt
mkdir -p "$STATE"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ---------------------------------------------------------------- config
# Two profiles: W = on WiFi, C = off WiFi. Per profile:
#   SIM0 / SIM1  OFF | ORIG (on, its own network types) | ALL | 4G3G2G | 4G2G | 4G | 2G
#   DATA / VOICE / SMS   keep | 0 | 1   (slot that gets the default)
#   MDATA        keep | 1 | 0           (mobile data switch)
PROFILE_KEYS="SIM0 SIM1 DATA VOICE SMS MDATA"
GLOBAL_KEYS="ENABLED REQUIRE_INTERNET INTERVAL DEBOUNCE TX_SET_DATA TX_SET_UICC TX_SET_VOICE TX_SET_SMS TX_DATA_REASON TX_IS_DATA_REASON"
CONF_KEYS="$GLOBAL_KEYS"
for p in W C; do for k in $PROFILE_KEYS; do CONF_KEYS="$CONF_KEYS ${p}_$k"; done; done
LEGACY_KEYS="MODE SLOT WIFI_NET CELL_NET MANAGE_DATA DATA_SIM VOICE_SIM SMS_SIM"   # v3

load_config() {
  ENABLED=1
  REQUIRE_INTERNET=0   # only count WiFi that Android validated as having internet
  INTERVAL=5           # seconds between WiFi checks
  DEBOUNCE=8           # seconds a change must hold before acting
  TX_SET_DATA=31       # ISub.setDefaultDataSubId(int)                - ROM specific
  TX_SET_UICC=46       # ISub.setUiccApplicationsEnabled(boolean,int) - ROM specific
  TX_SET_VOICE=34      # ISub.setDefaultVoiceSubId(int)               - ROM specific
  TX_SET_SMS=37        # ISub.setDefaultSmsSubId(int)                 - ROM specific
  TX_DATA_REASON=112   # ITelephony.setDataEnabledForReason(int,int,boolean,String) - ROM specific
  TX_IS_DATA_REASON=113 # ITelephony.isDataEnabledForReason(int,int)   - ROM specific
  for p in W C; do
    eval "${p}_SIM0=ORIG ${p}_SIM1=ORIG ${p}_DATA=keep ${p}_VOICE=keep ${p}_SMS=keep ${p}_MDATA=keep"
  done
  for k in $LEGACY_KEYS; do eval "$k="; done
  HAS_PROFILES=""

  # Parse KEY=value lines without executing anything
  if [ -f "$CONF" ]; then
    while IFS='=' read -r k v; do
      case " $CONF_KEYS $LEGACY_KEYS " in *" $k "*) eval "$k=\$v" ;; *) continue ;; esac
      case "$k" in W_*|C_*) HAS_PROFILES=1 ;; esac
    done < "$CONF"
  fi
  [ -z "$HAS_PROFILES" ] && [ -n "$MODE" ] && migrate_v3

  # Sanitize
  case "$ENABLED"          in 0|1) ;; *) ENABLED=1 ;; esac
  case "$REQUIRE_INTERNET" in 0|1) ;; *) REQUIRE_INTERNET=0 ;; esac
  for k in INTERVAL DEBOUNCE TX_SET_DATA TX_SET_UICC TX_SET_VOICE TX_SET_SMS TX_DATA_REASON TX_IS_DATA_REASON; do
    eval "v=\$$k"
    case "$v" in ''|*[!0-9]*) eval "$k=" ;; esac
  done
  [ -n "$INTERVAL" ] && [ "$INTERVAL" -ge 2 ] || INTERVAL=5
  [ -n "$DEBOUNCE" ] || DEBOUNCE=8
  [ -n "$TX_SET_DATA" ]  || TX_SET_DATA=31
  [ -n "$TX_SET_UICC" ]  || TX_SET_UICC=46
  [ -n "$TX_SET_VOICE" ] || TX_SET_VOICE=34
  [ -n "$TX_SET_SMS" ]   || TX_SET_SMS=37
  [ -n "$TX_DATA_REASON" ] || TX_DATA_REASON=112
  [ -n "$TX_IS_DATA_REASON" ] || TX_IS_DATA_REASON=113
  for p in W C; do
    for k in SIM0 SIM1; do
      eval "v=\$${p}_$k"
      case "$v" in OFF|ORIG|ALL|4G3G2G|4G2G|4G|2G) ;; *) eval "${p}_$k=ORIG" ;; esac
    done
    # Never turn both SIMs off
    eval "[ \"\$${p}_SIM0\" = OFF ] && [ \"\$${p}_SIM1\" = OFF ] && ${p}_SIM0=ORIG"
    for k in DATA VOICE SMS; do
      eval "v=\$${p}_$k"
      case "$v" in
        0|1) eval "[ \"\$${p}_SIM$v\" = OFF ] && ${p}_$k=keep" ;;   # can't point at a SIM that's off
        *) eval "${p}_$k=keep" ;;
      esac
    done
    eval "v=\$${p}_MDATA"
    case "$v" in 0|1|keep) ;; *) eval "${p}_MDATA=keep" ;; esac
  done
  use_auto_codes
}

# v3 single-SIM config -> profiles
migrate_v3() {
  s=${SLOT:-1}
  case "$s" in 0|1) ;; *) s=1 ;; esac
  if [ "$MODE" = network ]; then
    eval "W_SIM$s=\${WIFI_NET:-2G}; C_SIM$s=\${CELL_NET:-ALL}"
  else
    eval "W_SIM$s=OFF"
    if [ "${MANAGE_DATA:-1}" = 1 ]; then W_MDATA=0; C_MDATA=1; fi
    C_DATA=$(legacy_target "$DATA_SIM" "prev_data_$s")
    C_VOICE=$(legacy_target "$VOICE_SIM" "prev_voice_$s")
    C_SMS=$(legacy_target "$SMS_SIM" "prev_sms_$s")
    o=$((1 - s))
    # Defaults while the SIM is off can only go to the other one
    [ "$C_VOICE" != keep ] && W_VOICE=$o
    [ "$C_SMS" != keep ] && W_SMS=$o
  fi
}
legacy_target() {   # v3 auto|0|1 (+ remembered sub) -> slot or keep
  case "$1" in
    0|1) echo "$1" ;;
    *) sub=$(cat "$STATE/$2" 2>/dev/null)
       for sl in 0 1; do [ -n "$sub" ] && [ "$(cat "$STATE/subid_$sl" 2>/dev/null)" = "$sub" ] && { echo $sl; return; }; done
       echo keep ;;
  esac
}

conf_sum() { cksum "$CONF" 2>/dev/null; }
cfg_dump() { for k in $CONF_KEYS; do eval "echo \"$k=\$$k\""; done; }
profile_desc() {
  eval "echo \"SIM1=\$${1}_SIM0 SIM2=\$${1}_SIM1 data=\$${1}_DATA calls=\$${1}_VOICE sms=\$${1}_SMS mobiledata=\$${1}_MDATA\""
}

# Does the config need the ROM-specific ISub codes? (turning SIMs off/on, setting defaults)
needs_codes() {
  for p in W C; do
    eval "[ \"\$${p}_SIM0\" = OFF ] || [ \"\$${p}_SIM1\" = OFF ]" && return 0
    for k in DATA VOICE SMS MDATA; do eval "[ \"\$${p}_$k\" != keep ]" && return 0; done
  done
  # A SIM that is off right now also needs the codes to come back on
  [ -z "$(slot_sub 0)" ] || [ -z "$(slot_sub 1)" ]
}

# Allowed-network-types bitmasks (binary, as taken by cmd phone)
mask_of() {
  case "$1" in
    ALL)    echo 11011101001110000111 ;;  # 5G + 4G + 3G + 2G
    4G3G2G) echo 1011101001110000111 ;;   # 4G + 3G + 2G (HyperOS "4G")
    4G2G)   echo 1001001000000000011 ;;   # 4G + 2G
    4G)     echo 1000001000000000000 ;;   # 4G only
    2G)     echo 1000000000000011 ;;      # 2G only
  esac
}

# "GPRS|EDGE|LTE|..." (cmd phone get output) -> binary bitmask (bit = network type - 1)
names_to_mask() {
  case "$1" in *[!01]*) ;; '') return 1 ;; *) echo "$1"; return 0 ;; esac
  nm_sum=0
  for n in $(echo "$1" | tr '|' ' '); do
    case "$n" in
      GPRS) b=0 ;; EDGE) b=1 ;; UMTS) b=2 ;; CDMA) b=3 ;; EVDO_0) b=4 ;; EVDO_A) b=5 ;;
      1xRTT) b=6 ;; HSDPA) b=7 ;; HSUPA) b=8 ;; HSPA) b=9 ;; IDEN) b=10 ;; EVDO_B) b=11 ;;
      LTE) b=12 ;; EHRPD|eHRPD) b=13 ;; HSPA+|HSPAP) b=14 ;; GSM) b=15 ;; TD_SCDMA) b=16 ;;
      IWLAN) b=17 ;; LTE_CA) b=18 ;; NR) b=19 ;; *) continue ;;
    esac
    nm_sum=$((nm_sum | (1 << b)))
  done
  [ "$nm_sum" -gt 0 ] || return 1
  out=""
  while [ "$nm_sum" -gt 0 ]; do out="$((nm_sum & 1))$out"; nm_sum=$((nm_sum >> 1)); done
  echo "$out"
}

# ---------------------------------------------------------------- WiFi
wifi_up() {
  if [ "$REQUIRE_INTERNET" = 1 ]; then
    conn_dump | grep -E 'NetworkAgentInfo.*WIFI' \
      | grep -qE '[&: ]VALIDATED([& ]|$)'
    return
  fi
  cmd wifi status 2>/dev/null | grep -q "Wifi is connected" && return 0
  ip route show table all 2>/dev/null | grep -q "^default.*dev wlan0"
}
state() { wifi_up && echo wifi || echo cell; }

# ---------------------------------------------------------------- telephony (read-only)
# status.sh fills ISUB_CACHE / CONN_CACHE once, so one WebUI poll runs each dumpsys a single
# time instead of ~15 times. The service never sets them and always reads live state.
isub_dump()    { if [ -n "$ISUB_CACHE" ]; then printf '%s\n' "$ISUB_CACHE"; else dumpsys isub 2>/dev/null; fi; }
conn_dump()    { if [ -n "$CONN_CACHE" ]; then printf '%s\n' "$CONN_CACHE"; else dumpsys connectivity 2>/dev/null; fi; }
get_data_sub() { isub_dump | grep -oE 'defaultDataSubId=-?[0-9]+' | head -1 | cut -d= -f2; }
get_voice_sub(){ isub_dump | grep -oE 'defaultVoiceSubId=-?[0-9]+' | head -1 | cut -d= -f2; }
get_sms_sub()  { isub_dump | grep -oE 'defaultSmsSubId=-?[0-9]+' | head -1 | cut -d= -f2; }
slot_sub() {   # active subscription in a slot (empty while the SIM is off)
  isub_dump | grep -oE "Logical SIM slot $1: subId=[0-9]+" | head -1 | grep -oE '[0-9]+$'
}
slot_sub_any() {   # subscription record for a slot
  isub_dump | grep -oE "id=[0-9]+ iccId=[^ ]+ simSlotIndex=$1 " | head -1 \
    | grep -oE '^id=[0-9]+' | cut -d= -f2
}
sub_of_slot() {   # subId in a slot, also while that SIM is off (cached)
  s=$(slot_sub "$1")
  case "$s" in ''|-*) s=$(slot_sub_any "$1") ;; esac
  case "$s" in ''|-*) [ -s "$STATE/subid_$1" ] && s=$(cat "$STATE/subid_$1") ;; esac
  case "$s" in ''|-*) return 1 ;; esac
  echo "$s" > "$STATE/subid_$1"
  echo "$s"
}

# ---------------------------------------------------------------- ISub calls (ROM specific)
set_uicc() { service call isub "$TX_SET_UICC" i32 "$1" i32 "$2"; }

# The ISub calls go by transaction code, and the codes differ between builds - a wrong code
# calls a different method. They only run on a known build or one the user confirmed.
# A build is identified by the checksum of framework.jar (where the codes live), not by
# ro.build.fingerprint, which root modules often spoof.
FRAMEWORK=${WSS_FRAMEWORK:-/system/framework/framework.jar}
FPFILE=$STATE/fingerprint                  # framework id the user confirmed

# Known framework.jar checksums and their codes: <cksum>-<size>:DATA,UICC,VOICE,SMS,DATA_REASON,IS_DATA_REASON
KNOWN_BUILDS="
3259115906-43485600:31,46,34,37,112,113
"
# ^ xiaomi.eu HyperOS 3 OS3.0.309.0 (nezha, Xiaomi 17 Ultra)

fw_id() {   # checksum of framework.jar, computed once per boot
  b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  if [ -s "$STATE/fwid" ] && [ "$(sed -n 1p "$STATE/fwid")" = "$b" ]; then sed -n 2p "$STATE/fwid"; return; fi
  id=$(cksum "$FRAMEWORK" 2>/dev/null | cut -d' ' -f1,2 | tr ' ' -)
  [ -n "$id" ] && printf '%s\n%s\n' "$b" "$id" > "$STATE/fwid"
  echo "$id"
}
known_codes() {
  for e in $KNOWN_BUILDS; do [ "${e%%:*}" = "$1" ] && { echo "${e#*:}"; return 0; }; done
  return 1
}
# Read the codes from the running ROM itself: a small helper (isubcodes.dex) run with
# app_process looks up ISub$Stub.TRANSACTION_* by reflection and checks each method's
# signature. Cached per framework.jar; an empty result means detection failed.
auto_codes() {
  id=$(fw_id)
  [ -n "$id" ] || return 1
  if [ -s "$STATE/autocodes2" ] && [ "$(sed -n 1p "$STATE/autocodes2")" = "$id" ]; then
    v=$(sed -n 2p "$STATE/autocodes2"); [ -n "$v" ] && echo "$v"; [ -n "$v" ]; return
  fi
  [ -f "$MODDIR/isubcodes.dex" ] || return 1
  out=$(CLASSPATH="$MODDIR/isubcodes.dex" app_process / IsubCodes 2>/dev/null)
  v=""
  for m in setDefaultDataSubId setUiccApplicationsEnabled setDefaultVoiceSubId setDefaultSmsSubId setDataEnabledForReason isDataEnabledForReason; do
    c=$(echo "$out" | grep -E "^$m=[0-9]+ .* ok$" | head -1 | sed -E "s/^$m=([0-9]+) .*/\1/")
    if [ -z "$c" ] || [ "$c" -le 0 ]; then v=""; break; fi
    v="${v:+$v,}$c"
  done
  printf '%s\n%s\n' "$id" "$v" > "$STATE/autocodes2"
  [ -n "$v" ] && echo "$v"
}
# Use auto-detected codes when available (called at the end of load_config)
use_auto_codes() {
  AUTO_CODES=""
  v=$(auto_codes) || return 0
  IFS=, read -r TX_SET_DATA TX_SET_UICC TX_SET_VOICE TX_SET_SMS TX_DATA_REASON TX_IS_DATA_REASON <<EOF
$v
EOF
  AUTO_CODES=1
}

build_ok() {
  [ "$AUTO_CODES" = 1 ] && return 0
  id=$(fw_id)
  [ -n "$id" ] || return 1
  kc=$(known_codes "$id") && [ "$kc" = "$TX_SET_DATA,$TX_SET_UICC,$TX_SET_VOICE,$TX_SET_SMS,$TX_DATA_REASON,$TX_IS_DATA_REASON" ] && return 0
  [ -f "$FPFILE" ] || return 1
  saved=$(cat "$FPFILE")
  [ "$saved" = "$id" ] && return 0
  # v4.3 and older saved ro.build.fingerprint - upgrade it if it still matches
  if [ "$saved" = "$(getprop ro.build.fingerprint)" ]; then echo "$id" > "$FPFILE"; return 0; fi
  return 1
}

# ---------------------------------------------------------------- network types
net_set() {   # <slot> <preset>
  cur=$(names_to_mask "$(cmd phone get-allowed-network-types-for-users -s "$1" 2>/dev/null | head -1)")
  # Remember the SIM's own network types the first time the module changes them
  [ -s "$STATE/orig_mask_$1" ] || { [ -n "$cur" ] && echo "$cur" > "$STATE/orig_mask_$1"; }
  m=$(mask_of "$2")
  [ "$cur" = "$m" ] && return 0
  log "SIM$(($1 + 1)) networks -> $2: $(cmd phone set-allowed-network-types-for-users -s "$1" "$m" 2>&1 | tr -d '\n')"
}
net_restore() {   # <slot> - back to the SIM's own network types
  f=$STATE/orig_mask_$1
  [ -s "$f" ] || return 0
  cur=$(names_to_mask "$(cmd phone get-allowed-network-types-for-users -s "$1" 2>/dev/null | head -1)")
  [ "$cur" = "$(cat "$f")" ] || \
    log "SIM$(($1 + 1)) original networks restored: $(cmd phone set-allowed-network-types-for-users -s "$1" "$(cat "$f")" 2>&1 | tr -d '\n')"
  rm -f "$f"
}

# ---------------------------------------------------------------- defaults
# set_default <label> <tx code> <subId> <getter> - retries while a SIM registers
set_default() {
  case "$3" in ''|-*|0) return 0 ;; esac
  [ "$($4)" = "$3" ] && return 0
  sd_i=0
  while [ "$($4)" != "$3" ]; do
    if [ $sd_i -ge 60 ]; then log "WARN: default $1 SIM is $($4), expected $3"; return 1; fi
    service call isub "$2" i32 "$3" >/dev/null
    sleep 3; sd_i=$((sd_i+3))
  done
  log "default $1 SIM -> sub $3"
}

# ---------------------------------------------------------------- mobile data, per SIM
# Mobile data is blocked per SIM with Android's "carrier" data-enabled reason, which sits
# beside the user's own switch: a SIM only gets data if every reason allows it. HyperOS
# keeps re-enabling its global mobile data switch, and the "policy" reason is overwritten
# by NetworkPolicyManager, but nothing on a SIM without a carrier app touches this one.
# It isn't persisted, so it's set again after every boot.
CARRIER_REASON=2
data_allowed() {   # <sub> -> 00000001 allowed, 00000000 blocked
  service call phone "$TX_IS_DATA_REASON" i32 "$1" i32 $CARRIER_REASON 2>/dev/null | grep -oE '[0-9a-f]{8}' | sed -n 2p
}
set_data_allowed() {   # <sub> <1|0>
  service call phone "$TX_DATA_REASON" i32 "$1" i32 $CARRIER_REASON i32 "$2" s16 com.android.shell >/dev/null 2>&1
}
active_subs() { for sl in 0 1; do slot_sub $sl; done; }
# dm=0: no SIM may use mobile data. dm=1: only the data SIM may.
data_policy() {
  case "$1" in
    0) for ds_s in $(active_subs); do set_data_allowed "$ds_s" 0; done
       log "mobile data blocked on every SIM" ;;
    1) d=$(get_data_sub)
       for ds_s in $(active_subs); do if [ "$ds_s" = "$d" ]; then set_data_allowed "$ds_s" 1; else set_data_allowed "$ds_s" 0; fi; done
       svc data enable
       log "mobile data on, data SIM only (sub $d)" ;;
  esac
}
# Put the blocks back if anything changed them (or the data SIM changed)
enforce_data() {
  case "$1" in 0|1) ;; *) return 0 ;; esac
  [ "$1" = 1 ] && d=$(get_data_sub) || d=""
  for ds_s in $(active_subs); do
    want=00000000; [ "$ds_s" = "$d" ] && want=00000001
    have=$(data_allowed "$ds_s")
    if [ -n "$have" ] && [ "$have" != "$want" ]; then
      [ "$want" = 00000001 ] && set_data_allowed "$ds_s" 1 || set_data_allowed "$ds_s" 0
      log "mobile data block on sub $ds_s was not as set - fixed"
    fi
  done
}
unblock_all() { for ds_s in $(active_subs); do set_data_allowed "$ds_s" 1; done; }

# ---------------------------------------------------------------- profiles
# apply_profile <W|C> [baseline]
# baseline=1: both SIMs on with their own network types (pause / uninstall / action)
apply_profile() {
  ap=$1; base=$2
  eval "d0=\$${ap}_SIM0; d1=\$${ap}_SIM1; dd=\$${ap}_DATA; dv=\$${ap}_VOICE; ds=\$${ap}_SMS; dm=\$${ap}_MDATA"
  if [ "$base" = 1 ]; then d0=ORIG; d1=ORIG; fi

  # Which SIMs have to be turned on or off?
  toggle=""
  for sl in 0 1; do
    eval "d=\$d$sl"
    on=$(slot_sub $sl)
    if [ "$d" = OFF ] && [ -n "$on" ]; then toggle=1; fi
    if [ "$d" != OFF ] && [ -z "$on" ]; then toggle=1; fi
  done
  # Block mobile data on every SIM during the switch, so none briefly carries data it shouldn't
  [ "$dm" != keep ] && [ "$base" != 1 ] && for ds_s in $(active_subs); do set_data_allowed "$ds_s" 0; done

  # 1. Turn on what should be on, and wait for it to register
  for sl in 0 1; do
    eval "d=\$d$sl"
    [ "$d" != OFF ] && [ -z "$(slot_sub $sl)" ] || continue
    sub=$(sub_of_slot $sl) || { log "SIM$((sl + 1)): no SIM found"; continue; }
    log "SIM$((sl + 1)) on (sub $sub): $(set_uicc 1 "$sub" | tr -d '\n')"
    i=0
    while [ $i -lt 60 ] && [ "$(slot_sub $sl)" != "$sub" ]; do sleep 2; i=$((i+2)); done
    [ "$dm" != keep ] && [ "$base" != 1 ] && set_data_allowed "$sub" 0
  done

  # 2. Network types of the SIMs that are on
  for sl in 0 1; do
    eval "d=\$d$sl"
    case "$d" in
      OFF) ;;
      ORIG) net_restore $sl ;;
      *) [ -n "$(slot_sub $sl)" ] && net_set $sl "$d" ;;
    esac
  done

  # 3. Data / calls / SMS SIM - before anything is turned off, so Android doesn't move them
  for x in "data TX_SET_DATA get_data_sub $dd" "calls TX_SET_VOICE get_voice_sub $dv" "SMS TX_SET_SMS get_sms_sub $ds"; do
    set -- $x
    case "$4" in 0|1) ;; *) continue ;; esac
    eval "code=\$$2"
    set_default "$1" "$code" "$(sub_of_slot "$4")" "$3"
  done

  # 4. Turn off what should be off
  turned_off=""
  for sl in 0 1; do
    eval "d=\$d$sl"
    [ "$d" = OFF ] && [ -n "$(slot_sub $sl)" ] || continue
    sub=$(sub_of_slot $sl)
    log "SIM$((sl + 1)) off (sub $sub): $(set_uicc 0 "$sub" | tr -d '\n')"
    turned_off="$turned_off $sub"
  done

  # 5. Mobile data
  if [ "$base" = 1 ]; then unblock_all; log "mobile data unblocked on every SIM"; return 0; fi
  [ "$dm" = keep ] && return 0
  if [ -n "$turned_off" ]; then
    # Android moves the data SIM a moment after a SIM is turned off - wait until it's on a
    # SIM that is still on, so "data SIM only" picks the right one
    i=0
    while [ $i -lt 30 ]; do
      ds_now=$(get_data_sub)
      moved=1
      for t in $turned_off; do [ "$ds_now" = "$t" ] && moved=""; done
      if [ -n "$moved" ] && [ -n "$ds_now" ] && { [ "$ds_now" = "$(slot_sub 0)" ] || [ "$ds_now" = "$(slot_sub 1)" ]; }; then break; fi
      sleep 1; i=$((i+1))
    done
  fi
  data_policy "$dm"
  return 0
}

# Carry over state from v2.x
migrate_state() {
  [ -s "$STATE/subid" ] && [ ! -s "$STATE/subid_1" ] && mv "$STATE/subid" "$STATE/subid_1"
  rm -f "$STATE/subid"
  [ -s "$STATE/prev_data" ] && [ ! -s "$STATE/prev_data_1" ] && mv "$STATE/prev_data" "$STATE/prev_data_1"
  rm -f "$STATE/prev_data"
}
