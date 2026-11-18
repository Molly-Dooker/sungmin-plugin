#!/usr/bin/env bash
# costguard.sh <work folder> <limit USD> [alert USD list, default 25,50,100,200]: cost guard of a deepagents run (050 run 2).
# Every 60 s it takes the USD estimate of <run>/usage.jsonl (usage.py next to this script). Each alert level fires once as
# a "cost alert" line in <work>/events.log (waitev.sh picks it up); after a restart the levels already passed fire again once.
# At LIMIT it stops the run the run.md "멈추기" way: wrappers/STOP, wait drained with no holder and no wrapper, stop the
# unit. If the device stays busy it leaves the unit running and says so. Deletes nothing. LIMIT is the user's decision.
WK=$1; LIMIT=${2:?usage: costguard.sh <work folder> <limit USD> [alerts]}; ALERTS=${3:-25,50,100,200}
source "$WK/launch.env"
DEV=${DEV:-/dev/bos/0}
U=$(dirname "$(readlink -f "$0")")/usage.py
fired=" "
while true; do
  R=$(cat "$WK/run.txt"); UNIT=$(cat "$WK/unit.txt")
  usd=$($PY -c "import importlib.util,sys;s=importlib.util.spec_from_file_location('u',sys.argv[1]);u=importlib.util.module_from_spec(s);s.loader.exec_module(u);print(int(u.summarize(sys.argv[2])[('all','all')][4]))" "$U" "$R/usage.jsonl" 2>/dev/null || echo 0)
  for lv in ${ALERTS//,/ }; do
    if [ "${usd:-0}" -ge "$lv" ] && [[ "$fired" != *" $lv "* ]]; then
      fired="$fired$lv "; echo "$(date '+%m-%d %H:%M:%S') [costguard] cost alert usd~$usd >= $lv" | tee -a "$WK/events.log"
    fi
  done
  if [ "${usd:-0}" -ge "$LIMIT" ]; then
    echo "$(date '+%m-%d %H:%M:%S') [costguard] cost limit usd~$usd >= $LIMIT: touch STOP" | tee -a "$WK/events.log"; touch "$R/wrappers/STOP"
    for i in $(seq 1 480); do
      d=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('drained'), len(d.get('blocking') or []))" "$R/wrappers/status.json" 2>/dev/null)
      if [ "$d" = "True 0" ] && ! fuser "$DEV" >/dev/null 2>&1 && ! ps -eo cmd | grep -q "[r]un_device_command.py"; then break; fi
      sleep 15
    done
    if ! fuser "$DEV" >/dev/null 2>&1 && ! ps -eo cmd | grep -q "[r]un_device_command.py"; then
      systemctl --user stop "$UNIT.service" && r="unit stopped (cost limit)" || r="unit stop failed (rc $?)"
      echo "$(date '+%m-%d %H:%M:%S') [costguard] $r" | tee -a "$WK/events.log"
    else
      echo "$(date '+%m-%d %H:%M:%S') [costguard] NOT stopped: device busy (drained=$d)" | tee -a "$WK/events.log"
    fi
    exit 0
  fi
  sleep 60
done
