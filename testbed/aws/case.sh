#!/bin/bash
# Run on the AWS VyOS router: switch between the three assignment cases.
# Same shaping as the Lab 2 testbed (tbf root, netem nested), on the two
# VPC-facing interfaces: eth0 = client subnet 10.0.1.0/24, eth1 = server
# subnet 10.0.2.0/24.
#
#   ./case.sh 0      clear all shaping
#   ./case.sh 1      RTT 10ms,  1% loss,  100 Mbit
#   ./case.sh 2      RTT 200ms, 20% loss, 100 Mbit
#   ./case.sh 3      RTT 200ms, no loss,  80 Mbit
#   ./case.sh show   print the active configuration
set -e
IFACES="eth0 eth1"
TC="sudo /sbin/tc"
# Token bucket burst. 9015 (the handout value) holds six 1500-byte frames but
# only one 9001-byte frame, which starves TCP at MTU 9001; use BURST=54015
# (six jumbo frames) for the MTU 9001 runs.
BURST=${BURST:-9015}

clear_all() { for i in $IFACES; do $TC qdisc del dev $i root 2>/dev/null || true; done; }

shape() {  # $1 = rate mbit   $2 = one-way delay ms   $3 = loss % (may be empty)
  for i in $IFACES; do
    $TC qdisc add dev $i root handle 1:0 tbf rate ${1}mbit latency 0.001ms burst $BURST
    if [ -n "$3" ]; then
      $TC qdisc add dev $i parent 1:1 handle 10: netem delay ${2}ms loss ${3}%
    else
      $TC qdisc add dev $i parent 1:1 handle 10: netem delay ${2}ms
    fi
  done
}

case "$1" in
  0) clear_all; echo "cleared all shaping" ;;
  1) clear_all; shape 100 5   1  ; echo "Case 1: RTT 10ms  / loss 1%  / 100 Mbit" ;;
  2) clear_all; shape 100 100 20 ; echo "Case 2: RTT 200ms / loss 20% / 100 Mbit" ;;
  3) clear_all; shape 80  100 ""  ; echo "Case 3: RTT 200ms / no loss  / 80 Mbit" ;;
  show) : ;;
  *) echo "usage: $0 {0|1|2|3|show}"; exit 1 ;;
esac

echo "--- active qdiscs (burst $BURST) ---"
for i in $IFACES; do echo "[$i] mtu $(cat /sys/class/net/$i/mtu)"; $TC qdisc show dev $i | sed 's/^/  /'; done
