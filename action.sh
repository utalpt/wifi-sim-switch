#!/system/bin/sh
# KSU action button: pause / resume. Returns at once - the running service does the work
# (pausing turns both SIMs back on with their own network types and lifts data blocks).
MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_config

if [ "$ENABLED" = 1 ]; then new=0; else new=1; fi
mkdir -p "$STATE"
if [ -f "$CONF" ] && grep -q '^ENABLED=' "$CONF"; then
  sed "s/^ENABLED=.*/ENABLED=$new/" "$CONF" > "$CONF.tmp"
else
  { cat "$CONF" 2>/dev/null; echo "ENABLED=$new"; } > "$CONF.tmp"
fi
mv "$CONF.tmp" "$CONF"

if [ "$new" = 0 ]; then
  echo "Paused."
  echo "Both SIMs are turned back on with their own network types,"
  echo "and mobile data blocks are lifted, within ~${INTERVAL}s."
  echo "Run the action again to resume."
else
  echo "Resumed."
  echo "The profile for the current WiFi state is applied within ~${INTERVAL}s."
fi
if ! pgrep -f 'wifisimoff/service.sh' >/dev/null 2>&1; then
  echo
  echo "Warning: the service isn't running - reboot to start it."
fi
echo
echo "--- last log lines ---"
tail -n 8 "$LOG" 2>/dev/null
