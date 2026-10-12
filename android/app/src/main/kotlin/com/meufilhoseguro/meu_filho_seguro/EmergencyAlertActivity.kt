package com.meufilhoseguro.meu_filho_seguro

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.google.firebase.firestore.FirebaseFirestore

/**
 * Tela de emergência estilo Defesa Civil.
 *
 * Aparece em TELA CHEIA mesmo com o celular bloqueado quando o filho
 * aciona o SOS:
 * - Liga a tela e mostra por cima do bloqueio
 *   (setShowWhenLocked / setTurnScreenOn)
 * - Vibração forte em padrão de emergência
 * - O som do alarme continua tocando (via SosWatchService)
 * - NÃO pode ser dispensada pelo botão voltar: exige tocar em
 *   "MARCAR COMO VISTO", que registra o ack no Firestore, para o
 *   alarme e abre o app.
 */
class EmergencyAlertActivity : Activity() {

    companion object {
        const val EXTRA_ALERT_ID = "alert_id"
        const val EXTRA_CHILD_NAME = "child_name"

        /**
         * v15 — alerta de TESTE: quando true, a tela mostra o selo
         * "TESTE" para ninguém confundir com uma emergência real.
         * O "MARCAR COMO VISTO" funciona normalmente (faz o ack).
         */
        const val EXTRA_IS_TEST = "is_test"

        private const val ALERT_NOTIF_ID = 1003
    }

    private var vibrator: Vibrator? = null
    private var closeReceiver: android.content.BroadcastReceiver? = null

    /** Selo "TESTE" (visível só em alertas de teste). */
    private var testBadge: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Se o alerta for encerrado por outro caminho (ex.: "Marcar como
        // visto" no popup do app), esta tela fecha TOTALMENTE — não fica
        // em 2º plano nem volta ao desbloquear.
        closeReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(
                context: android.content.Context?,
                intent: android.content.Intent?
            ) {
                dismissCompletely()
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(
                    closeReceiver,
                    android.content.IntentFilter(
                        SosWatchService.ACTION_CLOSE_EMERGENCY
                    ),
                    android.content.Context.RECEIVER_NOT_EXPORTED
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

        // Defesa Civil: aparece por cima da tela bloqueada e liga a tela.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val childName =
            intent.getStringExtra(EXTRA_CHILD_NAME) ?: "Seu filho"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#B71C1C"))
            setPadding(64, 64, 64, 64)
        }

        val emoji = TextView(this).apply {
            text = "🆘"
            textSize = 72f
            gravity = Gravity.CENTER
        }
        val title = TextView(this).apply {
            text = "SOS ACIONADO!"
            setTextColor(Color.WHITE)
            textSize = 36f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
        }

        // v15 — selo "TESTE": aparece só quando o alerta é de teste
        // (EXTRA_IS_TEST). Evita que alguém confunda o teste com uma
        // emergência de verdade.
        val badge = TextView(this).apply {
            text = "TESTE"
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            setPadding(32, 12, 32, 12)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#7F0000"))
                setStroke(4, Color.WHITE)
                cornerRadius = 32f
            }
        }
        val badgeParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = 24 }
        testBadge = badge
        val subtitle = TextView(this).apply {
            text = "$childName precisa de ajuda AGORA!"
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 0)
        }
        val hint = TextView(this).apply {
            text = "Toque no botão abaixo para confirmar que viu o alerta e parar o alarme."
            setTextColor(Color.parseColor("#FFCDD2"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 0)
        }
        val button = Button(this).apply {
            text = "MARCAR COMO VISTO"
            textSize = 20f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#B71C1C"))
            setBackgroundColor(Color.WHITE)
            setPadding(32, 32, 32, 32)
            setOnClickListener { onAcknowledge() }
        }
        val btnParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = 64
        }

        root.addView(emoji)
        root.addView(title)
        // Selo de teste: visível só em alertas de teste.
        root.addView(badge, badgeParams)
        badge.visibility =
            if (intent.getBooleanExtra(EXTRA_IS_TEST, false))
                android.view.View.VISIBLE
            else
                android.view.View.GONE
        root.addView(subtitle)
        root.addView(hint)
        root.addView(button, btnParams)
        setContentView(root)

        startVibration()
    }

    /**
     * Vibração forte em padrão de emergência (repete até dispensar).
     */
    private fun startVibration() {
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                    as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            // Padrão Defesa Civil: 1s vibrando, 0.5s pausa, em loop.
            val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(
                    VibrationEffect.createWaveform(pattern, 0)
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopVibration() {
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
        }
        vibrator = null
    }

    /**
     * "Marcar como visto": registra o ack no Firestore (o app para de
     * alarmar), para o som e a vibração, remove a notificação e abre o app.
     */
    private fun onAcknowledge() {
        val alertId = intent.getStringExtra(EXTRA_ALERT_ID) ?: ""

        // 1. Ack no Firestore: o monitor do Flutter vê e para o alarme.
        if (alertId.isNotEmpty()) {
            try {
                FirebaseFirestore.getInstance()
                    .collection("sos_alerts")
                    .document(alertId)
                    .update("ack", true)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. Para o som do alarme no serviço de vigilância.
        try {
            val stopIntent = Intent(this, SosWatchService::class.java)
                .setAction(SosWatchService.ACTION_STOP_ALARM)
            startService(stopIntent)
        } catch (e: Exception) {
        }

        // 3. Para a vibração e remove a notificação de emergência.
        stopVibration()
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager).cancel(ALERT_NOTIF_ID)
        } catch (e: Exception) {
        }

        // 4. Fecha esta tela COMPLETAMENTE (some dos recentes e não
        // volta ao desbloquear) e abre o app.
        try {
            sendBroadcast(
                Intent(SosWatchService.ACTION_CLOSE_EMERGENCY)
                    .setPackage(packageName)
            )
        } catch (e: Exception) { }
        val openApp = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(openApp)
        dismissCompletely()
    }

    /**
     * Fecha a tela de emergência de verdade: para a vibração, remove
     * das tarefas recentes e destrói a activity. Sem isso, a "imagem"
     * do alerta ficava em 2º plano mesmo após atendida.
     */
    private fun dismissCompletely() {
        stopVibration()
        try {
            closeReceiver?.let { unregisterReceiver(it) }
        } catch (e: Exception) { }
        closeReceiver = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                finishAndRemoveTask()
            } else {
                @Suppress("DEPRECATION")
                finish()
            }
        } catch (e: Exception) {
            try { finish() } catch (_: Exception) { }
        }
    }

    /**
     * O botão voltar NÃO dispensa o alerta: é preciso tocar em
     * "MARCAR COMO VISTO" (estilo Defesa Civil).
     */
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        // Ignorado de propósito.
    }

    /**
     * Se um NOVO alerta chegar com esta tela já aberta (launchMode
     * singleTop + fallback de abertura direta), troca o intent para o
     * mais recente — o "MARCAR COMO VISTO" referencia o alerta certo.
     *
     * v15 — atualiza também o selo "TESTE" conforme o novo intent.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        testBadge?.visibility =
            if (intent.getBooleanExtra(EXTRA_IS_TEST, false))
                android.view.View.VISIBLE
            else
                android.view.View.GONE
    }

    override fun onDestroy() {
        try {
            closeReceiver?.let { unregisterReceiver(it) }
        } catch (e: Exception) { }
        closeReceiver = null
        stopVibration()
        super.onDestroy()
    }
}
