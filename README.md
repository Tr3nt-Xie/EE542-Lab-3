# EE 542 Lab 3

Three EC2 nodes in one VPC — Ubuntu client and server, VyOS router — running
the Lab 2 file-transfer protocol under the Lab 2 network conditions, then
a modified TCP stack (Part 3).

## Layout

```
src/            reliable UDP file transfer from Lab 2 (sender = client, receiver = server)
testbed/aws/    case.sh (router: switch Case 1/2/3), host-limit.sh (hosts: 100 Mbit egress), mtu.sh
measure/        bench-aws.sh (1 GB matrix over SSH), verify-aws.sh (ping / iperf per case)
```

## Part 1: AWS topology

| Node | Private IP (router side) | Notes |
|---|---|---|
| client | 10.0.1.10 eth0 | sender; second interface carries the elastic IP and SSH |
| VyOS | 10.0.1.254 eth0 / 10.0.2.254 eth1 | forwards between the two subnets |
| server | 10.0.2.10 eth0 | receiver; second interface for the elastic IP |

Hosts route the other subnet through the router (`ip route add 10.0.2.0/24
via 10.0.1.254` and the mirror on the server); source/destination check is
disabled on the router's interfaces. SSH goes over the elastic-IP interface,
so shaping and MTU changes on eth0 never touch the management path.

## Part 2: running the transfer

Build on both hosts:

```bash
sudo apt-get install -y build-essential
sudo sysctl -w net.core.rmem_max=33554432 net.core.wmem_max=33554432
cd src && make
```

Shape (Lab 2 values; `BURST=54015` for MTU 9001, see below):

```bash
./host-limit.sh on            # client and server
./case.sh 2                   # router: 1 = 10 ms/1%, 2 = 200 ms/20%, 3 = 200 ms/0%/80 Mbit
./mtu.sh 9001                 # all three nodes, then `sudo ip route flush cache` on the hosts
```

Transfer:

```bash
./server 9000 ~/recv.bin 33554432                       # server
./client 10.0.2.10 9000 ~/data.bin 1472 98              # client, MTU 1500
./client 10.0.2.10 9000 ~/data.bin 8973 98              # client, MTU 9001
./client 10.0.2.10 9000 ~/data.bin 1472 auto            # let the sender find the rate
```

From a workstation with the SSH bundle, `measure/verify-aws.sh "1 2 3"`
checks each case with ping and iperf the way the handout asks, and
`measure/bench-aws.sh 98 1472 "1 2 3" tag` runs the 1 GB matrix and keeps
every log under `private/measure/`.

Two things worth knowing about jumbo frames on EC2: the VyOS config pins
its interfaces to MTU 1500, and after a failed jumbo ping the hosts keep a
path-MTU 1500 entry in the route cache until it is flushed. And the
handout's `burst 9015` holds exactly one 9001-byte frame, which starves TCP
at MTU 9001 (4 Mbit/s unshaped); scale it to six frames (`BURST=54015`) for
the MTU 9001 runs, the same six-frame allowance 9015 gives at MTU 1500.
