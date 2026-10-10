package com.meufilhoseguro.meu_filho_seguro

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * Serviço em primeiro plano que vigia alertas SOS no Firestore mesmo
 * com o app fechado ou a tela bloqueada.
 *
 * - Ouve a coleção `sos_alerts` filtrando pelo guardianId do responsável.
 * - Quando chega um SOS novo e o app NÃO está em primeiro plano, toca o
 *   alarme nativamente (canal ALARME: fura silencioso e Não Perturbe) e
 *   mostra notificação de prioridade máxima que abre o app ao tocar.
 * - Se o app estiver aberto, o Flutter cuida do som (evita som duplo).
 * - START_STICKY: reinicia sozinho se o sistema o matar.
 */
class SosWatchService : Service() {

    companion object {
        const val ACTION_START = "com.meufilhoseguro.app.WATCH_START"
        const val ACTION_STOP = "com.meufilhoseguro.app.WATCH_STOP"
        const val ACTION_STOP_ALARM = "com.meufilhoseguro.app.WATCH_STOP_ALARM"

        private const val CHANNEL_ID = "sos_watch_channel"
        private const val ALERT_CHANNEL_ID = "sos_alert_channel"
        private const val NOTIF_ID = 1002
        private const val ALERT_NOTIF_ID = 1003

        private const val PREFS = "mfs_sos_watch"
        private const val KEY_GUARDIAN_ID = "guardian_id"
        private const val SETTINGS_PREFS = "mfs_settings"
        private const val KEY_ALARM_SOUND = "alarm_sound_uri"

        /** Verdadeiro enquanto este serviço estiver tocando o alarme. */
        @Volatile
        var isAlarming: Boolean = false
            private set
    }

    private var listener: ListenerRegistration? = null
    private var mediaPlayer: MediaPlayer? = null
    private val alarmedIds = mutableSetOf<String>()
    private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopWatch()
                return START_NOT_STICKY
            }
            ACTION_STOP_ALARM -> {
                stopAlarmSound()
                return START_STICKY
            }
            else -> startWatch()
        }
        return START_STICKY
    }

    private fun startWatch() {
        if (running) return
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val guardianId = prefs.getString(KEY_GUARDIAN_ID, null)
        if (guardianId.isNullOrEmpty()) {
            stopSelf()
            return
        }
        running = true

        createChannels()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Meu Filho Seguro")
            .setContentText("Monitorando alertas SOS")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .build()
        startForeground(NOTIF_ID, notification)

        // Ouve SOS deste responsável (filtro de ack feito no cliente para
        // não exigir índice composto no Firestore).
        listener = FirebaseFirestore.getInstance()
            .collection("sos_alerts")
            .whereEqualTo("guardianId", guardianId)
            .addSnapshotListener { snap, _ ->
                if (snap == null) return@addSnapshotListener
                for (doc in snap.documents) {
                    val ack = doc.getBoolean("ack") ?: false
                    if (ack) continue
                    val id = doc.id
                    if (!alarmedIds.add(id)) continue
                    // Ignora alertas antigos (ex.: serviço reiniciado).
                    val ts = doc.getTimestamp("timestamp")?.toDate()
                    if (ts != null &&
                        System.currentTimeMillis() - ts.time > 30 * 60 * 1000
                    ) continue
                    onSosAlert(
                        id,
                        doc.getString("childName") ?: "Seu filho"
                    )
                }
            }
    }

    private fun onSosAlert(id: String, childName: String) {
        // Se o app estiver aberto, o Flutter toca o som (evita duplicar).
        if (isAppInForeground()) return
        playAlarmSound()
        showAlertNotification(id, childName)
    }

    private fun isAppInForeground(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val procs = am.runningAppProcesses ?: return false
        for (p in procs) {
            if (p.processName == packageName) {
                return p.importance ==
                    ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        }
        return false
    }

    private fun playAlarmSound() {
        stopAlarmSound()
        try {
            val audioManager =
                getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol =
                audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)

            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val saved = getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_ALARM_SOUND, "")
            val alarmUri = saved?.takeIf { it.isNotEmpty() }?.let {
                try { android.net.Uri.parse(it) } catch (e: Exception) { null }
            }
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(this@SosWatchService, alarmUri)
                isLooping = true
                prepare()
                start()
            }
            isAlarming = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAlarmSound() {
        try { mediaPlayer?.stop() } catch (e: Exception) { }
        try { mediaPlayer?.release() } catch (e: Exception) { }
        mediaPlayer = null
        isAlarming = false
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.cancel(ALERT_NOTIF_ID)
        } catch (e: Exception) { }
    }

    private fun showAlertNotification(id: String, childName: String) {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, id.hashCode(), openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Full-screen intent: abre o app por cima da tela bloqueada.
        val fullScreen = PendingIntent.getActivity(
            this, id.hashCode() + 1, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("🆘 SOS ACIONADO!")
            .setContentText("$childName precisa de ajuda agora!")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pending)
            .setFullScreenIntent(fullScreen, true)
            .setAutoCancel(false)
            .setOngoing(true)
            .build()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.notify(ALERT_NOTIF_ID, notification)
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Vigilância SOS",
                NotificationManager.IMPORTANCE_LOW
            )
        )
        val alertChannel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "Alerta SOS",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerta de emergência quando o filho aciona o SOS"
            lockscreenVisibility =
                android.app.Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(alertChannel)
    }

    private fun stopWatch() {
        running = false
        try { listener?.remove() } catch (e: Exception) { }
        listener = null
        stopAlarmSound()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        try { listener?.remove() } catch (e: Exception) { }
        stopAlarmSound()
        super.onDestroy()
    }
}
