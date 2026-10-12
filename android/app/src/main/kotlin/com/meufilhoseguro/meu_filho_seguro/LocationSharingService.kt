package com.meufilhoseguro.meu_filho_seguro

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions

/**
 * Serviço em primeiro plano que envia a localização do filho ao
 * Firestore a cada 5 segundos — é o que permite ao responsável ver
 * o filho se movendo no mapa em tempo real, estilo Uber.
 *
 * - Notificação persistente (Android exige para foreground service).
 * - Usa o SDK nativo do Firestore (já inicializado pelo plugin Flutter).
 * - START_STICKY: se o sistema matar o serviço, ele reinicia sozinho
 *   lendo a configuração salva em SharedPreferences.
 *
 * v15 (PROBLEMA 1 — passinhos constantes): a amostragem do histórico
 * (`history/{childId}/points`, a cada 2 min) e a limpeza de pontos com
 * mais de 7 dias rodam AQUI DENTRO do serviço nativo. Antes, a
 * amostragem era um Timer do Flutter que só funcionava com o app do
 * filho ABERTO — app fechado = amostragem parada = buracos no
 * histórico. Dentro do foreground service ela continua funcionando
 * mesmo com o app fechado.
 */
class LocationSharingService : Service() {

    companion object {
        const val ACTION_START = "com.meufilhoseguro.app.START_SHARING"
        const val ACTION_STOP = "com.meufilhoseguro.app.STOP_SHARING"

        private const val CHANNEL_ID = "location_sharing_channel"
        private const val NOTIF_ID = 1001
        private const val INTERVAL_MS = 4_000L

        // Amostragem do histórico: a cada 2 min (mesma cadência do
        // antigo Timer do Flutter, agora dentro do serviço nativo).
        private const val HISTORY_INTERVAL_MS = 120_000L
        // Retenção do histórico no Firestore: 7 dias (igual ao
        // HistoryService.cleanupOldPoints do Flutter).
        private const val HISTORY_RETENTION_MS = 7L * 24 * 60 * 60 * 1000
        private const val KEY_LAST_HISTORY_CLEANUP = "last_history_cleanup"

        private const val PREFS = "mfs_sharing"
        private const val KEY_CHILD_ID = "child_id"
        private const val KEY_CHILD_NAME = "child_name"
        private const val KEY_GUARDIAN_ID = "guardian_id"
        private const val KEY_GUARDIAN_IDS = "guardian_ids"
    }

    private val fused by lazy {
        LocationServices.getFusedLocationProviderClient(this)
    }
    private var running = false

    // Última localização recebida: é ela que a amostragem do histórico
    // grava a cada 2 min (sem pedir GPS extra — sem custo de bateria
    // além do rastreamento que já roda).
    private var lastLocation: Location? = null

