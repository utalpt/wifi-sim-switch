#!/system/bin/sh
# Called by the WebUI "Confirm codes" button: trust the ISub codes for this framework.jar
MODDIR=${0%/*}
. "$MODDIR/common.sh"
id=$(fw_id)
[ -n "$id" ] || { echo "framework.jar not readable" >&2; exit 1; }
echo "$id" > "$FPFILE"
log "ISub codes confirmed for framework $id"
echo "$id"
