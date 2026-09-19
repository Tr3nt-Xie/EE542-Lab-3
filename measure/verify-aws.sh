#!/bin/bash
# Verify each case on the AWS testbed the way the handout asks: ping
# (-i 0.2 -c 200), iperf UDP loss in both directions, iperf TCP.
#   ./verify-aws.sh "0 1 2 3"
CFG=${LAB3_SSH:-$HOME/Downloads/EE542-Lab3-SSH}/ssh_config   # SSH bundle: key + known_hosts, never committed
S(){ ssh -F "$CFG" "$@" 2>&1 | grep -v '^\*\*'; }
OUT=$(cd "$(dirname "$0")/.." && pwd)/private/measure/verify-aws.txt; mkdir -p "$(dirname "$OUT")"
for C in ${1:-0 1 2 3}; do
  S aws-vyos "BURST=${BURST:-9015} ./case.sh $C" >/dev/null; sleep 2
  echo "===== Case $C  $(date +%F' '%T) =====" | tee -a "$OUT"
  S aws-vyos "./case.sh show" | grep -E "^\[|tbf|netem" | tee -a "$OUT"
  echo "--- ping client -> server (200 x 0.2 s)" | tee -a "$OUT"
  S aws-client "ping -i 0.2 -c 200 -q 10.0.2.10 | tail -2" | tee -a "$OUT"
  echo "--- iperf UDP client -> server, 100 Mbit offered, 10 s" | tee -a "$OUT"
  S aws-server "pkill -x iperf; nohup iperf -s -u >/dev/null 2>&1 &"; sleep 1
  S aws-client "iperf -u -c 10.0.2.10 -b 100M -t 10 -f m | grep -E 'Server Report' -A1 | tail -1" | tee -a "$OUT"
  S aws-server "pkill -x iperf"
  echo "--- iperf UDP server -> client, 100 Mbit offered, 10 s" | tee -a "$OUT"
  S aws-client "pkill -x iperf; nohup iperf -s -u >/dev/null 2>&1 &"; sleep 1
  S aws-server "iperf -u -c 10.0.1.10 -b 100M -t 10 -f m | grep -E 'Server Report' -A1 | tail -1" | tee -a "$OUT"
  S aws-client "pkill -x iperf"
  echo "--- iperf TCP client -> server, 15 s" | tee -a "$OUT"
  S aws-server "pkill -x iperf; nohup iperf -s >/dev/null 2>&1 &"; sleep 1
  S aws-client "iperf -c 10.0.2.10 -t 15 -f m | tail -1" | tee -a "$OUT"
  S aws-server "pkill -x iperf"
done
S aws-vyos "./case.sh 0" >/dev/null
