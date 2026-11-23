#!/system/bin/sh
# A turned-off SIM stays off across reboots - turn everything back on before the module
# goes away. This runs early in boot (telephony isn't up yet), so do the work in the
# background once boot completes. common.sh is loaded into memory first, as the module
# folder is deleted right after this script.
MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_config
LOG=/dev/null
(
  until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
  sleep 20
  if build_ok; then apply_profile C 1; else net_restore 0; net_restore 1; fi
  rm -rf "$STATE"
) </dev/null >/dev/null 2>&1 &
