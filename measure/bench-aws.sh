#!/bin/bash
# Lab 3 Part 2: run the Lab 2 benchmark matrix on the AWS nodes.
#   ./bench-aws.sh <mbit|auto> [dgram_bytes] [cases] [tag]
#   ./bench-aws.sh 98 1472 "1 2 3" aws-mtu1500
#   ./bench-aws.sh 98 8973 "1 2 3" aws-mtu9001      # after ./mtu.sh 9001 on all three nodes
# Sender = client (10.0.1.10, holds ~/data.bin), receiver = server (10.0.2.10),
# both reached through the Lab 3 SSH bundle. Keeps every raw log.
CFG=${LAB3_SSH:-$HOME/Downloads/EE542-Lab3-SSH}/ssh_config   # SSH bundle: key + known_hosts, never committed
S(){ ssh -F "$CFG" "$@" 2>&1 | grep -v '^\*\*'; }
MBIT=${1:-98}; DGRAM=${2:-1472}; CASES=${3:-"1 2 3"}; TAG=${4:-aws-$(date +%m%d-%H%M)}
RCV_IP=10.0.2.10; FILE=${FILE:-data.bin}
DIR=$(cd "$(dirname "$0")/.." && pwd)/private/measure; RUNS=$DIR/runs/$TAG; mkdir -p "$RUNS"
OUT=$DIR/bench-aws-results.csv
[ -f "$OUT" ] || echo "tag,case,mtu,dgram,mbit,file_mb,oneway_s,oneway_mbps,srv_span_s,srv_mbps,retx,rounds,rcvbuf_err,md5_ok,skew_ms" > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$RUNS/bench.log"; }

S aws-vyos "./case.sh 0" >/dev/null
SRC_MD5=$(S aws-client "md5sum ~/$FILE | cut -d' ' -f1")
SIZE=$(S aws-client "stat -c%s ~/$FILE"); SIZE_MB=$((SIZE/1000000))
MTU=$(S aws-client "cat /sys/class/net/eth0/mtu")
RMTU=$(S aws-vyos "cat /sys/class/net/eth0/mtu")
log "file ${SIZE_MB}MB md5=${SRC_MD5:0:8} host_mtu=$MTU router_mtu=$RMTU dgram=$DGRAM pace=$MBIT cases=[$CASES]"
for H in aws-client aws-server; do S $H "timedatectl 2>/dev/null | grep -i synchronized || ntpq -p 2>/dev/null | head -3" >/dev/null; done

for C in $CASES; do
  log "=== Case $C ==="
  S aws-vyos "BURST=${BURST:-9015} ./case.sh $C" >/dev/null; sleep 2
  SL="$RUNS/case$C.srv.log"; CL="$RUNS/case$C.cli.log"
  S aws-server 'pkill -x server 2>/dev/null; rm -f ~/recv.bin'
  ssh -F "$CFG" aws-server "cd ~/Fast-reliable-File-Transfer/src && timeout 2400 ./server 9000 ~/recv.bin 33554432" >"$SL" 2>&1 &
  SRVPID=$!; sleep 3
  T0=$(date +%s)
  ssh -F "$CFG" aws-client "cd ~/Fast-reliable-File-Transfer/src && ${CLIENT_ENV:-} timeout 2400 ./client $RCV_IP 9000 ~/$FILE $DGRAM $MBIT" >"$CL" 2>&1
  CRC=$?; wait $SRVPID 2>/dev/null; T1=$(date +%s)

  SEC=$(grep "one-way elapsed"    "$CL" | awk '{print $3}')
  MBPS=$(grep "payload throughput" "$CL" | awk '{print $3}')
  RETX=$(grep "retransmitted"      "$CL" | awk '{print $2}')
  RNDS=$(grep "feedback rounds"    "$CL" | awk '{print $3}')
  SPAN=$(grep "receive span"       "$SL" | awk '{print $3}')
  SMBPS=$(grep "receive goodput"   "$SL" | awk '{print $3}')
  RBE=$(grep "RcvbufErrors"        "$SL" | sed 's/.*RcvbufErrors +\([0-9-]*\).*/\1/')
  DST_MD5=$(S aws-server 'md5sum ~/recv.bin 2>/dev/null | cut -d" " -f1')
  OK=$([ -n "$SRC_MD5" ] && [ "$SRC_MD5" = "$DST_MD5" ] && echo yes || echo NO)
  SKEW=$([ -n "$SEC" ] && [ -n "$SPAN" ] && awk -v a="$SEC" -v b="$SPAN" 'BEGIN{printf "%d", (a-b)*1000}')
  log "  one-way ${SEC:-?}s/${MBPS:-?}Mbps | receiver ${SPAN:-?}s/${SMBPS:-?}Mbps | retx=${RETX:-?} rounds=${RNDS:-?} rcvbuf_err=${RBE:-?} md5=$OK wall=$((T1-T0))s rc=$CRC"
  [ -n "$SKEW" ] && [ "${SKEW#-}" -gt 2000 ] && log "  !! one-way and receiver span differ by ${SKEW} ms - clock skew"
  echo "$TAG,$C,$MTU,$DGRAM,$MBIT,$SIZE_MB,${SEC:-},${MBPS:-},${SPAN:-},${SMBPS:-},${RETX:-},${RNDS:-},${RBE:-},$OK,${SKEW:-}" >> "$OUT"
done
S aws-vyos "./case.sh 0" >/dev/null
log "=== done -> $OUT (raw logs in $RUNS) ==="