    private val historyHandler = Handler(Looper.getMainLooper())
    private val historySampler = object : Runnable {
        override fun run() {
            sampleHistoryPoint()
            maybeCleanupOldHistoryPoints()
            historyHandler.postDelayed(this, HISTORY_INTERVAL_MS)
        }
    }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val loc = result.lastLocation ?: return
            lastLocation = loc
            pushToFirestore(loc)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSharing()
                return START_NOT_STICKY
            }
            else -> {
                // Configuração via extras (primeira chamada vinda do Flutter).
                val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                intent?.getStringExtra(KEY_CHILD_ID)?.let { childId ->
                    val editor = prefs.edit()
                        .putString(KEY_CHILD_ID, childId)
                        .putString(
                            KEY_CHILD_NAME,
                            intent.getStringExtra(KEY_CHILD_NAME) ?: ""
                        )
                        .putString(
                            KEY_GUARDIAN_ID,
                            intent.getStringExtra(KEY_GUARDIAN_ID) ?: ""
                        )
                    // Multi-responsável: guarda a lista (pai e mãe).
                    intent.getStringArrayExtra(KEY_GUARDIAN_IDS)?.let { gids ->
                        editor.putStringSet(KEY_GUARDIAN_IDS, gids.toSet())
                    }
                    editor.apply()
                }
                startSharing()
            }
        }
        // Se o sistema matar o serviço, reinicia sozinho (lê config do prefs).
        return START_STICKY
    }

    private fun startSharing() {
        if (running) return
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val childId = prefs.getString(KEY_CHILD_ID, null)
        if (childId.isNullOrEmpty()) {
            // Sem configuração não há para quem enviar: não inicia.
            stopSelf()
            return
        }
        running = true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Compartilhamento de localização",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Meu Filho Seguro")
            .setContentText("Compartilhando localização com o responsável")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }

        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            INTERVAL_MS
        )
            .setMinUpdateIntervalMillis(INTERVAL_MS)
            .setMaxUpdateDelayMillis(INTERVAL_MS * 2)
            .build()

        try {
            fused.requestLocationUpdates(
                request,
                locationCallback,
                Looper.getMainLooper()
            )
            // Inicia a amostragem do histórico (a cada 2 min), que agora
            // roda junto do serviço — mesmo com o app fechado.
            historyHandler.removeCallbacks(historySampler)
            historyHandler.postDelayed(historySampler, HISTORY_INTERVAL_MS)
        } catch (e: SecurityException) {
            // Sem permissão de localização: não há o que fazer.
            stopSharing()
        }
    }

    /**
     * Amostragem do histórico do trajeto (v15 — PROBLEMA 1: passinhos
     * constantes).
     *
     * A cada 2 minutos grava a última localização conhecida em
     * `history/{childId}/points` (campos: lat, lng, battery,
     * timestamp=serverTimestamp). Antes, essa amostragem rodava num
     * Timer do Flutter que só funcionava com o app do filho ABERTO —
     * com o app fechado a amostragem parava e o histórico ficava com
     * buracos. Dentro do foreground service nativo ela continua
     * funcionando mesmo com o app fechado.
     */
    private fun sampleHistoryPoint() {
        val loc = lastLocation ?: return
        try {
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val childId = prefs.getString(KEY_CHILD_ID, null) ?: return

            val battery = (getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
                .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            val data: HashMap<String, Any> = hashMapOf(
                "lat" to loc.latitude,
                "lng" to loc.longitude,
                "battery" to battery.toLong(),
                "timestamp" to FieldValue.serverTimestamp()
            )

            FirebaseFirestore.getInstance()
                .collection("history")
                .document(childId)
                .collection("points")
                .add(data)
        } catch (e: Exception) {
            // Amostragem nunca deve derrubar o serviço.
        }
    }

    /**
     * Limpeza de pontos do histórico com mais de 7 dias (1x ao dia).
     * Antes era feita pelo app Flutter (HistoryService.cleanupOldPoints);
     * agora roda aqui dentro do serviço, junto da amostragem.
     */
    private fun maybeCleanupOldHistoryPoints() {
        try {
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val childId = prefs.getString(KEY_CHILD_ID, null) ?: return

            val today = java.text.SimpleDateFormat(
                "yyyy-MM-dd", java.util.Locale.US
            ).format(java.util.Date())
            if (prefs.getString(KEY_LAST_HISTORY_CLEANUP, "") == today) return
            prefs.edit().putString(KEY_LAST_HISTORY_CLEANUP, today).apply()

            val cutoff = Timestamp(
                java.util.Date(System.currentTimeMillis() - HISTORY_RETENTION_MS)
            )
            val db = FirebaseFirestore.getInstance()
            db.collection("history")
                .document(childId)
                .collection("points")
                .whereLessThan("timestamp", cutoff)
                .limit(200)
                .get()
                .addOnSuccessListener { snap ->
                    if (snap.isEmpty) return@addOnSuccessListener
                    val batch = db.batch()
                    for (doc in snap.documents) {
                        batch.delete(doc.reference)
                    }
                    batch.commit()
                }
        } catch (e: Exception) {
            // Limpeza nunca deve derrubar o serviço.
        }
    }

    private fun pushToFirestore(loc: Location) {
        try {
            val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val childId = prefs.getString(KEY_CHILD_ID, null) ?: return
            val childName = prefs.getString(KEY_CHILD_NAME, "") ?: ""
            val guardianId = prefs.getString(KEY_GUARDIAN_ID, "") ?: ""

            val battery = (getSystemService(Context.BATTERY_SERVICE) as BatteryManager)
                .getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            // Multi-responsável: inclui o array `guardianIds` para que
            // todos os responsáveis (pai e mãe) recebam os alertas.
            val gids = prefs.getStringSet(KEY_GUARDIAN_IDS, null)?.toList()
                ?: listOf(guardianId).filter { it.isNotEmpty() }

            val data: HashMap<String, Any> = hashMapOf(
                "childId" to childId,
                "childName" to childName,
                "guardianId" to guardianId,
                "guardianIds" to gids,
                "lat" to loc.latitude,
                "lng" to loc.longitude,
                "battery" to battery.toLong(),
                // Velocidade em m/s e direção em graus (0-360).
                "speed" to loc.speed.toDouble(),
                "heading" to loc.bearing.toDouble(),
                "updatedAt" to Timestamp.now()
            )

            FirebaseFirestore.getInstance()
                .collection("locations")
                .document(childId)
                .set(data, SetOptions.merge())
        } catch (e: Exception) {
            // Envio periódico nunca deve derrubar o serviço.
        }
    }

    private fun stopSharing() {
        running = false
        historyHandler.removeCallbacks(historySampler)
        try {
            fused.removeLocationUpdates(locationCallback)
        } catch (e: Exception) {
            // Ignora.
        }
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
        historyHandler.removeCallbacks(historySampler)
        try {
            fused.removeLocationUpdates(locationCallback)
        } catch (e: Exception) {
            // Ignora.
        }
        super.onDestroy()
    }

    /**
     * Se o usuário arrastar o app para fora dos recentes, o Android pode
     * matar o serviço. Como a config está salva em SharedPreferences,
     * tentamos reiniciar o compartilhamento imediatamente.
     * (Medida de segurança: o filho não deve conseguir interromper o
     * rastreamento fechando o app.)
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getString(KEY_CHILD_ID, null).isNullOrEmpty()) {
            val restart = Intent(this, LocationSharingService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(restart)
                } else {
                    startService(restart)
                }
            } catch (e: Exception) {
                // Em segundo plano restrito, o sistema pode recusar;
                // o START_STICKY ainda tenta recuperar.
            }
        }
        super.onTaskRemoved(rootIntent)
    }
}
