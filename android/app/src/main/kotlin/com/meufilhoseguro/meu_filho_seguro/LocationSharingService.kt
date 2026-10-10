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
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.firebase.Timestamp
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
 */
class LocationSharingService : Service() {

    companion object {
        const val ACTION_START = "com.meufilhoseguro.app.START_SHARING"
        const val ACTION_STOP = "com.meufilhoseguro.app.STOP_SHARING"

        private const val CHANNEL_ID = "location_sharing_channel"
        private const val NOTIF_ID = 1001
        private const val INTERVAL_MS = 2_000L

        private const val PREFS = "mfs_sharing"
        private const val KEY_CHILD_ID = "child_id"
        private const val KEY_CHILD_NAME = "child_name"
        private const val KEY_GUARDIAN_ID = "guardian_id"
    }

    private val fused by lazy {
        LocationServices.getFusedLocationProviderClient(this)
    }
    private var running = false

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val loc = result.lastLocation ?: return
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
                    prefs.edit()
                        .putString(KEY_CHILD_ID, childId)
                        .putString(
                            KEY_CHILD_NAME,
                            intent.getStringExtra(KEY_CHILD_NAME) ?: ""
                        )
                        .putString(
                            KEY_GUARDIAN_ID,
                            intent.getStringExtra(KEY_GUARDIAN_ID) ?: ""
                        )
                        .apply()
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
        } catch (e: SecurityException) {
            // Sem permissão de localização: não há o que fazer.
            stopSharing()
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

            val data: HashMap<String, Any> = hashMapOf(
                "childId" to childId,
                "childName" to childName,
                "guardianId" to guardianId,
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
        try {
            fused.removeLocationUpdates(locationCallback)
        } catch (e: Exception) {
            // Ignora.
        }
        super.onDestroy()
    }
}
