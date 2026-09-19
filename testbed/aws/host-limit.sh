#!/bin/bash
# Run on the AWS client and server: 100 Mbit egress cap on eth0, the
# interface that faces the VyOS router (eth1 carries the SSH session and
# is left alone).
#   ./host-limit.sh on|off|show        (BURST=54015 for MTU 9001, default 9015)
IF=eth0
BURST=${BURST:-9015}
case "$1" in
  on)  sudo tc qdisc del dev $IF root 2>/dev/null; sudo tc qdisc add dev $IF root tbf rate 100mbit latency 0.001ms burst $BURST ;;
  off) sudo tc qdisc del dev $IF root 2>/dev/null ;;
  show) : ;;
  *) echo "usage: $0 on|off|show"; exit 1 ;;
esac
echo "[$IF] mtu $(cat /sys/class/net/$IF/mtu)"; tc qdisc show dev $IF
