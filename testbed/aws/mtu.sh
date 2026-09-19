#!/bin/bash
# Run on any of the three AWS nodes: set the router-facing interface(s) to
# the given MTU. AWS VPC supports 1500 and 9001 (jumbo) inside the VPC.
#   ./mtu.sh 1500|9001
MTU=${1:?mtu}
case "$(hostname)" in
  client|server) IFS_=eth0 ;;
  *)             IFS_="eth0 eth1" ;;   # VyOS
esac
for i in $IFS_; do sudo ip link set dev $i mtu $MTU; echo "$i mtu $(cat /sys/class/net/$i/mtu)"; done
