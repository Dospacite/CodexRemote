package com.rousoftware.codex_remote

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "codex_remote/android_transport"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val url = call.argument<String>("url")
                    val bearerToken = call.argument<String>("bearerToken")
                    if (url.isNullOrBlank()) {
                        result.error("invalid_args", "Missing websocket URL", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, CodexForegroundService::class.java).apply {
                        action = CodexForegroundService.ACTION_CONNECT
                        putExtra(CodexForegroundService.EXTRA_URL, url)
                        putExtra(CodexForegroundService.EXTRA_BEARER_TOKEN, bearerToken)
                    }
                    CodexForegroundService.startService(this, intent)
                    result.success(null)
                }

                "send" -> {
                    val payload = call.argument<String>("payload")
                    if (payload.isNullOrBlank()) {
                        result.error("invalid_args", "Missing payload", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, CodexForegroundService::class.java).apply {
                        action = CodexForegroundService.ACTION_SEND
                        putExtra(CodexForegroundService.EXTRA_PAYLOAD, payload)
                    }
                    CodexForegroundService.startService(this, intent)
                    result.success(null)
                }

                "sendFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "Missing payload file path", null)
                        return@setMethodCallHandler
                    }
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("invalid_args", "Payload file does not exist", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, CodexForegroundService::class.java).apply {
                        action = CodexForegroundService.ACTION_SEND_FILE
                        putExtra(CodexForegroundService.EXTRA_PAYLOAD_FILE, path)
                    }
                    CodexForegroundService.startService(this, intent)
                    result.success(null)
                }

                "disconnect" -> {
                    val intent = Intent(this, CodexForegroundService::class.java).apply {
                        action = CodexForegroundService.ACTION_DISCONNECT
                    }
                    CodexForegroundService.startService(this, intent)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "codex_remote/android_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                CodexServiceBridge.sink = events
                CodexServiceBridge.flushBacklog()
            }

            override fun onCancel(arguments: Any?) {
                CodexServiceBridge.sink = null
            }
        })
    }
}
