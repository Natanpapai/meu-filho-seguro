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
    private val SETTINGS_PREFS = "mfs_settings"
    private val KEY_ALARM_SOUND = "alarm_sound_uri"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playAlarm" -> {
                        playAlarm(call.argument<String>("soundUri"))
                        result.success(null)
                    }
                    "stopAlarm" -> {
                        stopAlarm()
                        result.success(null)
                    }
                    "getAlarmSounds" -> {
                        result.success(getAlarmSounds())
                    }
                    "previewAlarm" -> {
                        previewAlarm(call.argument<String>("uri"))
                        result.success(null)
                    }
                    "saveAlarmSound" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                            .edit().putString(KEY_ALARM_SOUND, uri).apply()
                        result.success(null)
                    }
                    "getAlarmSound" -> {
                        val uri = getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                            .getString(KEY_ALARM_SOUND, "") ?: ""
                        result.success(uri)
                    }
                    "startWatch" -> {
                        val gid = call.argument<String>("guardianId") ?: ""
                        getSharedPreferences("mfs_sos_watch", Context.MODE_PRIVATE)
                            .edit().putString("guardian_id", gid).apply()
                        val intent = Intent(this, SosWatchService::class.java)
                            .setAction(SosWatchService.ACTION_START)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopWatch" -> {
                        val intent = Intent(this, SosWatchService::class.java)
                            .setAction(SosWatchService.ACTION_STOP)
                        startService(intent)
                        getSharedPreferences("mfs_sos_watch", Context.MODE_PRIVATE)
                            .edit().clear().apply()
                        result.success(null)
                    }
                    "isWatchAlarming" -> {
                        result.success(SosWatchService.isAlarming)
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
     * Toca o som de alarme em loop no canal ALARME.
     * O canal ALARME (AudioAttributes.USAGE_ALARM) não é afetado pelo
     * modo silencioso, e alarmes são exceção padrão do "Não perturbe".
     *
     * Usa o som escolhido pelo usuário (salvo em mfs_settings), ou o
     * [soundUri] passado explicitamente (pré-visualização), ou o alarme
     * padrão do sistema como fallback.
     */
    private fun playAlarm(soundUri: String? = null) {
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

            val saved = getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_ALARM_SOUND, "")
            val chosen = soundUri?.takeIf { it.isNotEmpty() }
                ?: saved?.takeIf { it.isNotEmpty() }
            val alarmUri = chosen?.let {
                try { android.net.Uri.parse(it) } catch (e: Exception) { null }
            }
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
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

    /**
     * Toca o som UMA vez (sem loop) para pré-visualização na tela de
     * configuração. Não mexe no volume do sistema.
     * Se [uri] for vazio, usa o alarme padrão do sistema.
     */
    private fun previewAlarm(uri: String?) {
        stopAlarm()
        try {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val soundUri = uri?.takeIf { it.isNotEmpty() }?.let {
                try { android.net.Uri.parse(it) } catch (e: Exception) { null }
            }
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: return
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(this@MainActivity, soundUri)
                isLooping = false
                prepare()
                start()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Lista os sons de alarme disponíveis no sistema.
     * Retorna lista de mapas {title, uri}.
     */
    private fun getAlarmSounds(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        try {
            val rm = RingtoneManager(this)
            rm.setType(RingtoneManager.TYPE_ALARM)
            val cursor = rm.cursor
            while (cursor.moveToNext()) {
                val title =
                    cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                val uri = rm.getRingtoneUri(cursor.position).toString()
                out.add(mapOf("title" to title, "uri" to uri))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        if (out.isEmpty()) {
            val def = RingtoneManager
                .getDefaultUri(RingtoneManager.TYPE_ALARM)?.toString() ?: ""
            out.add(mapOf("title" to "Alarme padrão do sistema", "uri" to def))
        }
        return out
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
        // Também para o alarme do serviço de vigilância, se estiver tocando.
        try {
            val intent = Intent(this, SosWatchService::class.java)
                .setAction(SosWatchService.ACTION_STOP_ALARM)
            startService(intent)
        } catch (e: Exception) {
            // Serviço pode não existir ainda.
        }
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }
}
