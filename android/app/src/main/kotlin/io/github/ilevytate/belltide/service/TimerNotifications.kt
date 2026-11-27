package io.github.ilevytate.belltide.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import io.github.ilevytate.belltide.MainActivity
import io.github.ilevytate.belltide.R
import io.github.ilevytate.belltide.engine.TimerConfig
import io.github.ilevytate.belltide.engine.TimerSnapshot

/**
 * Builds the service's ongoing notification. A running step shows a system
 * chronometer counting down, so the notification only needs updating when a
 * step changes, not every second.
 */
class TimerNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    init {
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.channel_timers_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.channel_timers_description)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    fun update(snapshots: List<TimerSnapshot>) {
        manager.notify(NOTIFICATION_ID, build(snapshots))
    }

    fun build(snapshots: List<TimerSnapshot>): Notification {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_belltide)
            .setColor(context.getColor(R.color.belltide_accent))
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        when (snapshots.size) {
            0 -> builder.setContentTitle(context.getString(R.string.app_name))
            1 -> single(builder, snapshots[0])
            else -> multiple(builder, snapshots)
        }
        return builder.build()
    }

    private fun single(builder: NotificationCompat.Builder, s: TimerSnapshot) {
        builder.setContentTitle(s.name.ifBlank { context.getString(R.string.app_name) })
        if (s.paused) {
            builder.setContentText(
                context.getString(R.string.notif_paused_detail, stepText(s), clock(s.stepRemainingMs)),
            )
            builder.setShowWhen(false)
            builder.addAction(action(R.drawable.ic_action_play, R.string.action_resume, TimerService.ACTION_RESUME, s.id))
        } else {
            builder.setContentText(stepText(s))
            countdown(builder, s.stepRemainingMs)
            builder.addAction(action(R.drawable.ic_action_pause, R.string.action_pause, TimerService.ACTION_PAUSE, s.id))
        }
        builder.addAction(action(R.drawable.ic_action_skip, R.string.action_skip, TimerService.ACTION_SKIP, s.id))
        builder.addAction(action(R.drawable.ic_action_stop, R.string.action_stop, TimerService.ACTION_STOP, s.id))
    }

    private fun multiple(builder: NotificationCompat.Builder, all: List<TimerSnapshot>) {
        val running = all.filter { !it.paused }
        builder.setContentTitle(
            context.resources.getQuantityString(R.plurals.notif_timers_active, all.size, all.size),
        )
        val lines = all.map { s ->
            val detail = if (s.paused) context.getString(R.string.notif_paused) else stepText(s)
            "${s.name} · $detail"
        }
        builder.setContentText(lines.first())
        builder.setStyle(NotificationCompat.InboxStyle().also { style -> lines.forEach(style::addLine) })
        val soonest = running.minOfOrNull { it.stepRemainingMs }
        if (soonest != null) countdown(builder, soonest) else builder.setShowWhen(false)

        if (running.isEmpty()) {
            builder.addAction(action(R.drawable.ic_action_play, R.string.action_resume_all, TimerService.ACTION_RESUME_ALL, null))
        } else {
            builder.addAction(action(R.drawable.ic_action_pause, R.string.action_pause_all, TimerService.ACTION_PAUSE_ALL, null))
        }
        builder.addAction(action(R.drawable.ic_action_stop, R.string.action_stop_all, TimerService.ACTION_STOP_ALL, null))
    }

    private fun countdown(builder: NotificationCompat.Builder, remainingMs: Long) {
        builder.setWhen(System.currentTimeMillis() + remainingMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
    }

    private fun stepText(s: TimerSnapshot): String = when {
        s.inLeadIn -> context.getString(R.string.notif_get_ready)
        s.kind == TimerConfig.KIND_INTERVAL && s.rounds > 0 ->
            context.getString(R.string.notif_chime_of, s.round, s.rounds)
        s.kind == TimerConfig.KIND_INTERVAL -> context.getString(R.string.notif_next_chime)
        s.rounds > 0 -> context.getString(R.string.notif_step_round_of, s.stepLabel, s.round, s.rounds)
        else -> context.getString(R.string.notif_step_round, s.stepLabel, s.round)
    }

    private fun action(icon: Int, title: Int, action: String, timerId: String?): NotificationCompat.Action {
        val intent = Intent(context, TimerService::class.java).setAction(action)
        if (timerId != null) intent.putExtra(TimerService.EXTRA_TIMER_ID, timerId)
        val pending = PendingIntent.getService(
            context,
            (action + (timerId ?: "")).hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Action.Builder(icon, context.getString(title), pending).build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val CHANNEL_ID = "running_timers"
        const val NOTIFICATION_ID = 1001

        fun clock(ms: Long): String {
            val totalSeconds = (ms + 999) / 1000
            val h = totalSeconds / 3600
            val m = (totalSeconds % 3600) / 60
            val s = totalSeconds % 60
            return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
        }
    }
}
