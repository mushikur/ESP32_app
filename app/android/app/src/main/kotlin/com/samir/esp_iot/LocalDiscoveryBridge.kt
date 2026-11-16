package com.samir.esp_iot

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLException

internal class LocalDiscoveryBridge(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val discoveryThread = HandlerThread("esp-iot-discovery").apply { start() }
    private val handler = Handler(discoveryThread.looper)
    private val workers = ThreadPoolExecutor(4, 4, 10, TimeUnit.SECONDS, ArrayBlockingQueue(8))
        .apply { allowCoreThreadTimeOut(true) }
    private val closers = ThreadPoolExecutor(1, 2, 10, TimeUnit.SECONDS, ArrayBlockingQueue(8))
        .apply { allowCoreThreadTimeOut(true) }
    private val pending = mutableMapOf<Int, Operation>()

    init {
        channel.setMethodCallHandler { call, result -> handler.post { onCall(call, result) } }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "wifi" -> {
                    val wifi = currentWifi()
                    result.success(wifi.toMap(connectivity.activeNetwork == wifi.network))
                }
                "cancel" -> {
                    call.argument<Int>("operation")?.let { id ->
                        pending[id]?.let { finish(id, it, failure = LanFailure("cancelled")) }
                    }
                    result.success(null)
                }
                "mdns", "udp", "probe" -> start(call, result)
                else -> result.notImplemented()
            }
        } catch (error: LanFailure) {
            result.error(error.code, null, null)
        } catch (_: SecurityException) {
            result.error("permission", null, null)
        } catch (_: Exception) {
            result.error("invalidResponse", null, null)
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val scope = currentWifi()
        if (call.argument<Number>("networkId")?.toLong() != scope.network.networkHandle ||
            call.argument<String>("address") != scope.address.hostAddress ||
            call.argument<Int>("prefix") != scope.prefix
        ) throw LanFailure("networkChanged")
        val id = call.argument<Int>("operation") ?: throw LanFailure("invalid")
        if (id in pending || pending.size >= 8) throw LanFailure("busy")
        val operation = Operation(result)
        pending[id] = operation
        try {
            when (call.method) {
                "mdns" -> MdnsSearch(scope, id, operation).start()
                "udp" -> {
                    val nonce = call.argument<String>("nonce")
                    if (nonce == null || !HEX_ID.matches(nonce)) throw LanFailure("invalid")
                    runWorker(id, operation, 3800) { udp(scope, nonce, operation) }
                }
                "probe" -> {
                    val host = call.argument<String>("host")?.let(::parseIpv4)
                    val port = call.argument<Int>("port")
                    if (host == null || !scope.allows(host) || port == null || port !in 1..65535) {
                        throw LanFailure("outsideWifi")
                    }
                    val quick = call.argument<Boolean>("quick") == true
                    val root = call.argument<Boolean>("root") == true
                    runWorker(id, operation, if (quick) 1450 else 3200) {
                        probeHttps(scope, host, port, root, quick, operation)
                    }
                }
            }
        } catch (error: Exception) {
            finish(id, operation, failure = failureFor(error))
        }
    }

    private fun runWorker(id: Int, operation: Operation, timeout: Long, action: () -> Any) {
        operation.deadline = Runnable { finish(id, operation, failure = LanFailure("timeout")) }
            .also { handler.postDelayed(it, timeout) }
        operation.future = workers.submit {
            try {
                val value = action()
                handler.post { finish(id, operation, value) }
            } catch (error: Exception) {
                handler.post { finish(id, operation, failure = failureFor(error)) }
            }
        }
    }

    private fun finish(id: Int, operation: Operation, value: Any? = null, failure: LanFailure? = null) {
        if (pending[id] !== operation) return
        pending.remove(id)
        operation.deadline?.let(handler::removeCallbacks)
        operation.cleanup?.invoke()
        if (failure != null) {
            operation.cancelled.set(true)
            operation.future?.cancel(true)
            operation.udpSocket.getAndSet(null)?.close()
            operation.httpConnection.getAndSet(null)?.let { connection ->
                runCatching { closers.execute { runCatching { connection.disconnect() } } }
            }
            operation.result.error(failure.code, null, null)
        } else {
            operation.result.success(value)
        }
    }

    fun cancelAll() {
        handler.post(::cancelPending)
    }

    private fun cancelPending() {
        pending.toMap().forEach { (id, operation) ->
            finish(id, operation, failure = LanFailure("cancelled"))
        }
        workers.purge()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        handler.post {
            cancelPending()
            workers.shutdownNow()
            closers.shutdown()
            discoveryThread.quitSafely()
        }
    }

    private fun currentWifi(): WifiLink {
        val active = connectivity.activeNetwork
        if (active != null && connectivity.getNetworkCapabilities(active)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        ) throw LanFailure("vpn")
        fun isWifi(network: Network): Boolean = connectivity.getNetworkCapabilities(network)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true

        @Suppress("DEPRECATION")
        val network = if (active != null && isWifi(active)) active
        else connectivity.allNetworks.filter(::isWifi).singleOrNull() ?: throw LanFailure("noWifi")
        return connectivity.getLinkProperties(network)?.linkAddresses.orEmpty().firstNotNullOfOrNull {
            val address = it.address as? Inet4Address ?: return@firstNotNullOfOrNull null
            WifiLink(network, address, it.prefixLength).takeIf { link -> link.isPrivateSubnet() }
        } ?: throw LanFailure("noPrivateIpv4")
    }

    private fun assertCurrent(scope: WifiLink) {
        val current = try { currentWifi() } catch (error: LanFailure) {
            if (error.code == "permission") throw error
            throw LanFailure("networkChanged")
        }
        if (current != scope) throw LanFailure("networkChanged")
    }

    private fun udp(scope: WifiLink, nonce: String, operation: Operation): List<Map<String, Any>> {
        assertCurrent(scope)
        val socket = DatagramSocket(null)
        operation.udpSocket.set(socket)
        try {
            if (operation.cancelled.get()) throw LanFailure("cancelled")
            scope.network.bindSocket(socket)
            socket.bind(InetSocketAddress(scope.address, 0))
            socket.broadcast = true
            val query = """{"protocol":"esp-iot","version":1,"kind":"discover","nonce":"$nonce"}"""
                .toByteArray(Charsets.UTF_8)
            socket.send(DatagramPacket(query, query.size, scope.broadcast(), UDP_PORT))
            val end = SystemClock.elapsedRealtime() + 2900
            val offers = mutableListOf<Map<String, Any>>()
            val buffer = ByteArray(513)
            val packet = DatagramPacket(buffer, buffer.size)
            while (offers.size < 24 && !operation.cancelled.get()) {
                val remaining = end - SystemClock.elapsedRealtime()
                if (remaining <= 0) break
                socket.soTimeout = remaining.toInt()
                packet.length = buffer.size
                try { socket.receive(packet) } catch (_: SocketTimeoutException) { break }
                val sender = packet.address as? Inet4Address ?: continue
                if (packet.length !in 1..512 || !scope.allows(sender)) continue
                offers.add(mapOf(
                    "host" to sender.hostAddress!!,
                    "payload" to packet.data.copyOfRange(packet.offset, packet.offset + packet.length),
                ))
            }
            assertCurrent(scope)
            return offers
        } finally {
            operation.udpSocket.getAndSet(null)?.close()
            socket.close()
        }
    }

    private fun probeHttps(
        scope: WifiLink,
        host: Inet4Address,
        port: Int,
        root: Boolean,
        quick: Boolean,
        operation: Operation,
    ): Map<String, Any> {
        assertCurrent(scope)
        val path = if (root) "/" else "/.well-known/esp-iot"
        val url = URL("https", host.hostAddress!!, port, path)
        val connection = scope.network.openConnection(url, Proxy.NO_PROXY) as HttpURLConnection
        operation.httpConnection.set(connection)
        val deadline = SystemClock.elapsedRealtime() + if (quick) 1250 else 2850
        try {
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = if (quick) 550 else 1200
            connection.readTimeout = if (quick) 650 else 1500
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept-Encoding", "identity")
            connection.setRequestProperty("Connection", "close")
            if (!root) connection.setRequestProperty("Accept", "application/json")
            if (operation.cancelled.get()) throw LanFailure("cancelled")
            val status = connection.responseCode
            if (status !in 100..599) throw LanFailure("invalidResponse")
            val contentType = connection.contentType.orEmpty().substringBefore(';').trim().lowercase()
            val body = if (!root && status == 200 && contentType == "application/json") {
                val encoding = connection.contentEncoding
                if (encoding != null && !encoding.equals("identity", ignoreCase = true)) {
                    throw LanFailure("invalidResponse")
                }
                if (connection.contentLength > MAX_DESCRIPTOR) throw LanFailure("tooLarge")
                val bytes = ByteArrayOutputStream()
                val buffer = ByteArray(2048)
                connection.inputStream.use { input ->
                    while (true) {
                        if (operation.cancelled.get()) throw LanFailure("cancelled")
                        if (SystemClock.elapsedRealtime() >= deadline) throw LanFailure("timeout")
                        val length = input.read(buffer)
                        if (length < 0) break
                        if (bytes.size() + length > MAX_DESCRIPTOR) throw LanFailure("tooLarge")
                        bytes.write(buffer, 0, length)
                    }
                }
                bytes.toByteArray()
            } else ByteArray(0)
            assertCurrent(scope)
            return mapOf("status" to status, "contentType" to contentType, "body" to body)
        } finally {
            operation.httpConnection.getAndSet(null)?.disconnect()
        }
    }

    @Suppress("DEPRECATION")
    private inner class MdnsSearch(
        private val scope: WifiLink,
        private val id: Int,
        private val operation: Operation,
    ) : NsdManager.DiscoveryListener {
        private val seen = mutableSetOf<String>()
        private val queue = ArrayDeque<NsdServiceInfo>()
        private val devices = mutableListOf<Map<String, Any>>()
        private var active = true
        private var resolver: NsdManager.ResolveListener? = null
        private var lock: WifiManager.MulticastLock? = null

        fun start() {
            operation.cleanup = ::stop
            if (Build.VERSION.SDK_INT < 34) {
                lock = context.getSystemService(WifiManager::class.java)
                    .createMulticastLock("esp-iot-discover").apply {
                        setReferenceCounted(false)
                        acquire()
                    }
            }
            operation.deadline = Runnable {
                try {
                    assertCurrent(scope)
                    finish(id, operation, devices.toList())
                } catch (error: Exception) {
                    finish(id, operation, failure = failureFor(error))
                }
            }.also { handler.postDelayed(it, 3600) }
            if (Build.VERSION.SDK_INT >= 33) {
                nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, scope.network, context.mainExecutor, this)
            } else {
                nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, this)
            }
        }

        private fun stop() {
            active = false
            runCatching { nsd.stopServiceDiscovery(this) }
            if (Build.VERSION.SDK_INT >= 34) {
                resolver?.let { runCatching { nsd.stopServiceResolution(it) } }
            }
            lock?.let { if (it.isHeld) it.release() }
            lock = null
            queue.clear()
        }

        override fun onDiscoveryStarted(type: String) {
            handler.post { if (!active) runCatching { nsd.stopServiceDiscovery(this) } }
        }

        override fun onDiscoveryStopped(type: String) {}
        override fun onServiceLost(info: NsdServiceInfo) {}
        override fun onStopDiscoveryFailed(type: String, code: Int) {}

        override fun onStartDiscoveryFailed(type: String, code: Int) {
            handler.post { finish(id, operation, failure = LanFailure("mdns")) }
        }

        override fun onServiceFound(info: NsdServiceInfo) {
            handler.post {
                if (!active || seen.size >= 20 || !seen.add(info.serviceName)) return@post
                queue.addLast(info)
                resolveNext()
            }
        }

        private fun resolveNext() {
            if (!active || resolver != null || queue.isEmpty()) return
            val info = queue.removeFirst()
            val listener = object : NsdManager.ResolveListener {
                override fun onResolveFailed(service: NsdServiceInfo, error: Int) {
                    handler.post { resolver = null; resolveNext() }
                }

                override fun onServiceResolved(service: NsdServiceInfo) {
                    handler.post {
                        resolver = null
                        if (!active) return@post
                        addResolved(service)
                        resolveNext()
                    }
                }
            }
            resolver = listener
            try {
                nsd.resolveService(info, listener)
            } catch (_: IllegalArgumentException) {
                resolver = null
                resolveNext()
            }
        }

        private fun addResolved(service: NsdServiceInfo) {
            if (service.port !in 1..65535) return
            if (Build.VERSION.SDK_INT >= 33 && service.network != null && service.network != scope.network) return
            val addresses = if (Build.VERSION.SDK_INT >= 34) service.hostAddresses else listOfNotNull(service.host)
            val host = addresses.filterIsInstance<Inet4Address>().firstOrNull(scope::allows) ?: return
            val attributes = service.attributes
            val version = attributes["v"]?.toString(Charsets.UTF_8)
            val tls = attributes["tls"]?.toString(Charsets.UTF_8)
            if ((version != null && version != "1") || (tls != null && tls != "0" && tls != "1")) return
            val data = mutableMapOf<String, Any>(
                "host" to host.hostAddress!!,
                "port" to service.port,
                "secure" to (tls == "1"),
                "service" to service.serviceName.take(64),
            )
            attributes["id"]?.toString(Charsets.UTF_8)?.let { data["deviceId"] = it }
            if (Build.VERSION.SDK_INT >= 36) service.hostname?.let { data["hostname"] = it.take(64) }
            devices.add(data)
        }
    }

    private class Operation(val result: MethodChannel.Result) {
        var future: Future<*>? = null
        var deadline: Runnable? = null
        var cleanup: (() -> Unit)? = null
        val cancelled = AtomicBoolean()
        val udpSocket = AtomicReference<DatagramSocket?>()
        val httpConnection = AtomicReference<HttpURLConnection?>()
    }

    private data class WifiLink(val network: Network, val address: Inet4Address, val prefix: Int) {
        private val number = address.number()
        private val mask = (0xffffffffL shl (32 - prefix)) and 0xffffffffL
        private val first = number and mask
        private val last = first or (mask xor 0xffffffffL)

        fun isPrivateSubnet() = prefix in 8..30 && first.isPrivate() && last.isPrivate() && number in (first + 1) until last
        fun allows(host: Inet4Address) = host.number().let { it != number && it in (first + 1) until last }
        fun broadcast() = InetAddress.getByAddress(ByteArray(4) { (last shr (24 - it * 8)).toByte() })
        fun toMap(isDefault: Boolean) = mapOf(
            "address" to address.hostAddress!!,
            "prefix" to prefix,
            "networkId" to network.networkHandle,
            "isDefault" to isDefault,
        )
    }

    private class LanFailure(val code: String) : IOException(code)

    private companion object {
        const val SERVICE = "_espiot._tcp"
        const val UDP_PORT = 55073
        const val MAX_DESCRIPTOR = 32 * 1024
        val HEX_ID = Regex("[a-f0-9]{32}")
        val IPV4 = Regex("(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}")

        fun parseIpv4(host: String): Inet4Address? {
            if (!IPV4.matches(host)) return null
            val parts = host.split('.').map { it.toInt() }
            if (parts.any { it > 255 }) return null
            return InetAddress.getByAddress(ByteArray(4) { parts[it].toByte() }) as Inet4Address
        }

        fun Inet4Address.number() = address.fold(0L) { number, byte -> (number shl 8) or (byte.toLong() and 255) }
        fun Long.isPrivate() = this shr 24 == 10L || this shr 20 == 0xac1L || this shr 16 == 0xc0a8L

        fun failureFor(error: Exception) = when (error) {
            is LanFailure -> error
            is SecurityException -> LanFailure("permission")
            is SocketTimeoutException -> LanFailure("timeout")
            is SSLException -> LanFailure("certificate")
            is RejectedExecutionException -> LanFailure("busy")
            else -> LanFailure("unreachable")
        }
    }
}
