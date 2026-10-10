package com.meufilhoseguro.meu_filho_seguro

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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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
        private const val OFFLINE_NOTIF_ID = 1004

        /** Sem localização há mais de 5 min = filho offline. */
        private const val OFFLINE_AFTER_MS = 5 * 60 * 1000L
        /** Verifica offline a cada 60 s (1 leitura por filho/min: barato). */
        private const val OFFLINE_CHECK_MS = 60 * 1000L

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

    /**
     * Verificação periódica de filho offline (sem localização há +5 min).
     * Roda a cada 60 s enquanto a vigilância estiver ativa — assim o
     * responsável é avisado mesmo com o app fechado.
     */
    private val offlineHandler = Handler(Looper.getMainLooper())

    /** Episódios de offline já notificados: "childId:updatedAtMillis". */
    private val offlineAlerted = mutableSetOf<String>()

    private val offlineCheck = object : Runnable {
        override fun run() {
            if (running) {
                checkOfflineChildren()
                offlineHandler.postDelayed(this, OFFLINE_CHECK_MS)
            }
        }
    }

    /** GuardianId deste responsável (para filtrar os filhos dele). */
    private var watchGuardianId: String? = null

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
        watchGuardianId = guardianId
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

        // Verificação periódica de filho offline (mesmo com app fechado).
        offlineHandler.removeCallbacks(offlineCheck)
        offlineHandler.postDelayed(offlineCheck, OFFLINE_CHECK_MS)
    }

    /**
     * Verifica se algum filho deste responsável está sem enviar
     * localização há mais de 5 minutos (celular desligado, sem internet
     * ou app morto). Notifica 1x por episódio de offline.
     *
     * Limitação honesta: um celular desligado NÃO pode ser rastreado
     * (sem GPS, sem internet). Este alerta informa que o rastreamento
     * parou — e o app mostra a última posição conhecida.
     */
    private fun checkOfflineChildren() {
        val gid = watchGuardianId ?: return
        val db = FirebaseFirestore.getInstance()
        // Junta as duas formas de vínculo (responsável principal e
        // multi-responsável) sem exigir índice composto.
        val found = mutableMapOf<String, com.google.firebase.firestore.DocumentSnapshot>()
        var pending = 2
        fun maybeDone() {
            if (--pending != 0) return
            val now = System.currentTimeMillis()
            for ((childId, doc) in found) {
                val ts = doc.getTimestamp("updatedAt") ?: continue
                val staleMs = now - ts.toDate().time
                val episodeKey = "$childId:${ts.toDate().time}"
                if (staleMs >= OFFLINE_AFTER_MS) {
                    if (offlineAlerted.add(episodeKey)) {
                        val name = doc.getString("childName") ?: "Seu filho"
                        showOfflineNotification(childId, name, ts.toDate().time)
                    }
                } else {
                    // Voltou a enviar: libera novos alertas futuros.
                    offlineAlerted.removeAll { it.startsWith("$childId:") }
                    try {
                        (getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager)
                            .cancel(childId.hashCode())
                    } catch (e: Exception) { }
                }
            }
        }
        db.collection("locations")
            .whereEqualTo("guardianId", gid)
            .get()
            .addOnSuccessListener { snap ->
                for (d in snap.documents) found[d.id] = d
                maybeDone()
            }
            .addOnFailureListener { maybeDone() }
        db.collection("locations")
            .whereArrayContains("guardianIds", gid)
            .get()
            .addOnSuccessListener { snap ->
                for (d in snap.documents) found[d.id] = d
                maybeDone()
            }
            .addOnFailureListener { maybeDone() }
    }

    /**
     * Notificação de filho offline: prioridade alta, visível na tela de
     * bloqueio. Tocar abre o app. É cancelada quando o filho volta a
     * enviar a localização.
     */
    private fun showOfflineNotification(
        childId: String,
        childName: String,
        lastUpdateMs: Long
    ) {
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, childId.hashCode(), openApp,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val mins = ((System.currentTimeMillis() - lastUpdateMs) / 60000).toInt()
        val ago = if (mins < 60) "há $mins min" else {
            val h = mins / 60
            val m = mins % 60
            if (m == 0) "há $h h" else "há $h h $m min"
        }
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("⚠️ $childName está offline")
            .setContentText(
                "Sem localização $ago. Pode ser celular desligado ou " +
                    "sem internet. O mapa mostra a última posição conhecida."
            )
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pending)
            .setAutoCancel(false)
            .setOngoing(false)
            .build()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.notify(childId.hashCode(), notification)
    }

    /**
     * SOS chegou: toca o alarme e mostra a tela de emergência estilo
     * Defesa Civil SEMPRE — com o app aberto, fechado ou com a tela
     * bloqueada, sem nenhuma barreira.
     *
     * O som não duplica: o Flutter verifica `isAlarming` antes de tocar
     * o próprio alarme (ver `SosAlarmService.triggerAlarm`).
     */
    private fun onSosAlert(id: String, childName: String) {
        playAlarmSound()
        showAlertNotification(id, childName)
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

    /**
     * Notificação de emergência estilo Defesa Civil:
     * - Abre a [EmergencyAlertActivity] em TELA CHEIA por cima da tela
     *   bloqueada (fullScreenIntent + showWhenLocked/turnScreenOn)
     * - Vibração forte em padrão de emergência + LED vermelho
     * - Ongoing: não pode ser arrastada para fora; só "MARCAR COMO VISTO"
     *   na tela de emergência dispensa o alerta.
     */
    private fun showAlertNotification(id: String, childName: String) {
        val emergencyIntent =
            Intent(this, EmergencyAlertActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EmergencyAlertActivity.EXTRA_ALERT_ID, id)
                putExtra(EmergencyAlertActivity.EXTRA_CHILD_NAME, childName)
            }
        val pending = PendingIntent.getActivity(
            this, id.hashCode(), emergencyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Full-screen intent: abre a tela de emergência por cima do bloqueio.
        val fullScreen = PendingIntent.getActivity(
            this, id.hashCode() + 1, emergencyIntent,
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
            .setVibrate(longArrayOf(0, 800, 400, 800, 400, 800))
            .setLights(
                android.graphics.Color.RED, 1000, 500
            )
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
        // Deleta e recria o canal de alerta para garantir que as novas
        // configurações (vibração Defesa Civil) valham para quem já tinha
        // o app instalado — canal existente não atualiza sozinho.
        nm.deleteNotificationChannel(ALERT_CHANNEL_ID)
        val alertChannel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "Alerta SOS",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerta de emergência quando o filho aciona o SOS"
            lockscreenVisibility =
                android.app.Notification.VISIBILITY_PUBLIC
            // Estilo Defesa Civil: vibração forte no padrão de emergência.
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            enableLights(true)
            lightColor = android.graphics.Color.RED
        }
        nm.createNotificationChannel(alertChannel)
    }

    private fun stopWatch() {
        running = false
        offlineHandler.removeCallbacks(offlineCheck)
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
        offlineHandler.removeCallbacks(offlineCheck)
        try { listener?.remove() } catch (e: Exception) { }
        stopAlarmSound()
        super.onDestroy()
    }
}
