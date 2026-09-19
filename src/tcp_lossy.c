/* tcp_lossy - a TCP congestion control module for lossy, non-congested links.
 *
 * Standard TCP treats every loss as congestion and halves its window.
 * On a link whose loss is random (netem, a satellite hop, a long wireless
 * uplink) that response is the whole reason throughput collapses:
 * 130 kbit/s at 200 ms RTT and 20% loss for cubic, measured in this lab.
 *
 * This module keeps the window on loss. ssthresh() returns the current
 * window, so proportional rate reduction has nothing to reduce to, and
 * fast recovery merely retransmits. Growth is Reno's: slow start, then
 * one segment per RTT, up to a configurable cap so that a lossless link
 * is not flooded.
 *
 * What it cannot fix from here: tcp_enter_loss() in the core sets
 * snd_cwnd = 1 on every retransmission timeout, and tcp_timer.c doubles
 * the RTO on each consecutive timeout. Those need the kernel patch in
 * ../kernel/; this module is the part that works on a stock kernel.
 *
 *   sudo insmod tcp_lossy.ko max_cwnd=2000
 *   sudo sysctl -w net.ipv4.tcp_congestion_control=lossy
 */
#include <linux/module.h>
#include <net/tcp.h>

static int max_cwnd __read_mostly = 2000;
module_param(max_cwnd, int, 0644);
MODULE_PARM_DESC(max_cwnd, "upper bound on the congestion window, in segments");

static void lossy_cong_avoid(struct sock *sk, u32 ack, u32 acked)
{
	struct tcp_sock *tp = tcp_sk(sk);

	if (!tcp_is_cwnd_limited(sk))
		return;
	if (tp->snd_cwnd >= max_cwnd) {
		tp->snd_cwnd = max_cwnd;
		return;
	}
	if (tp->snd_cwnd < tp->snd_ssthresh) {
		acked = tcp_slow_start(tp, acked);
		if (!acked)
			return;
	}
	tcp_cong_avoid_ai(tp, tp->snd_cwnd, acked);
}

/* Called on loss: the window we "should" fall back to. Returning the
 * current window means no reduction at all. */
static u32 lossy_ssthresh(struct sock *sk)
{
	const struct tcp_sock *tp = tcp_sk(sk);

	return max(tp->snd_cwnd, 2U);
}

static u32 lossy_undo_cwnd(struct sock *sk)
{
	const struct tcp_sock *tp = tcp_sk(sk);

	return max(tp->snd_cwnd, tp->prior_cwnd);
}

static struct tcp_congestion_ops tcp_lossy __read_mostly = {
	.ssthresh	= lossy_ssthresh,
	.cong_avoid	= lossy_cong_avoid,
	.undo_cwnd	= lossy_undo_cwnd,
	.owner		= THIS_MODULE,
	.name		= "lossy",
};

static int __init lossy_register(void)
{
	return tcp_register_congestion_control(&tcp_lossy);
}

static void __exit lossy_unregister(void)
{
	tcp_unregister_congestion_control(&tcp_lossy);
}

module_init(lossy_register);
module_exit(lossy_unregister);

MODULE_AUTHOR("EE542 Lab 3 group");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("TCP congestion control that does not back off on random loss");
