#!/usr/bin/env python3
"""Apply the lossy-link TCP changes to an Ubuntu 4.4 (linux-aws 4.4.0-1128)
kernel tree, in place.  python3 apply-lossy-link.py <kernel-src-dir>

One new sysctl, net.ipv4.tcp_lossy_link, a bit mask so that each change can
be switched on its own without rebooting:

  1  no exponential RTO back-off: keep the RTO on a retransmission timeout
     instead of doubling it (Mondal & Kuzmanovic, "Removing Exponential
     Back-off from TCP", CCR 2008)
  2  keep the congestion window on a retransmission timeout instead of
     collapsing it to one segment
  4  treat loss recovery as a repair, not a congestion signal: no
     proportional-rate reduction of cwnd, and keep running the congestion
     control's increase function while in Recovery

Every edit is an exact string replacement and asserts that the original
text is present exactly once, so the script refuses to run on a tree it
does not recognise.
"""
import pathlib, sys

root = pathlib.Path(sys.argv[1])

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == 1, "{}: expected exactly one match for:\n{}".format(rel, old)
    p.write_text(s.replace(old, new))
    print("edited " + rel)

# --- declaration and definition ------------------------------------------
edit("include/net/tcp.h",
     "extern int sysctl_tcp_early_retrans;\n",
     "extern int sysctl_tcp_early_retrans;\n"
     "extern int sysctl_tcp_lossy_link;\n")

edit("net/ipv4/tcp_input.c",
     "int sysctl_tcp_early_retrans __read_mostly = 3;\n",
     "int sysctl_tcp_early_retrans __read_mostly = 3;\n"
     "/* EE542: bit mask, see Documentation in kernel/apply-lossy-link.py.\n"
     " * 1 = no exponential RTO back-off, 2 = keep cwnd on RTO,\n"
     " * 4 = no cwnd reduction in loss recovery. 0 = stock behaviour. */\n"
     "int sysctl_tcp_lossy_link __read_mostly = 0;\n"
     "EXPORT_SYMBOL(sysctl_tcp_lossy_link);\n")

# --- sysctl entry -----------------------------------------------------------
edit("net/ipv4/sysctl_net_ipv4.c",
     '\t\t.procname\t= "tcp_early_retrans",\n',
     '\t\t.procname\t= "tcp_lossy_link",\n'
     '\t\t.data\t\t= &sysctl_tcp_lossy_link,\n'
     '\t\t.maxlen\t\t= sizeof(int),\n'
     '\t\t.mode\t\t= 0644,\n'
     '\t\t.proc_handler\t= proc_dointvec,\n'
     '\t},\n'
     '\t{\n'
     '\t\t.procname\t= "tcp_early_retrans",\n')

# --- 1: no exponential back-off ---------------------------------------------
edit("net/ipv4/tcp_timer.c",
     "\t} else {\n"
     "\t\t/* Use normal (exponential) backoff */\n"
     "\t\ticsk->icsk_rto = min(icsk->icsk_rto << 1, TCP_RTO_MAX);\n"
     "\t}\n",
     "\t} else if (sysctl_tcp_lossy_link & 1) {\n"
     "\t\t/* EE542: on a lossy link a timeout is a lost packet, not a\n"
     "\t\t * congested path. Keep the measured RTO instead of doubling it;\n"
     "\t\t * the retry limits still apply through icsk_retransmits. */\n"
     "\t\ticsk->icsk_rto = min(icsk->icsk_rto, TCP_RTO_MAX);\n"
     "\t} else {\n"
     "\t\t/* Use normal (exponential) backoff */\n"
     "\t\ticsk->icsk_rto = min(icsk->icsk_rto << 1, TCP_RTO_MAX);\n"
     "\t}\n")

# --- 2: keep cwnd on RTO ----------------------------------------------------
edit("net/ipv4/tcp_input.c",
     "\ttp->snd_cwnd\t   = 1;\n"
     "\ttp->snd_cwnd_cnt   = 0;\n"
     "\ttp->snd_cwnd_stamp = tcp_time_stamp;\n",
     "\t/* EE542: a timeout on a lossy link says nothing about capacity;\n"
     "\t * keep the window and just retransmit. */\n"
     "\tif (!(sysctl_tcp_lossy_link & 2))\n"
     "\t\ttp->snd_cwnd\t   = 1;\n"
     "\ttp->snd_cwnd_cnt   = 0;\n"
     "\ttp->snd_cwnd_stamp = tcp_time_stamp;\n")

# --- 4: no reduction in recovery, keep growing ------------------------------
edit("net/ipv4/tcp_input.c",
     "static inline bool tcp_may_raise_cwnd(const struct sock *sk, const int flag)\n"
     "{\n"
     "\tif (tcp_in_cwnd_reduction(sk))\n"
     "\t\treturn false;\n",
     "static inline bool tcp_may_raise_cwnd(const struct sock *sk, const int flag)\n"
     "{\n"
     "\t/* EE542: loss recovery is a repair, not a reason to stop growing. */\n"
     "\tif ((sysctl_tcp_lossy_link & 4) &&\n"
     "\t    inet_csk(sk)->icsk_ca_state == TCP_CA_Recovery)\n"
     "\t\treturn flag & FLAG_FORWARD_PROGRESS;\n"
     "\tif (tcp_in_cwnd_reduction(sk))\n"
     "\t\treturn false;\n")

edit("net/ipv4/tcp_input.c",
     "\tif (newly_acked_sacked <= 0 || WARN_ON_ONCE(!tp->prior_cwnd))\n"
     "\t\treturn;\n",
     "\tif (newly_acked_sacked <= 0 || WARN_ON_ONCE(!tp->prior_cwnd))\n"
     "\t\treturn;\n"
     "\t/* EE542: proportional rate reduction exists to drain a congested\n"
     "\t * queue; on a lossy link there is none. Leave cwnd alone. */\n"
     "\tif (sysctl_tcp_lossy_link & 4)\n"
     "\t\treturn;\n")
print("all edits applied")
