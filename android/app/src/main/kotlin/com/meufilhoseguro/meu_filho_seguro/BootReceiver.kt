package com.meufilhoseguro.meu_filho_seguro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Reinicia os serviços de segurança após o celular ligar.
 *
 * - No celular do filho: retoma o compartilhamento de localização se ele
 *   estava ativo antes de desligar (config salva em "mfs_sharing").
 * - No celular do responsável: retoma a vigilância de SOS se estava ativa
 *   (config salva em "mfs_sos_watch").
 *
 * Limitação honesta: com o celular desligado não há rastreamento
 * (sem GPS, sem internet). O que este receiver garante é que o
 * rastreamento volte SOZINHO assim que o aparelho ligar, sem depender
 * de alguém abrir o app.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        // 1) Compartilhamento do filho (estava ativo?).
        val sharingPrefs =
            context.getSharedPreferences("mfs_sharing", Context.MODE_PRIVATE)
        if (!sharingPrefs.getString("child_id", null).isNullOrEmpty()) {
            val service = Intent(context, LocationSharingService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(service)
                } else {
                    context.startService(service)
                }
            } catch (e: Exception) {
                // Ignora: o START_STICKY tenta recuperar depois.
            }
        }

        // 2) Vigilância SOS do responsável (estava ativa?).
        val watchPrefs =
            context.getSharedPreferences("mfs_sos_watch", Context.MODE_PRIVATE)
        if (!watchPrefs.getString("guardian_id", null).isNullOrEmpty()) {
            val watch = Intent(context, SosWatchService::class.java)
                .setAction(SosWatchService.ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(watch)
                } else {
                    context.startService(watch)
                }
            } catch (e: Exception) {
                // Ignora.
            }
        }
    }
}
