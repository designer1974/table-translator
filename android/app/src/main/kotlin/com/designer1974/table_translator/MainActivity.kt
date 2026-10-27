package com.designer1974.table_translator

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Riconoscimento vocale veloce con il servizio di Google, scelto in modo
 * esplicito (su alcuni Huawei/Xiaomi il servizio predefinito non funziona).
 * Invia a Flutter: pronto, inizio voce, volume, testo parziale, testo finale, errori.
 */
class MainActivity : FlutterActivity() {
    private var recognizer: SpeechRecognizer? = null
    private var usedComponent: ComponentName? = null
    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private var permResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 77) {
            permResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "tt/stt/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink) { sink = events }
                override fun onCancel(args: Any?) { sink = null }
            }
        )
        MethodChannel(messenger, "tt/stt").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(info())
                "permission" -> {
                    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        permResult = result
                        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 77)
                    }
                }
                "start" -> {
                    try {
                        start(call.argument<String>("lang") ?: "it-IT", call.argument<String>("other"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("STT", e.message, null)
                    }
                }
                "stop" -> { recognizer?.stopListening(); result.success(null) }
                "cancel" -> { recognizer?.cancel(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        try { recognizer?.destroy() } catch (_: Exception) {}
        recognizer = null
        super.onDestroy()
    }

    private fun emit(type: String, extra: Map<String, Any?> = emptyMap()) {
        main.post { sink?.success(mapOf("type" to type) + extra) }
    }

    private fun services(): List<ComponentName> =
        packageManager.queryIntentServices(Intent(RecognitionService.SERVICE_INTERFACE), 0)
            .map { ComponentName(it.serviceInfo.packageName, it.serviceInfo.name) }

    /** Preferisce il servizio dell'app Google. */
    private fun bestComponent(): ComponentName? {
        val all = services()
        return all.firstOrNull { it.packageName == "com.google.android.googlequicksearchbox" }
            ?: all.firstOrNull { it.packageName == "com.google.android.tts" }
            ?: all.firstOrNull { it.packageName.startsWith("com.google") }
            ?: all.firstOrNull()
    }

    private fun info(): Map<String, Any?> = mapOf(
        "available" to SpeechRecognizer.isRecognitionAvailable(this),
        "services" to services().map { it.flattenToShortString() },
        "using" to bestComponent()?.flattenToShortString(),
    )

    private fun ensure(): SpeechRecognizer {
        recognizer?.let { return it }
        val comp = bestComponent()
        val r = if (comp != null) SpeechRecognizer.createSpeechRecognizer(this, comp)
        else SpeechRecognizer.createSpeechRecognizer(this)
        usedComponent = comp
        r.setRecognitionListener(listener)
        recognizer = r
        return r
    }

    private fun start(lang: String, other: String?) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang)
            putExtra("android.speech.extra.ONLY_RETURN_LANGUAGE_PREFERENCE", lang)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            // anche l'altra lingua: il servizio Google può riconoscerla da solo
            if (other != null) putExtra("android.speech.extra.EXTRA_ADDITIONAL_LANGUAGES", arrayOf(other))
            // Android 14+: riconosce da solo quale delle due lingue si parla
            val both = arrayListOf(lang).apply { if (other != null) add(other) }
            putExtra("android.speech.extra.ENABLE_LANGUAGE_DETECTION", true)
            putStringArrayListExtra("android.speech.extra.LANGUAGE_DETECTION_ALLOWED_LANGUAGES", both)
            putExtra("android.speech.extra.ENABLE_LANGUAGE_SWITCH", "balanced")
            putStringArrayListExtra("android.speech.extra.LANGUAGE_SWITCH_ALLOWED_LANGUAGES", both)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
        }
        val r = ensure()
        r.cancel()
        r.startListening(intent)
    }

    private fun firstText(b: Bundle?): String =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = emit("ready")
        override fun onBeginningOfSpeech() = emit("begin")
        override fun onRmsChanged(rmsdB: Float) = emit("rms", mapOf("value" to rmsdB.toDouble()))
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() = emit("end")
        override fun onError(error: Int) {
            // dopo alcuni errori il servizio va ricreato
            if (error == SpeechRecognizer.ERROR_CLIENT || error == 11 /* server disconnected */) {
                try { recognizer?.destroy() } catch (_: Exception) {}
                recognizer = null
            }
            emit("error", mapOf("code" to error))
        }
        override fun onResults(results: Bundle?) = emit("final", mapOf("text" to firstText(results)))
        override fun onPartialResults(partialResults: Bundle?) =
            emit("partial", mapOf("text" to firstText(partialResults)))
        override fun onEvent(eventType: Int, params: Bundle?) {}
        override fun onLanguageDetection(results: Bundle) {
            val tag = results.getString("detected_language") ?: return
            emit("lang", mapOf("tag" to tag))
        }
    }
}
