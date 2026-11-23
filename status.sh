#!/system/bin/sh
# Prints the current state as KEY=value lines for the WebUI. Read-only.
# Each dumpsys / cmd / service call starts a new process, so the slow ones run in
# parallel and the WebUI gets its answer in roughly the time of the slowest one.
MODDIR=${0%/*}
. "$MODDIR/common.sh"

T=$STATE/.status.$$
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT

# Live reads, in parallel
dumpsys isub > "$T/isub" 2>/dev/null &
dumpsys connectivity 2>/dev/null | grep -E 'NetworkAgentInfo' > "$T/conn" &
cmd wifi status > "$T/wifi" 2>/dev/null &
for s in 0 1; do cmd phone get-allowed-network-types-for-users -s $s 2>/dev/null | head -1 > "$T/mask$s" & done
if pgrep -f 'wifisimoff/service.sh' >/dev/null 2>&1; then echo 1 > "$T/run"; else echo 0 > "$T/run"; fi &
wait

ISUB_CACHE=$(cat "$T/isub")
CONN_CACHE=$(cat "$T/conn")
load_config

# Per-SIM data blocks (ISub codes needed), also in parallel
if build_ok; then
  ok=1
  for s in $(active_subs); do data_allowed "$s" > "$T/dallow_$s" & done
  wait
fi

cfg_dump
[ -f "$RUNTIME" ] && cat "$RUNTIME"
echo "running=$(cat "$T/run")"
if [ "$REQUIRE_INTERNET" = 1 ]; then
  if grep -E 'NetworkAgentInfo.*WIFI' "$T/conn" | grep -qE '[&: ]VALIDATED([& ]|$)'; then echo wifi=1; else echo wifi=0; fi
elif grep -q "Wifi is connected" "$T/wifi" || ip route show table all 2>/dev/null | grep -q "^default.*dev wlan0"; then
  echo wifi=1
else
  echo wifi=0
fi
[ -n "$ok" ] && echo fp_ok=1 || echo fp_ok=0
[ -f "$FPFILE" ] && echo "fp_saved=$(cat "$FPFILE")"
id=$(fw_id)
echo "fp=$id"
known_codes "$id" >/dev/null && echo fp_known=1
[ "$AUTO_CODES" = 1 ] && echo auto_codes=1
echo "rom=$(getprop ro.build.fingerprint)"
echo "data_sub=$(get_data_sub)"
echo "voice_sub=$(get_voice_sub)"
echo "sms_sub=$(get_sms_sub)"
# Is any cellular network actually carrying internet? (IMS-only links for calls don't count)
if grep -E 'NetworkAgentInfo.*CELLULAR' "$T/conn" | grep -qE '[&: ]INTERNET([& ]|$)'; then
  echo cell_internet=1; else echo cell_internet=0; fi
echo "theme=$(cat "$STATE/theme" 2>/dev/null)"

# One line per SIM: sim=subId|slot|name|enabled
isub_dump | grep 'SubscriptionInfoInternal: id=' | sort -u | sed -nE \
  's/.*SubscriptionInfoInternal: id=([0-9]+) .* simSlotIndex=(-?[0-9]+) .* displayName=(.*) carrierName=.* areUiccApplicationsEnabled=([01]).*/sim=\1|\2|\3|\4/p' | sort -t'|' -k1,1 -u
for s in $(isub_dump | grep -oE 'Logical SIM slot [01]: subId=[0-9]+' | sort -u | grep -oE 'slot [01]' | cut -d' ' -f2); do
  echo "active_slot=$s"
done
for f in "$T"/dallow_*; do [ -f "$f" ] && echo "${f##*/}=$(cat "$f")"; done
for s in 0 1; do
  echo "slot_sub$s=$(sub_of_slot $s)"
  echo "mask$s=$(cat "$T/mask$s")"
done
grep -E '^(version|author)=' "$MODDIR/module.prop" | sed 's/^/mod_/'
