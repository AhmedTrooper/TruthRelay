package io.truthrelay.mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.net.ConnectivityManager
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * MainActivity hosts the MethodChannel that bridges Flutter to the OS-level
 * hotspot + TCP transport the mobile mesh uses when the relay server is
 * unreachable.
 *
 * Methods exposed on "truthrelay.local_hotspot":
 *   - isHotspotSupported()              -> Boolean
 *   - startHost(int port)               -> {ssid, passphrase, port, gateway_ip}
 *   - stopHost()                        -> null
 *   - joinHotspot({ssid, passphrase, port, gateway_ip}) -> {fd:int, peer_addr}
 *   - leaveHotspot()                    -> null
 *
 * Channels:
 *   - "truthrelay.local_hotspot.events" -> stream of hotspot state changes
 *   - "truthrelay.local_hotspot.bytes"  -> per-connection byte stream
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "TruthRelayHotspot"
        private const val METHOD_CHANNEL = "truthrelay.local_hotspot"
        private const val EVENT_CHANNEL = "truthrelay.local_hotspot.events"
        private const val BYTES_CHANNEL = "truthrelay.local_hotspot.bytes"

        // Best-effort gateway candidate IP. The local hotspot gateway is
        // almost always 192.168.43.1 on Android; some vendors use .1 .2
        // or .49. We try a small list on the joiner side.
        private val GATEWAY_CANDIDATES = listOf(
            "192.168.43.1",
            "192.168.49.1",
            "192.168.42.1",
            "192.168.44.1",
            "192.168.45.1",
            "192.168.46.1",
        )
    }

    private var serverSocket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventsSink: EventChannel.EventSink? = null
    // Map of connectionId -> bytes sink. Connection id = peer label.
    private val bytesSinks = mutableMapOf<String, EventChannel.EventSink>()
    // Map of connectionId -> Socket. Lets Dart -> Java sendBytes() find the
    // right socket.
    private val socketsById = mutableMapOf<String, Socket>()
    // Map of connectionId -> DataOutputStream for outbound writes.
    private val outsById = mutableMapOf<String, DataOutputStream>()

    private val tcpListeners = mutableListOf<Thread>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isHotspotSupported" -> result.success(Build.VERSION.SDK_INT >= 26)
                        "startHost" -> {
                            val port = call.argument<Int>("port") ?: 8765
                            startHotspotAndListen(port, result)
                        }
                        "stopHost" -> { stopHotspot(result) }
                        "joinHotspot" -> {
                            val ssid = call.argument<String>("ssid") ?: ""
                            val passphrase = call.argument<String>("passphrase") ?: ""
                            val port = call.argument<Int>("port") ?: 8765
                            joinHotspot(ssid, passphrase, port, result)
                        }
                        "leaveHotspot" -> { leaveHotspot(result) }
                        "sendBytes" -> {
                            val connId = call.argument<String>("connection_id") ?: ""
                            val bytes = call.argument<ByteArray>("bytes")
                            sendBytes(connId, bytes, result)
                        }
                        "closeConnection" -> {
                            val connId = call.argument<String>("connection_id") ?: ""
                            closeConnection(connId, result)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "method ${call.method} failed", t)
                    result.error("HOTSPOT_ERR", t.message, null)
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    eventsSink = sink
                }
                override fun onCancel(args: Any?) {
                    eventsSink = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BYTES_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    val connId = (args as? Map<*, *>)?.get("connection_id") as? String
                    if (connId != null) {
                        bytesSinks[connId] = sink
                    }
                }
                override fun onCancel(args: Any?) {
                    val connId = (args as? Map<*, *>)?.get("connection_id") as? String
                    if (connId != null) bytesSinks.remove(connId)
                }
            })

        // Receiver that listens for SSID changes. After startHotspot() the
        // system updates the connected SSID; we re-emit credentials when
        // that happens.
        val filter = IntentFilter()
        filter.addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        registerReceiver(scanReceiver, filter)
    }

    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            // no-op; we only need this to keep the receiver alive in case
            // future firmware hooks need it.
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(scanReceiver) } catch (_: Throwable) {}
        try { serverSocket?.close() } catch (_: Throwable) {}
        super.onDestroy()
    }

    // ---------------- Host side ----------------

    private fun startHotspotAndListen(port: Int, result: MethodChannel.Result) {
        stopServerSocket()
        val ssid = "TR-${randomFour()}"
        val pass = randomPassphrase()

        // Open the TCP listener IMMEDIATELY — independent of the hotspot
        // state. The TCP socket is the one the joiner dials; the OS routes
        // hotspot traffic to 0.0.0.0:port even when no soft-AP is up.
        val server = try {
            ServerSocket(port, 8, InetAddress.getByName("0.0.0.0"))
        } catch (t: Throwable) {
            result.error("BIND_FAIL", "Could not bind 0.0.0.0:$port: ${t.message}", null)
            return
        }
        serverSocket = server
        emit(mapOf("type" to "host_listening", "port" to port, "ssid" to ssid))
        Log.i(TAG, "TCP listener bound on 0.0.0.0:$port")

        // Spawn the accept loop FIRST so a joiner can connect before the
        // hotspot config is finalised.
        val acceptThread = Thread {
            var counter = 0
            try {
                while (!server.isClosed) {
                    val client = server.accept()
                    counter += 1
                    val connId = "host_peer_$counter"
                    val peerAddr = client.remoteSocketAddress.toString()
                    Log.i(TAG, "Accepted peer $connId from $peerAddr")
                    emit(mapOf(
                        "type" to "host_peer_connected",
                        "connection_id" to connId,
                        "peer_addr" to peerAddr,
                    ))
                    pump(client, connId)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "accept loop exited: ${t.message}")
                emit(mapOf("type" to "host_listening_stopped"))
            }
        }
        acceptThread.isDaemon = true
        acceptThread.start()
        tcpListeners.add(acceptThread)

        // Best-effort: also turn on the system's local-only hotspot so the
        // joiner phone sees an AP and can join. We do NOT use addNetwork
        // (that's for joining saved networks) and we do NOT touch the
        // current Wi-Fi connection (that would drop the user from the
        // laptop relay Wi-Fi mid-startHost).
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                startLocalOnlyHotspot { ssid, pass ->
                    if (ssid != null) {
                        Log.i(TAG, "Local-only hotspot active: $ssid")
                        emit(mapOf(
                            "type" to "host_hotspot_active",
                            "ssid" to ssid,
                            "passphrase" to pass,
                        ))
                    } else {
                        Log.w(TAG, "Local-only hotspot returned null")
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Could not start local-only hotspot: ${t.message}")
            }
        }

        val gateway = guessOwnGateway() ?: "192.168.43.1"
        result.success(mapOf(
            "ssid" to ssid,
            "passphrase" to pass,
            "port" to port,
            "gateway_ip" to gateway,
            "issued_at" to System.currentTimeMillis().toString(),
            "band" to 0,
        ))
    }

    /**
     * Start the OS-level local-only hotspot. We use reflection so the
     * code compiles regardless of compileSdk (the API 30
     * `LocalOnlyHotspotRequest` + 3-arg overload aren't visible at
     * compileSdk <= 29, but the runtime path is fine on any device).
     */
    private var hotspotReservation: Any? = null

    private fun startLocalOnlyHotspot(onReady: (String?, String?) -> Unit) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        try {
            // API 30+: startLocalOnlyHotspot(LocalOnlyHotspotRequest, Executor, Consumer)
            val requestClass = Class.forName("android.net.wifi.WifiManager\$LocalOnlyHotspotRequest")
            val requestBuilder = requestClass.getMethod("Builder").invoke(null)
            val request = requestBuilder.javaClass.getMethod("build").invoke(requestBuilder)
            val executor = ExecutorImpl()
            val consumerClass = Class.forName("android.net.wifi.WifiManager\$LocalOnlyHotspotReservation")
            val consumer = java.util.function.Consumer<Any> { res ->
                try {
                    hotspotReservation = res
                    val ssid = readSsidFromReservation(res)
                    val pass = readPassphraseFromReservation(res)
                    Log.i(TAG, "Local-only hotspot up: $ssid")
                    mainHandler.post { onReady(ssid, pass) }
                } catch (t: Throwable) {
                    Log.w(TAG, "reservation consumer threw: ${t.message}")
                    mainHandler.post { onReady(null, null) }
                }
            }
            val method = wifi.javaClass.getMethod(
                "startLocalOnlyHotspot",
                requestClass,
                java.util.concurrent.Executor::class.java,
                Class.forName("java.util.function.Consumer"),
            )
            method.invoke(wifi, request, executor, consumer)
        } catch (t: Throwable) {
            // Fall through to API 26-29 signature.
            try {
                startLocalOnlyHotspotApi26Legacy(wifi, onReady)
            } catch (t2: Throwable) {
                Log.w(TAG, "Could not start local-only hotspot (any API): ${t2.message}")
                mainHandler.post { onReady(null, null) }
            }
        }
    }

    private fun startLocalOnlyHotspotApi26Legacy(
        wifi: WifiManager,
        onReady: (String?, String?) -> Unit,
    ) {
        // Build a LocalOnlyHotspotCallback dynamically. We extend the class
        // via reflection so it works even when compileSdk doesn't include
        // the symbol. We override onStarted(WifiConfiguration) (the API 26
        // signature) by dynamic-dispatching on whatever the parent declares.
        val cbClass = Class.forName("android.net.wifi.WifiManager\$LocalOnlyHotspotCallback")
        val cb = java.lang.reflect.Proxy.newProxyInstance(
            cbClass.classLoader,
            arrayOf(cbClass),
            java.lang.reflect.InvocationHandler { _, method, args ->
                when (method.name) {
                    "onStarted" -> {
                        // args[0] can be either WifiConfiguration (API < 30)
                        // or LocalOnlyHotspotReservation (API >= 30). Try
                        // both extractors.
                        val arg = args?.firstOrNull()
                        val ssid = readSsidFromReservation(arg) ?: arg?.let { readSsidFromConfig(it) }
                        val pass = readPassphraseFromReservation(arg) ?: arg?.let { readPassphraseFromConfig(it) }
                        Log.i(TAG, "Local-only hotspot up (legacy): $ssid")
                        hotspotReservation = null
                        mainHandler.post { onReady(ssid, pass) }
                        null
                    }
                    "onFailed" -> {
                        val reason = (args?.firstOrNull() as? Number)?.toInt() ?: -1
                        Log.w(TAG, "local-only hotspot onFailed reason=$reason")
                        mainHandler.post { onReady(null, null) }
                        null
                    }
                    "onStopped" -> {
                        Log.w(TAG, "local-only hotspot onStopped")
                        null
                    }
                    else -> null
                }
            }
        )
        wifi.javaClass.getMethod("startLocalOnlyHotspot", cbClass, android.os.Handler::class.java)
            .invoke(wifi, cb, mainHandler)
    }

    private fun readSsidFromReservation(reservation: Any?): String? {
        if (reservation == null) return null
        return try {
            val softApConfig = reservation.javaClass.getMethod("getSoftApConfiguration").invoke(reservation)
            softApConfig?.javaClass?.getMethod("getSsid")?.invoke(softApConfig) as? String
        } catch (_: Throwable) {
            null
        }
    }

    private fun readPassphraseFromReservation(reservation: Any?): String? {
        if (reservation == null) return null
        return try {
            val softApConfig = reservation.javaClass.getMethod("getSoftApConfiguration").invoke(reservation)
            softApConfig?.javaClass?.getMethod("getPassphrase")?.invoke(softApConfig) as? String
        } catch (_: Throwable) {
            null
        }
    }

    private fun readSsidFromConfig(cfg: Any?): String? {
        if (cfg == null) return null
        return try {
            val raw = cfg.javaClass.getMethod("getSSid").invoke(cfg) as? String ?: return null
            raw.trim('"')
        } catch (_: Throwable) {
            null
        }
    }

    private fun readPassphraseFromConfig(cfg: Any?): String? {
        if (cfg == null) return null
        return try {
            val raw = cfg.javaClass.getMethod("getPreSharedKey").invoke(cfg) as? String ?: return null
            raw.trim('"')
        } catch (_: Throwable) {
            null
        }
    }

    private class ExecutorImpl : java.util.concurrent.Executor {
        override fun execute(command: Runnable) {
            command.run()
        }
    }

    private fun stopHotspot(result: MethodChannel.Result) {
        stopServerSocket()
        // Release any active LocalOnlyHotspotReservation reflectively.
        // On 26-29 the system manages teardown via the SoftAp state
        // machine so we don't need to do anything.
        try {
            val r = hotspotReservation
            if (r != null) {
                val m = r.javaClass.getMethod("close")
                m.invoke(r)
            }
        } catch (_: Throwable) {}
        hotspotReservation = null
        result.success(null)
    }

    private fun stopServerSocket() {
        try { serverSocket?.close() } catch (_: Throwable) {}
        serverSocket = null
    }

    // ---------------- Joiner side ----------------

    private fun joinHotspot(ssid: String, passphrase: String, port: Int, result: MethodChannel.Result) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        if (Build.VERSION.SDK_INT >= 29) {
            joinHotspotUsingSpecifier(ssid, passphrase, port, result)
            return
        }

        // API 26-28 fallback: old WifiConfiguration path.
        val cfg = WifiConfiguration().apply {
            this.SSID = "\"" + ssid + "\""
            this.preSharedKey = "\"" + passphrase + "\""
            @Suppress("DEPRECATION")
            allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA2_PSK)
        }
        @Suppress("DEPRECATION")
        val netId = wifi.addNetwork(cfg)

        executor.submit {
            var lastError: Throwable? = null
            for (gw in GATEWAY_CANDIDATES) {
                try {
                    val sock = Socket()
                    sock.connect(java.net.InetSocketAddress(gw, port), 5000)
                    @Suppress("DEPRECATION")
                    wifi.disconnect()
                    wifi.enableNetwork(netId, true)
                    wifi.reconnect()
                    val connId = "joiner_${System.currentTimeMillis()}"
                    val peerAddr = sock.remoteSocketAddress.toString()
                    mainHandler.post {
                        emit(mapOf(
                            "type" to "joiner_connected",
                            "connection_id" to connId,
                            "peer_addr" to peerAddr,
                        ))
                        result.success(mapOf(
                            "connection_id" to connId,
                            "peer_addr" to peerAddr,
                        ))
                    }
                    pump(sock, connId)
                    return@submit
                } catch (t: Throwable) {
                    lastError = t
                    continue
                }
            }
            mainHandler.post {
                result.error(
                    "JOIN_FAILED",
                    "Could not connect to any gateway candidate: ${lastError?.message}",
                    null,
                )
            }
        }
    }

    private fun joinHotspotUsingSpecifier(
        ssid: String, passphrase: String, port: Int, result: MethodChannel.Result,
    ) {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(passphrase)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .setNetworkSpecifier(specifier)
            .build()
        cm.requestNetwork(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) {
                executor.submit {
                    var lastError: Throwable? = null
                    val cap = cm.getNetworkCapabilities(network)
                    // Once we're on the hotspot, the OS gives us the
                    // gateway IP. Use the network's socket factory so
                    // we route through the new network rather than the
                    // current default.
                    val proxySockFactory = network.socketFactory
                    val proxyAddr = InetAddress.getByName("192.168.43.1")
                    for (gw in listOf("192.168.43.1", "192.168.49.1", proxyAddr.hostAddress ?: "192.168.43.1")) {
                        try {
                            val sock = proxySockFactory.createSocket(gw, port)
                            val connId = "joiner_${System.currentTimeMillis()}"
                            val peerAddr = sock.remoteSocketAddress.toString()
                            mainHandler.post {
                                emit(mapOf(
                                    "type" to "joiner_connected",
                                    "connection_id" to connId,
                                    "peer_addr" to peerAddr,
                                ))
                                result.success(mapOf(
                                    "connection_id" to connId,
                                    "peer_addr" to peerAddr,
                                ))
                            }
                            pump(sock, connId)
                            return@submit
                        } catch (t: Throwable) {
                            lastError = t
                            continue
                        }
                    }
                    mainHandler.post {
                        result.error(
                            "JOIN_FAILED",
                            "Connected to '$ssid' but could not open TCP: ${lastError?.message}",
                            null,
                        )
                    }
                }
            }
            override fun onUnavailable() {
                mainHandler.post {
                    result.error("JOIN_FAILED", "Network unavailable for SSID '$ssid'", null)
                }
            }
        })
    }

    private fun leaveHotspot(result: MethodChannel.Result) {
        // Best-effort. We can't undo the joiner's WifiConfiguration from
        // a single shared ID; the user is expected to tap "Stop" or close
        // the app, at which point Android reverts to the previous network.
        result.success(null)
    }

    private fun sendBytes(connectionId: String, bytes: ByteArray?, result: MethodChannel.Result) {
        if (connectionId.isEmpty() || bytes == null) {
            result.error("ARGS", "Missing connection_id or bytes", null)
            return
        }
        executor.submit {
            try {
                val out = outsById[connectionId]
                if (out == null) {
                    mainHandler.post { result.error("NO_SOCKET", "No socket for $connectionId", null) }
                    return@submit
                }
                out.write(bytes)
                out.flush()
                mainHandler.post { result.success(null) }
            } catch (t: Throwable) {
                Log.w(TAG, "sendBytes $connectionId failed: ${t.message}")
                mainHandler.post { result.error("WRITE_ERR", t.message, null) }
            }
        }
    }

    private fun closeConnection(connectionId: String, result: MethodChannel.Result) {
        try {
            socketsById.remove(connectionId)?.close()
            outsById.remove(connectionId)?.close()
        } catch (_: Throwable) {}
        result.success(null)
    }

    // ---------------- Byte pump ----------------

    /** Pump bytes from a Socket into the EventChannel for the Dart side. */
    private fun pump(socket: Socket, connId: String) {
        socketsById[connId] = socket
        outsById[connId] = DataOutputStream(socket.getOutputStream())
        executor.submit {
            try {
                val input = DataInputStream(socket.getInputStream())
                val buffer = ByteArray(4096)
                while (!socket.isClosed) {
                    val n = input.read(buffer)
                    if (n <= 0) break
                    val payload = buffer.copyOf(n)
                    mainHandler.post {
                        bytesSinks[connId]?.success(payload)
                        if (bytesSinks[connId] == null) {
                            try { socket.close() } catch (_: Throwable) {}
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "pump for $connId ended: ${t.message}")
            } finally {
                try { socket.close() } catch (_: Throwable) {}
                socketsById.remove(connId)
                outsById.remove(connId)
                mainHandler.post {
                    emit(mapOf("type" to "peer_disconnected", "connection_id" to connId))
                }
            }
        }
    }

    // ---------------- EventChannel helpers ----------------

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventsSink?.success(payload)
        }
    }

    // ---------------- String utilities ----------------

    private fun randomFour(): String {
        val pool = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return (1..4).map { pool.random() }.joinToString("")
    }

    private fun randomPassphrase(): String {
        val pool = "abcdefghjkmnpqrstuvwxyz23456789"
        return (1..8).map { pool.random() }.joinToString("")
    }

    private fun guessOwnGateway(): String? {
        try {
            val interfaces = java.net.NetworkInterface.getNetworkInterfaces()?.toList() ?: return null
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback || iface.isPointToPoint) continue
                val addrs = iface.inetAddresses?.toList() ?: continue
                for (addr in addrs) {
                    val s = addr.hostAddress ?: continue
                    if (s.startsWith("192.168.43.") || s.startsWith("192.168.49.")) {
                        return s
                    }
                }
            }
        } catch (_: Throwable) {}
        return null
    }
}
