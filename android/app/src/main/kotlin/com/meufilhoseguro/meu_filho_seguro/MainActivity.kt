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
    companion object {
        /**
         * Verdadeiro enquanto a MainActivity estiver tocando o alarme
         * (via Flutter). O serviço de vigilância consulta para não
         * duplicar o som quando o app está aberto.
         */
        @Volatile
        var isAlarmPlaying: Boolean = false
    }

    private val ALARM_CHANNEL = "com.meufilhoseguro.app/sos_alarm"
    private val SHARING_CHANNEL = "com.meufilhoseguro.app/sharing"
    private val SETTINGS_PREFS = "mfs_settings"
    private val KEY_ALARM_SOUND = "alarm_sound_uri"
    private var mediaPlayer: MediaPlayer? = null
    private var closeReceiver: android.content.BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Quando o alerta é encerrado em qualquer lugar (MARCAR COMO
        // VISTO), para o som daqui também — nada fica tocando/visível
        // em 2º plano.
        closeReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                // Só o som local, SEM rebroadcast (evita loop).
                stopLocalAlarm()
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(
                    closeReceiver,
                    android.content.IntentFilter(
                        SosWatchService.ACTION_CLOSE_EMERGENCY
                    ),
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                registerReceiver(
                    closeReceiver,
                    android.content.IntentFilter(
                        SosWatchService.ACTION_CLOSE_EMERGENCY
                    )
                )
            }
        } catch (e: Exception) { }
    }

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
                    "stopPreview" -> {
                        // Para só a pré-visualização local, sem os efeitos
                        // colaterais do stopAlarm (que acorda o serviço e
                        // transmite CLOSE_EMERGENCY).
                        stopLocalAlarm()
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
                        val prefs = getSharedPreferences("mfs_sos_watch", Context.MODE_PRIVATE)
                        prefs.edit().putString("guardian_id", gid).apply()
                        // Acumula os IDs (o ID local pode mudar com o tempo):
                        // o serviço ouve todos, sem quebrar o atual.
                        if (gid.isNotEmpty()) {
                            val set = prefs.getStringSet("guardian_ids", null)
                                ?.toMutableSet() ?: mutableSetOf()
                            set.add(gid)
                            prefs.edit().putStringSet("guardian_ids", set).apply()
                        }
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
                    // Android 14+: a permissão de notificações em tela
                    // cheia (USE_FULL_SCREEN_INTENT) precisa ser liberada
                    // pelo usuário nas configurações do sistema — sem
                    // isso, a tela de emergência estilo Defesa Civil não
                    // abre por cima da tela bloqueada.
                    "canUseFullScreenIntent" -> {
                        val granted = if (Build.VERSION.SDK_INT >= 34) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                                as android.app.NotificationManager
                            nm.canUseFullScreenIntent()
                        } else {
                            true
                        }
                        result.success(granted)
                    }
                    "openFullScreenIntentSettings" -> {
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= 34) {
                                Intent(
                                    android.provider.Settings
                                        .ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    android.net.Uri.parse("package:$packageName")
                                )
                            } else {
                                Intent(
                                    android.provider.Settings
                                        .ACTION_APP_NOTIFICATION_SETTINGS
                                ).putExtra(
                                    android.provider.Settings.EXTRA_APP_PACKAGE,
                                    packageName
                                )
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
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
                        // Multi-responsável: lista de todos os responsáveis
                        // (pai e mãe) para o doc `locations` incluir o array
                        // `guardianIds` — usado pelo alerta de offline.
                        call.argument<List<String>>("guardianIds")?.let {
                            intent.putExtra("guardian_ids", it.toTypedArray())
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
        // Evita som duplo: o serviço de vigilância já está tocando.
        try {
            if (SosWatchService.isAlarming) return
        } catch (e: Exception) { }
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
            isAlarmPlaying = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Toca o som UMA vez (sem loop) para pré-visualização na tela de
     * configuração. Não mexe no volume do sistema.
     * Se [uri] for vazio, usa o alarme padrão do sistema.
     *
     * CORREÇÃO (bug "fica mudo ao escolher"): usa [stopLocalAlarm] e NÃO
     * [stopAlarm]. O [stopAlarm] envia o broadcast ACTION_CLOSE_EMERGENCY,
     * que a própria MainActivity recebe e trata chamando [stopLocalAlarm]
     * — como o broadcast é assíncrono, ele chegava DEPOIS do preview ter
     * começado e matava o MediaPlayer recém-criado (race condition).
     * Resultado: o usuário tocava para ouvir e não saía som nenhum.
     */
    private fun previewAlarm(uri: String?) {
        stopLocalAlarm()
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
     *
     * CORREÇÃO: a versão anterior podia retornar lista vazia (cursor nulo
     * em alguns aparelhos → NPE capturada → só o fallback), e o usuário
     * ficava sem opções para escolher. Agora:
     * - cursor com null-safety e fechamento automático (use)
     * - varre ALARM, NOTIFICATION e RINGTONE
     * - sempre inclui os padrões do sistema (sem duplicar URIs)
     */
    private fun getAlarmSounds(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val seen = mutableSetOf<String>()
        fun add(title: String, uri: String) {
            if (uri.isNotEmpty() && seen.add(uri)) {
                out.add(mapOf("title" to title, "uri" to uri))
            }
        }
        try {
            val rm = RingtoneManager(this)
            for (type in intArrayOf(
                RingtoneManager.TYPE_ALARM,
                RingtoneManager.TYPE_NOTIFICATION,
                RingtoneManager.TYPE_RINGTONE
            )) {
                try {
                    rm.setType(type)
                    rm.cursor?.use { cursor ->
                        while (cursor.moveToNext()) {
                            val title = cursor.getString(
                                RingtoneManager.TITLE_COLUMN_INDEX
                            ) ?: "Som"
                            val uri = rm.getRingtoneUri(cursor.position)
                                ?.toString() ?: ""
                            add(title, uri)
                        }
                    }
                } catch (e: Exception) {
                    // Tenta o próximo tipo.
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        // Sempre oferece os padrões do sistema.
        add(
            "Alarme padrão",
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?.toString() ?: ""
        )
        add(
            "Notificação padrão",
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?.toString() ?: ""
        )
        add(
            "Toque padrão",
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?.toString() ?: ""
        )
        return out
    }

    /** Para só o MediaPlayer local, sem rebroadcast (uso interno). */
    private fun stopLocalAlarm() {
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
        isAlarmPlaying = false
    }

    private fun stopAlarm() {
        stopLocalAlarm()
        // Também para o alarme do serviço de vigilância, se estiver tocando.
        try {
            val intent = Intent(this, SosWatchService::class.java)
                .setAction(SosWatchService.ACTION_STOP_ALARM)
            startService(intent)
        } catch (e: Exception) {
            // Serviço pode não existir ainda.
        }
        // Fecha a tela de emergência nativa onde quer que esteja
        // (aberta, em 2º plano ou na tela bloqueada): nada fica para trás.
        try {
            sendBroadcast(
                Intent(SosWatchService.ACTION_CLOSE_EMERGENCY)
                    .setPackage(packageName)
            )
        } catch (e: Exception) { }
    }

    override fun onDestroy() {
        try {
            closeReceiver?.let { unregisterReceiver(it) }
        } catch (e: Exception) { }
        closeReceiver = null
        stopAlarm()
        super.onDestroy()
    }
}
