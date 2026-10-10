package com.meufilhoseguro.meu_filho_seguro

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ALARM_CHANNEL = "com.meufilhoseguro.app/sos_alarm"
    private val SHARING_CHANNEL = "com.meufilhoseguro.app/sharing"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playAlarm" -> {
                        playAlarm()
                        result.success(null)
                    }
                    "stopAlarm" -> {
                        stopAlarm()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startSharing" -> {
                        val intent = Intent(
                            this,
                            LocationSharingService::class.java
                        ).setAction(LocationSharingService.ACTION_START)
                        call.argument<String>("childId")?.let {
                            intent.putExtra("child_id", it)
                        }
                        call.argument<String>("childName")?.let {
                            intent.putExtra("child_name", it)
                        }
                        call.argument<String>("guardianId")?.let {
                            intent.putExtra("guardian_id", it)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopSharing" -> {
                        val intent = Intent(
                            this,
                            LocationSharingService::class.java
                        ).setAction(LocationSharingService.ACTION_STOP)
                        startService(intent)
                        // Limpa a configuração salva para não reiniciar sozinho.
                        getSharedPreferences(
                            "mfs_sharing",
                            Context.MODE_PRIVATE
                        ).edit().clear().apply()
                        result.success(null)
                    }
                    "isSharing" -> {
                        result.success(isServiceRunning())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isServiceRunning(): Boolean {
        val manager =
            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        for (service in manager.getRunningServices(Int.MAX_VALUE)) {
            if (service.service.className ==
                LocationSharingService::class.java.name
            ) {
                return true
            }
        }
        return false
    }

    /**
     * Toca o som de alarme do sistema em loop no canal ALARME.
     * O canal ALARME (AudioAttributes.USAGE_ALARM) não é afetado pelo
     * modo silencioso, e alarmes são exceção padrão do "Não perturbe".
     */
    private fun playAlarm() {
        stopAlarm()
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            // Volume máximo no canal de alarme para garantir que seja ouvido.
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVol, 0)

            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(this@MainActivity, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopAlarm() {
        try {
            mediaPlayer?.stop()
        } catch (e: Exception) {
            // já parado
        }
        try {
            mediaPlayer?.release()
        } catch (e: Exception) {
            // já liberado
        }
        mediaPlayer = null
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
