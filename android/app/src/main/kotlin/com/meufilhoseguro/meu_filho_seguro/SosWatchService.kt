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

        /**
         * Ação de TESTE (v14): dispara o caminho COMPLETO do alerta
         * (tela + som + notificação) sem precisar de um SOS real no
         * Firestore. Serve para o dono validar o comportamento com a
         * tela bloqueada. O "MARCAR COMO VISTO" encerra normalmente.
         */
        const val ACTION_TEST_ALERT = "com.meufilhoseguro.app.WATCH_TEST_ALERT"
        const val EXTRA_TEST_CHILD_NAME = "test_child_name"

        /**
         * Broadcast enviado quando o alerta é encerrado (MARCAR COMO
         * VISTO em qualquer lugar): a tela de emergência nativa e o
         * alarme da MainActivity fecham/param — nada fica em 2º plano.
         */
        const val ACTION_CLOSE_EMERGENCY = "com.meufilhoseguro.app.CLOSE_EMERGENCY"

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
        private const val KEY_GUARDIAN_IDS = "guardian_ids"
        private const val SETTINGS_PREFS = "mfs_settings"
        private const val KEY_ALARM_SOUND = "alarm_sound_uri"

        /** Verdadeiro enquanto este serviço estiver tocando o alarme. */
        @Volatile
        var isAlarming: Boolean = false
            private set
    }

    private val listeners = mutableListOf<ListenerRegistration>()
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

    /**
     * IDs deste responsável (para filtrar os alertas dele).
     * É um CONJUNTO porque o ID local pode mudar (ex.: reinstalou o app
     * e o login reconstruiu o perfil com ID novo): mantemos os IDs
     * antigos ouvindo também, até o Firestore ser atualizado — assim o
     * alerta chega neste aparelho mesmo durante a transição.
     */
    private var watchGuardianIds: Set<String> = emptySet()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopWatch()
                return START_NOT_STICKY
            }
            ACTION_STOP_ALARM -> {
                stopAlarmSound()
                // Fecha a tela de emergência nativa onde quer que esteja
                // (aberta, em 2º plano ou na tela bloqueada) e manda a
                // MainActivity parar o som dela também.
                sendBroadcast(
                    Intent(ACTION_CLOSE_EMERGENCY).setPackage(packageName)
                )
                return START_STICKY
            }
            ACTION_TEST_ALERT -> {
                // Teste de ponta a ponta pedido pelo dono: passa pelo
                // MESMO caminho de um SOS real (tela + som + notificação).
                val name = intent.getStringExtra(EXTRA_TEST_CHILD_NAME)
                    ?.takeIf { it.isNotBlank() } ?: "Seu filho"
                // Garante que o serviço está em primeiro plano antes.
                startWatch()
                onSosAlert("test_${System.currentTimeMillis()}", name)
                return START_STICKY
            }
            else -> startWatch()
        }
        return START_STICKY
    }

    private fun startWatch() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val guardianId = prefs.getString(KEY_GUARDIAN_ID, null)
        if (guardianId.isNullOrEmpty()) {
            stopSelf()
            return
        }
        // Acumula os IDs já vistos (o ID local pode mudar com o tempo).
        val known = prefs.getStringSet(KEY_GUARDIAN_IDS, null)
            ?.toMutableSet() ?: mutableSetOf()
        known.add(guardianId)
        prefs.edit().putStringSet(KEY_GUARDIAN_IDS, known).apply()

        // Se já está rodando com o MESMO conjunto de IDs, nada a fazer.
        // Se o conjunto mudou (ID novo), reanexa os listeners — antes o
        // `if (running) return` mantinha o filtro do ID antigo para sempre.
        if (running && watchGuardianIds == known) return
        if (running) {
            for (l in listeners) {
                try { l.remove() } catch (e: Exception) { }
            }
            listeners.clear()
        }
        watchGuardianIds = known.toSet()
        running = true

        createChannels()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Meu Filho Seguro")
            .setContentText("Monitorando alertas SOS")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .build()
        try {
            startForeground(NOTIF_ID, notification)
        } catch (e: Exception) {
            // Android 12+: se o serviço foi iniciado em 2º plano e o
            // sistema recusar o foreground, não adianta seguir como
            // "zumbi" — o SO vai matar o serviço de qualquer jeito.
            e.printStackTrace()
            stopSelf()
            return
        }

        // Ouve SOS deste responsável (filtro de ack feito no cliente para
        // não exigir índice composto no Firestore).
        // Usa o array `guardianIds` (não o campo único `guardianId`) para
        // que TODOS os responsáveis vinculados (pai e mãe) recebam o alerta.
        // Um listener por ID conhecido: cobre o período de transição em que
        // o Firestore ainda tem o ID antigo (o `alarmedIds` evita duplicar).
        val db = FirebaseFirestore.getInstance()
        for (gid in watchGuardianIds) {
            listeners.add(
                db.collection("sos_alerts")
                    .whereArrayContains("guardianIds", gid)
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
            )
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
        val gids = watchGuardianIds
        if (gids.isEmpty()) return
        val db = FirebaseFirestore.getInstance()
        // Junta as duas formas de vínculo (responsável principal e
        // multi-responsável) sem exigir índice composto. Consulta com
        // todos os IDs conhecidos deste aparelho.
        val found = mutableMapOf<String, com.google.firebase.firestore.DocumentSnapshot>()
        val queries = mutableListOf<com.google.android.gms.tasks.Task<com.google.firebase.firestore.QuerySnapshot>>()
        for (gid in gids) {
            queries.add(db.collection("locations").whereEqualTo("guardianId", gid).get())
            queries.add(db.collection("locations").whereArrayContains("guardianIds", gid).get())
        }
        var pending = queries.size
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
        for (q in queries) {
            q.addOnSuccessListener { snap ->
                for (d in snap.documents) found[d.id] = d
                maybeDone()
            }.addOnFailureListener { maybeDone() }
        }
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
     * Estratégia em 3 camadas (a primeira que funcionar vence):
     * 1. Notificação com fullScreenIntent (caminho OFICIAL do Android —
     *    o único que funciona com a tela bloqueada no Android 10+).
     *    No Android 14+ exige a permissão "alertas em tela cheia"
     *    liberada pelo usuário nas configurações (o app orienta).
     * 2. Abertura DIRETA da EmergencyAlertActivity (fallback para
     *    Android < 10 e para casos em que o fullScreenIntent é
     *    ignorado). Em Android 10+ o sistema pode bloquear a abertura
     *    vinda de 2º plano — por isso o try/catch: melhor esforço.
     * 3. WakeLock breve para acender a tela.
     *
     * v14 — ordem refeita: a notificação (camada oficial) é postada
     * ANTES da abertura direta, e o som toca depois dela. Antes, o
     * `MediaPlayer.prepare()` (síncrono, na thread principal) atrasava
     * a postagem da notificação.
     *
     * O som não duplica: o Flutter verifica `isAlarming` antes de tocar
     * o próprio alarme (ver `SosAlarmService.triggerAlarm`).
     */
    private fun onSosAlert(id: String, childName: String) {
        // Acorda a tela PRIMEIRO: a fullScreenIntent e a abertura direta
        // funcionam melhor com a tela já acesa (principalmente bloqueada).
        wakeScreen()
        // 1) Caminho oficial: notificação com fullScreenIntent.
        showAlertNotification(id, childName)
        // 2) Som do alarme.
        playAlarmSound()
        // 3) Fallback: abertura direta da tela de emergência.
        launchEmergencyScreenDirect(id, childName)
        // CORREÇÃO (bug "não aparece com tela bloqueada"): tenta de novo
        // após 1,5 s. Na primeira tentativa a tela pode ainda estar
        // apagando/acordando e o sistema bloqueia a abertura ("Background
        // activity start blocked"); com a tela já acesa pelo WakeLock, a
        // segunda tentativa tem chance muito maior em vários aparelhos.
        // Se a primeira já abriu, o singleTop só atualiza o intent.
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                launchEmergencyScreenDirect(id, childName)
            } catch (e: Exception) { }
        }, 1500)
    }

    /**
     * Fallback: abre a tela de emergência diretamente, sem depender do
     * fullScreenIntent da notificação.
     *
     * v14 — CORREÇÃO do "some sozinha": REMOVIDO o
     * FLAG_ACTIVITY_CLEAR_TASK. Ele destruía a tarefa do app (incluindo
     * a MainActivity), e o `onDestroy()` da MainActivity parava o alarme
     * do serviço + transmitia CLOSE_EMERGENCY — ou seja, a tela de
     * emergência recém-aberta era fechada pelo próprio app. Agora a
     * tela de emergência abre numa tarefa nova SEM matar a tarefa
     * atual (NEW_TASK + SINGLE_TOP, igual ao intent da notificação).
     *
     * Em Android 10+ o sistema pode bloquear a abertura vinda de 2º
     * plano ("Background activity start blocked") — por isso o
     * try/catch: é melhor esforço, sem crash.
     */
    private fun launchEmergencyScreenDirect(id: String, childName: String) {
        try {
            val intent =
                Intent(this, EmergencyAlertActivity::class.java).apply {
                    // NEW_TASK: a tela de emergência vem para a frente por
                    // cima de qualquer coisa (inclusive da tela bloqueada,
                    // junto com showWhenLocked/turnScreenOn da activity).
                    // SEM CLEAR_TASK: não destrói a MainActivity (evita a
                    // cascata onDestroy -> stopAlarm -> CLOSE_EMERGENCY que
                    // fechava a própria tela de emergência).
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(EmergencyAlertActivity.EXTRA_ALERT_ID, id)
                    putExtra(EmergencyAlertActivity.EXTRA_CHILD_NAME, childName)
                }
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Acende a tela por alguns segundos para o alerta ser visto mesmo
     * com o aparelho bloqueado/em repouso. A permissão WAKE_LOCK já está
     * no manifest.
     */
    private fun wakeScreen() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE)
                as android.os.PowerManager
            // SCREEN_BRIGHT_WAKE_LOCK (não o depreciado FULL_WAKE_LOCK):
            // acende a tela com brilho por cima do bloqueio.
            val wl = pm.newWakeLock(
                android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    android.os.PowerManager.ON_AFTER_RELEASE,
                "mfs:sos_wake"
            )
            // Solta sozinho após 20 s.
            wl.acquire(20 * 1000L)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun playAlarmSound() {
        stopAlarmSound()
        // Evita som duplo: se o app aberto (MainActivity) já está
        // tocando o alarme via Flutter, o nativo não toca de novo.
        // A tela de emergência e a notificação continuam normalmente.
        try {
            if (MainActivity.isAlarmPlaying) {
                isAlarming = true
                return
            }
        } catch (e: Exception) { }
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
        for (l in listeners) {
            try { l.remove() } catch (e: Exception) { }
        }
        listeners.clear()
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
        for (l in listeners) {
            try { l.remove() } catch (e: Exception) { }
        }
        listeners.clear()
        stopAlarmSound()
        super.onDestroy()
    }
}
