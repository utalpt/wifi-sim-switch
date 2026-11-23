#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 20
: > "$LOG"

migrate_state
load_config
# Rewrite a v3 config in the v4 profile format (once)
if [ -z "$HAS_PROFILES" ] && [ -n "$MODE" ]; then
  cfg_dump > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
  log "migrated v3 settings to profiles"
fi
log "start: enabled=$ENABLED"
log "  on WiFi: $(profile_desc W)"
log "  off WiFi: $(profile_desc C)"

runtime() {   # publish service state for the WebUI and the KernelSU card (only when it changes)
  r="status=$1 state=$2"
  [ "$r" = "$last_rt" ] && return
  printf 'status=%s\nstate=%s\nsince=%s\n' "$1" "$2" "$(date '+%F %T')" > "$RUNTIME"
  card_status "$1" "$2"
  last_rt=$r
}

# The KernelSU manager shows module.prop's description on the module card
sim_label() {   # <slot> -> carrier name, or SIM1/SIM2
  n=$(dumpsys isub 2>/dev/null | grep -oE "simSlotIndex=$1 .* displayName=[^ ]+" | head -1 | sed 's/.*displayName=//')
  [ -n "$n" ] || n=$(cat "$STATE/name_$1" 2>/dev/null)
  [ -n "$n" ] && echo "$n" > "$STATE/name_$1"   # remembered for when the SIM is off
  echo "${n:-SIM$(($1 + 1))}"
}
card_status() {   # <status> <state>
  case "$1" in
    paused)  d="⏸️ Paused - both SIMs on" ;;
    blocked) d="⚠️ Blocked - confirm the ISub codes in the WebUI" ;;
    active)
      [ -n "$2" ] || return 0
      [ "$2" = wifi ] && { pn="On WiFi"; p=W; } || { pn="Off WiFi"; p=C; }
      sims=""
      for sl in 0 1; do
        if [ -n "$(slot_sub $sl)" ]; then st_=on; else st_=off; fi
        sims="$sims · $(sim_label $sl) $st_"
      done
      eval "md=\$${p}_MDATA"
      case "$md" in
        0) dt=" · mobile data off" ;;
        1) ds=$(get_data_sub); dn=""
           for sl in 0 1; do [ "$(slot_sub $sl)" = "$ds" ] && dn=$(sim_label $sl); done
           dt=" · data on ${dn:-SIM}" ;;
        *) dt="" ;;
      esac
      d="✅ $pn$sims$dt" ;;
    *) return 0 ;;
  esac
  sed -i "s|^description=.*|description=$d|" "$MODDIR/module.prop" 2>/dev/null
}

last=""; blocked=""; paused=""
sum=$(conf_sum)
while true; do
  # Live config reload - profiles are declarative, so just apply the current one again
  new=$(conf_sum)
  if [ "$new" != "$sum" ]; then
    load_config
    log "config changed: enabled=$ENABLED"
    log "  on WiFi: $(profile_desc W)"
    log "  off WiFi: $(profile_desc C)"
    last=""; blocked=""; paused=""; sum=$new
  fi

  if [ "$ENABLED" != 1 ]; then
    if [ -z "$paused" ]; then
      log "paused: both SIMs on, own network types"
      if build_ok; then apply_profile C 1; else net_restore 0; net_restore 1; fi
      paused=1
    fi
    runtime paused ""
    sleep "$INTERVAL"; continue
  fi

  if ! build_ok && needs_codes; then
    [ -n "$blocked" ] || log "BLOCKED: these settings need the ISub codes, not confirmed for this build - check them in the WebUI"
    blocked=1
    runtime blocked ""
    sleep "$INTERVAL"; continue
  fi
  blocked=""

  wstate=$(state)
  if [ "$wstate" != "$last" ]; then
    sleep "$DEBOUNCE"
    if [ "$(state)" = "$wstate" ]; then
      if [ "$wstate" = wifi ]; then log "-> on WiFi"; apply_profile W; else log "-> off WiFi"; apply_profile C; fi
      last=$wstate
    fi
  fi
  # Keep the per-SIM mobile data blocks as the profile set them (every 3rd cycle)
  cyc=$(( ${cyc:-0} + 1 ))
  if [ -n "$last" ] && [ $((cyc % 3)) = 0 ]; then
    [ "$last" = wifi ] && mp=$W_MDATA || mp=$C_MDATA
    enforce_data "$mp"
  fi
  runtime active "$last"
  sleep "$INTERVAL"
done
