package com.rousoftware.codex_remote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.TimeUnit

class CodexForegroundService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val client by lazy {
        OkHttpClient.Builder()
            .pingInterval(20, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }

    private var socket: WebSocket? = null
    private var currentUrl: String? = null
    private var currentBearerToken: String? = null
    private var isSocketOpen: Boolean = false
    private var shouldReconnect: Boolean = false
    private var reconnectAttempt: Int = 0
    private val pendingMessages = ConcurrentLinkedQueue<String>()
    private val reconnectRunnable = Runnable {
        val url = currentUrl
        if (!shouldReconnect || url.isNullOrBlank()) {
            return@Runnable
        }
        connect(url, currentBearerToken)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification("Codex Remote", "Starting background connection"),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    0
                }
            )
        } catch (t: Throwable) {
            CodexServiceBridge.pushEvent(
                """{"method":"android/transportStatus","params":{"status":"error","message":${(t.message ?: "Failed to start foreground service").quoteJson()}}}"""
            )
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val url = intent.getStringExtra(EXTRA_URL)
                val bearerToken = intent.getStringExtra(EXTRA_BEARER_TOKEN)
                if (!url.isNullOrBlank()) {
                    shouldReconnect = true
                    connect(url, bearerToken)
                }
            }
            ACTION_SEND -> {
                val payload = intent.getStringExtra(EXTRA_PAYLOAD)
                if (!payload.isNullOrBlank()) {
                    sendOrQueue(payload)
                }
            }
            ACTION_SEND_FILE -> {
                val path = intent.getStringExtra(EXTRA_PAYLOAD_FILE)
                if (!path.isNullOrBlank()) {
                    sendPayloadFile(path)
                }
            }
            ACTION_DISCONNECT -> {
                disconnect(stopService = true)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        disconnect(stopService = false)
        super.onDestroy()
    }

    private fun connect(url: String, bearerToken: String?) {
        val normalizedToken = bearerToken?.trim()?.takeIf { it.isNotEmpty() }
        mainHandler.removeCallbacks(reconnectRunnable)
        if (currentUrl == url && currentBearerToken == normalizedToken && socket != null) {
            updateNotification(
                "Codex Remote",
                if (isSocketOpen) "Connected to $url" else "Connecting to $url"
            )
            return
        }

        val previousSocket = socket
        isSocketOpen = false
        currentUrl = url
        currentBearerToken = normalizedToken
        updateNotification("Codex Remote", "Connecting to $url")

        val requestBuilder = Request.Builder().url(url)
        if (normalizedToken != null) {
            requestBuilder.header("Authorization", "Bearer $normalizedToken")
        }

        val nextSocket = client.newWebSocket(
            requestBuilder.build(),
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (socket !== webSocket) {
                        return
                    }
                    isSocketOpen = true
                    reconnectAttempt = 0
                    flushPendingMessages(webSocket)
                    CodexServiceBridge.pushEvent(
                        """{"method":"android/transportStatus","params":{"status":"connected","url":${url.quoteJson()}}}"""
                    )
                    updateNotification("Codex Remote", "Connected to $url")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (socket !== webSocket) {
                        return
                    }
                    CodexServiceBridge.pushEvent(text)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (socket !== webSocket) {
                        return
                    }
                    isSocketOpen = false
                    socket = null
                    CodexServiceBridge.pushEvent(
                        """{"method":"android/transportStatus","params":{"status":"disconnected","code":$code,"reason":${reason.quoteJson()}}}"""
                    )
                    updateNotification("Codex Remote", "Disconnected")
                    scheduleReconnect("Socket closed")
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (socket !== webSocket) {
                        return
                    }
                    isSocketOpen = false
                    socket = null
                    val message = t.message ?: "Unknown websocket failure"
                    CodexServiceBridge.pushEvent(
                        """{"method":"android/transportStatus","params":{"status":"error","message":${message.quoteJson()}}}"""
                    )
                    updateNotification("Codex Remote", "Connection error")
                    scheduleReconnect(message)
                }
            }
        )
        socket = nextSocket
        previousSocket?.close(1000, "reconnect")
    }

    private fun disconnect(stopService: Boolean) {
        shouldReconnect = false
        mainHandler.removeCallbacks(reconnectRunnable)
        socket?.close(1000, "disconnect")
        socket = null
        isSocketOpen = false
        currentUrl = null
        currentBearerToken = null
        reconnectAttempt = 0
        pendingMessages.clear()
        updateNotification("Codex Remote", "Disconnected")
        if (stopService) {
            stopSelf()
        }
    }

    private fun sendOrQueue(payload: String) {
        val activeSocket = socket
        if (activeSocket == null || !isSocketOpen) {
            pendingMessages.add(payload)
            return
        }
        if (!activeSocket.send(payload)) {
            pendingMessages.add(payload)
        }
    }

    private fun sendPayloadFile(path: String) {
        val file = File(path)
        if (!file.exists()) {
            CodexServiceBridge.pushEvent(
                """{"method":"android/transportStatus","params":{"status":"error","message":"Payload file missing."}}"""
            )
            return
        }
        val payload = try {
            file.readText()
        } catch (t: Throwable) {
            CodexServiceBridge.pushEvent(
                """{"method":"android/transportStatus","params":{"status":"error","message":${(t.message ?: "Failed to read payload file").quoteJson()}}}"""
            )
            return
        } finally {
            file.delete()
        }
        if (payload.isNotBlank()) {
            sendOrQueue(payload)
        }
    }

    private fun flushPendingMessages(webSocket: WebSocket) {
        while (socket === webSocket && isSocketOpen) {
            val payload = pendingMessages.poll() ?: break
            if (!webSocket.send(payload)) {
                pendingMessages.add(payload)
                break
            }
        }
    }

    private fun scheduleReconnect(reason: String) {
        if (!shouldReconnect || currentUrl.isNullOrBlank()) {
            return
        }
        reconnectAttempt += 1
        val delayMs = when {
            reconnectAttempt <= 1 -> 1_000L
            reconnectAttempt == 2 -> 2_000L
            reconnectAttempt == 3 -> 5_000L
            else -> 10_000L
        }
        updateNotification("Codex Remote", "Reconnecting: $reason")
        mainHandler.removeCallbacks(reconnectRunnable)
        mainHandler.postDelayed(reconnectRunnable, delayMs)
    }

    private fun updateNotification(title: String, text: String) {
        runCatching {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(title, text))
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Codex Remote Background Connection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps the Codex app-server websocket running in the background."
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "codex_remote_connection"
        private const val NOTIFICATION_ID = 31041
        const val ACTION_CONNECT = "codex_remote.action.CONNECT"
        const val ACTION_SEND = "codex_remote.action.SEND"
        const val ACTION_SEND_FILE = "codex_remote.action.SEND_FILE"
        const val ACTION_DISCONNECT = "codex_remote.action.DISCONNECT"
        const val EXTRA_URL = "url"
        const val EXTRA_BEARER_TOKEN = "bearerToken"
        const val EXTRA_PAYLOAD = "payload"
        const val EXTRA_PAYLOAD_FILE = "payloadFile"

        fun startService(context: Context, intent: Intent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}

object CodexServiceBridge {
    @Volatile
    var sink: io.flutter.plugin.common.EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val backlog = ConcurrentLinkedQueue<String>()

    fun pushEvent(message: String) {
        val activeSink = sink
        if (activeSink != null) {
            mainHandler.post {
                sink?.success(message) ?: backlog.add(message)
            }
            return
        }
        backlog.add(message)
        while (backlog.size > 400) {
            backlog.poll()
        }
    }

    fun flushBacklog() {
        mainHandler.post {
            val activeSink = sink ?: return@post
            while (true) {
                val next = backlog.poll() ?: break
                activeSink.success(next)
            }
        }
    }
}

private fun String.quoteJson(): String {
    val escaped = this
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    return "\"$escaped\""
}
