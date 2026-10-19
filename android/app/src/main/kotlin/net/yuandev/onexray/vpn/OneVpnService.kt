package net.yuandev.onexray.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.Binder
import android.os.IBinder
import android.os.Parcel
import android.os.ParcelFileDescriptor
import android.util.AtomicFile
import androidx.core.content.ContextCompat
import com.elvishew.xlog.XLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import libXray.DialerController
import libXray.LibXray
import net.yuandev.onexray.MainActivity
import net.yuandev.onexray.R
import net.yuandev.onexray.automation.AutomationStore
import net.yuandev.onexray.widget.TrafficWidgetProvider
import net.yuandev.onexray.pigeon.JsonTool
import net.yuandev.onexray.pigeon.LibXrayInvokeRequest
import net.yuandev.onexray.pigeon.LibXrayInvokeResponse
import net.yuandev.onexray.pigeon.LibXrayMethod
import net.yuandev.onexray.pigeon.PerAppVPNMode
import net.yuandev.onexray.pigeon.StartVpnRequest
import net.yuandev.onexray.pigeon.TunJson
import net.yuandev.onexray.pigeon.VpnStatus
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference


class OneVpnService : VpnService() {
    companion object {
        const val ACTION_START: String = "vpn_start"
        const val EXTRA_REUSE_CONFIGURATION: String = "reuse_configuration"
        const val EXTRA_AUTOMATION_START: String = "automation_start"
        const val EXTRA_START_REQUEST_ID: String = "start_request_id"
        const val ACTION_STOP: String = "vpn_stop"
        const val ACTION_STOP_REQUEST: String = "net.yuandev.onexray.VPN_STOP_REQUEST"

        const val IPV4_ADDRESS = "198.18.0.1"
        const val IPV6_ADDRESS = "fc00::1"
        const val ACTION_VPN_STATUS: String = "net.yuandev.onexray.VPN_STATUS"
        const val EXTRA_RUNNING: String = "running"
        const val EXTRA_STARTING: String = "starting"
        const val EXTRA_ERROR: String = "error"
        const val NOTIFICATION_OPEN_REQUEST_CODE = 1
        const val NOTIFICATION_STOP_REQUEST_CODE = 2
        const val NOTIFICATION_ID = 1

        // Core retains protection callbacks for the lifetime of :native.
        private val controller = VPNController()
        private var controllerInit = false

        @Synchronized
        private fun initController() {
            if (controllerInit) return
            LibXray.registerDialerController(controller)
            LibXray.registerListenerController(controller)
            controllerInit = true
        }
    }

    @Volatile
    private var tunnel: ParcelFileDescriptor? = null

    private val tunMtu = 1500
    @Volatile
    private var running = false
    private var backgroundStart = false
    private val startGeneration = AtomicInteger(0)
    private val released = AtomicBoolean(true)
    @Volatile
    private var currentStartRequestId = 0L

    private val resourceStatus: VpnStatus
        get() = when {
            running && !released.get() -> VpnStatus.CONNECTED
            released.get() && tunnel != null -> VpnStatus.DISCONNECTING
            !released.get() -> VpnStatus.CONNECTING
            else -> VpnStatus.DISCONNECTED
        }

    private fun sendStatusBroadcast(running: Boolean, error: String? = null) {
        val intent = Intent(ACTION_VPN_STATUS).apply {
            setPackage(packageName) // 限定仅本包接收
            putExtra(EXTRA_RUNNING, running)
            putExtra(EXTRA_STARTING, resourceStatus == VpnStatus.CONNECTING)
            putExtra(EXTRA_ERROR, error)
            putExtra(EXTRA_START_REQUEST_ID, currentStartRequestId)
        }
        sendBroadcast(intent)
        VpnController.requestTileRefresh(this)
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val trafficMonitor by lazy {
        TrafficMonitor(this, scope) { sample ->
            if (running && !released.get()) {
                updateWidget(VpnStatus.CONNECTED, sample)
                try {
                    getSystemService(NotificationManager::class.java)
                        .notify(NOTIFICATION_ID, makeNotification(sample))
                } catch (error: Exception) {
                    XLog.e("Update VPN notification failed", error)
                }
            }
        }
    }

    private fun updateWidget(status: VpnStatus, sample: TrafficSample? = null) {
        try {
            TrafficWidgetProvider.publish(this, status, sample)
        } catch (error: Exception) {
            XLog.e("Update traffic widget failed", error)
        }
    }
    private val stopRequestReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ACTION_STOP_REQUEST) {
                XLog.d("OneVpnService: received stop request")
                stopTun()
            }
        }
    }
    private var stopRequestReceiverRegistered = false

    private val statusBinder = object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code != VpnStatusConnection.READ_STATUS) return super.onTransact(code, data, reply, flags)
            data.enforceInterface(VpnStatusConnection.DESCRIPTOR)
            reply?.writeNoException()
            reply?.writeInt(resourceStatus.ordinal)
            reply?.writeLong(currentStartRequestId)
            return true
        }
    }

    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == VpnStatusConnection.ACTION_BIND) statusBinder else super.onBind(intent)

    override fun onRevoke() {
        stopTun()
    }

    private class VPNController : DialerController {
        private val vpn = AtomicReference<OneVpnService?>()

        fun attach(service: OneVpnService) {
            vpn.set(service)
        }

        fun release(service: OneVpnService) {
            vpn.compareAndSet(service, null)
        }

        override fun protectFd(p0: Long): Boolean {
            val socket = p0.toInt()
            return vpn.get()?.protect(socket) == true
        }
    }

    override fun onCreate() {
        super.onCreate()
        initService()
        val filter = IntentFilter(ACTION_STOP_REQUEST)
        ContextCompat.registerReceiver(
            this,
            stopRequestReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        stopRequestReceiverRegistered = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        XLog.d("OneVpnService: onStartCommand ${intent?.action}")
        if (intent != null && intent.action == ACTION_STOP) {
            XLog.d("OneVpnService: onStartCommand $ACTION_STOP running=$running")
            stopTun()
            return START_NOT_STICKY
        }
        if (intent != null && intent.action == ACTION_START) {
            XLog.d("OneVpnService: onStartCommand $ACTION_START running=$running")
            val status = resourceStatus
            if (status == VpnStatus.DISCONNECTED) {
                currentStartRequestId = intent.getLongExtra(EXTRA_START_REQUEST_ID, 0L)
                    .takeIf { it > 0 } ?: VpnController.newStartRequestId()
            }
            if (intent.getBooleanExtra(EXTRA_AUTOMATION_START, false) && AutomationStore(this).startBlocked) {
                // A clear/restore may have started after the receiver dispatched this command.
                if (resourceStatus == VpnStatus.DISCONNECTED) stopSelf(startId)
                return START_NOT_STICKY
            }
            if (VpnController.consumeStopRequest(this)) {
                XLog.d("OneVpnService: start cancelled by pending stop request")
                stopTun()
                return START_NOT_STICKY
            }
            if (status == VpnStatus.DISCONNECTED) {
                backgroundStart = intent.getBooleanExtra(EXTRA_REUSE_CONFIGURATION, false)
                startTun(startId)
            } else {
                updateWidget(status)
            }
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (stopRequestReceiverRegistered) {
            try {
                unregisterReceiver(stopRequestReceiver)
            } catch (_: IllegalArgumentException) {
            }
            stopRequestReceiverRegistered = false
        }
        releaseTun()
        scope.cancel()
        super.onDestroy()
    }

    private fun initService() {
        XLog.init()
        val appName = getString(R.string.quick_settings_tile_label)
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("net.yuandev.onexray", appName, NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = appName }
        )
    }

    private fun startTun(startId: Int) {
        XLog.d("OneVpnService: startTun $startId request=$currentStartRequestId")
        if (!released.compareAndSet(true, false)) {
            XLog.d("OneVpnService: startTun ignored because VPN resources are active")
            return
        }
        val generation = startGeneration.incrementAndGet()
        try {
            updateWidget(VpnStatus.CONNECTING)
            showNotification()
            // Subscribe the UI to this service's death during Core startup,
            // without acknowledging CONNECTED before the Core succeeds.
            sendStatusBroadcast(false)
            val file = VpnController.startFile(this)
            val saved = SavedVpnConfig.read(file)
            val model = if (backgroundStart) {
                SavedVpnConfig.renewSession(saved, System.currentTimeMillis() * 1000).also {
                    val atomic = AtomicFile(file)
                    val output = atomic.startWrite()
                    try {
                        output.write(JsonTool.json.encodeToString(it).toByteArray(Charsets.UTF_8))
                        atomic.finishWrite(output)
                    } catch (error: Exception) {
                        atomic.failWrite(output)
                        throw error
                    }
                }
            } else saved
            runTun(model, generation)
        } catch (e: Exception) {
            failStart("OneVpnService: startTun failed", e, generation)
        }
    }

    private fun stopTun() {
        if (!releaseTun()) {
            trafficMonitor.stop()
            updateWidget(VpnStatus.DISCONNECTED)
            stopForeground(STOP_FOREGROUND_REMOVE)
            sendStatusBroadcast(false)
        }
        stopSelf()
    }

    private fun releaseTun(error: String? = null): Boolean {
        if (!released.compareAndSet(false, true)) {
            return false
        }
        startGeneration.incrementAndGet()
        trafficMonitor.stop()
        updateWidget(VpnStatus.DISCONNECTING)
        XLog.d("OneVpnService: stopTun")
        stopForeground(STOP_FOREGROUND_REMOVE)
        try {
            stopXray()
        } catch (e: Exception) {
            XLog.d("OneVpnService: stopTun stopXray exception")
            XLog.d(e)
        }
        try {
            LibXray.resetDNS()
        } catch (e: Exception) {
            XLog.d("OneVpnService: stopTun resetDNS exception")
            XLog.d(e)
        }
        try {
            tunnel?.close()
        } catch (e: Exception) {
            XLog.d("OneVpnService: stopTun close tunnel exception")
            XLog.d(e)
        }
        tunnel = null
        controller.release(this)
        running = false
        updateWidget(VpnStatus.DISCONNECTED)
        sendStatusBroadcast(false, error)
        return true
    }

    private fun failStart(message: String, error: Exception, generation: Int? = null) {
        if (generation != null && generation != startGeneration.get()) {
            XLog.d("$message ignored for stale start generation=$generation")
            XLog.d(error)
            return
        }
        XLog.e(message, error)
        val reason = error.message ?: error.toString()
        if (!releaseTun(reason)) sendStatusBroadcast(false, reason)
        if (backgroundStart) VpnController.reportStartFailure(this, reason)
        stopSelf()
    }

    private fun showNotification() {
        val notification = makeNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun makeNotification(sample: TrafficSample? = null): Notification {
        val appName = getString(R.string.quick_settings_tile_label)
        val channelId = "net.yuandev.onexray"

        val openPendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_OPEN_REQUEST_CODE,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stopPendingIntent = PendingIntent.getService(
            this,
            NOTIFICATION_STOP_REQUEST_CODE,
            Intent(this, OneVpnService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val text = if (running) TrafficSample.speedText(sample)
            else getString(R.string.quick_settings_tile_status_connecting)
        val details = if (running)
            "$text\n${getString(R.string.traffic_this_connection)}: ${TrafficSample.sessionText(sample)}"
            else text
        return Notification.Builder(this, channelId)
            .setContentTitle(appName)
            .setSubText(if (running) getString(R.string.notification_vpn_connected) else null)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(details))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(openPendingIntent)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.mipmap.ic_launcher),
                    getString(R.string.notification_action_open),
                    openPendingIntent
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.pause_light),
                    getString(R.string.notification_action_disconnect),
                    stopPendingIntent
                ).build()
            )
            .build()
    }

    private fun runTun(
        request: StartVpnRequest,
        generation: Int,
    ) {
        if (generation != startGeneration.get() || tunnel != null) {
            return
        }
        XLog.d("OneVpnService: runTun tunnel = null")
        val builder = Builder()
        val tun = requireNotNull(request.tun) { "missing TUN config" }
        setPerAppVpn(tun, builder)
        setIPAndDns(tun, builder)

        val establishedTunnel = builder.establish()
            ?: throw IllegalStateException("failed to establish VPN tunnel")
        if (generation != startGeneration.get()) {
            establishedTunnel.close()
            return
        }
        tunnel = establishedTunnel

        XLog.d("OneVpnService: runTun tunnel = ${tunnel?.fd}")

        val coreInvokeText = requireNotNull(request.coreInvokeText) {
            "missing Xray run request"
        }
        controller.attach(this)
        configureDNS(tun)
        runXray(coreInvokeText, establishedTunnel, generation, request.metricsPort)
    }

    private fun configureDNS(tun: TunJson) {
        val dns = tun.tunDnsIPv4?.trim()
        require(!dns.isNullOrEmpty()) { "missing IPv4 TUN DNS" }
        LibXray.setDNS(controller, "$dns:53")
    }

    private fun setIPAndDns(tun: TunJson, builder: Builder) {
        builder.addAddress(IPV4_ADDRESS, 15)
            .addRoute("0.0.0.0", 0)
            .setMtu(tunMtu)
        tun.tunDnsIPv4?.let {
            builder.addDnsServer(it)
        }

        tun.enableIPv6?.let {
            if (it) {
                builder.addAddress(IPV6_ADDRESS, 64)
                    .addRoute("::", 0)
                tun.tunDnsIPv6?.let { dnsIPv6 ->
                    builder.addDnsServer(dnsIPv6)
                }
            }
        }
    }

    private fun setPerAppVpn(tun: TunJson, builder: Builder) {
        tun.perAppVPNMode?.let {
            when (it) {
                PerAppVPNMode.ALLOW -> addAllowedApplication(tun.allowAppList, builder)
                PerAppVPNMode.DISALLOW -> addDisallowedApplication(tun.disallowAppList, builder)
            }
        }
    }

    private fun addAllowedApplication(appList: List<String>?, builder: Builder) {
        var allowed = 0
        for (appPackage in appList.orEmpty().distinct()) {
            try {
                packageManager.getPackageInfo(appPackage, 0)
                builder.addAllowedApplication(appPackage)
                allowed++
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }
        // No addAllowedApplication calls would otherwise mean every installed app.
        require(allowed > 0) { "Select at least one installed app before connecting" }
    }

    private fun addDisallowedApplication(appList: List<String>?, builder: Builder) {
        appList?.let {
            if (it.isNotEmpty()) {
                for (appPackage in it) {
                    try {
                        packageManager.getPackageInfo(appPackage, 0)
                        builder.addDisallowedApplication(appPackage)
                    } catch (_: PackageManager.NameNotFoundException) {
                    }
                }
            }
        }
    }

    private fun runXray(
        coreInvokeText: String,
        establishedTunnel: ParcelFileDescriptor,
        generation: Int,
        metricsPort: String?,
    ) {
        scope.launch {
            try {
                initController()
                if (generation != startGeneration.get() || tunnel !== establishedTunnel) {
                    return@launch
                }
                val result = LibXray.invoke(patchRuntimeEnv(coreInvokeText, establishedTunnel.fd))
                validateRunXrayResult(result)
                if (generation != startGeneration.get() || tunnel !== establishedTunnel) {
                    XLog.d("OneVpnService: stale runXray result ignored")
                    if (tunnel == null) {
                        stopXray()
                    }
                    return@launch
                }
                withContext(Dispatchers.Main) {
                    if (generation != startGeneration.get() || tunnel !== establishedTunnel) return@withContext
                    XLog.d("OneVpnService: Xray started")
                    running = true
                    sendStatusBroadcast(true)
                    try {
                        trafficMonitor.start(metricsPort)
                    } catch (error: Exception) {
                        // Presentation failure must not tear down a running VPN.
                        XLog.e("Start traffic display failed", error)
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    failStart("OneVpnService: runXray failed", e, generation)
                }
            }
        }
    }

    private fun validateRunXrayResult(result: String) {
        val response = JsonTool.json.decodeFromString<LibXrayInvokeResponse>(result)
        if (!response.success) {
            throw IllegalStateException(response.error)
        }
    }

    private fun stopXray() {
        val request = LibXrayInvokeRequest(method = LibXrayMethod.STOP_XRAY)
        LibXray.invoke(JsonTool.json.encodeToString(request))
    }

    private fun patchRuntimeEnv(requestJson: String, fd: Int): String {
        try {
            val request = JsonTool.json.decodeFromString<LibXrayInvokeRequest>(requestJson)
            val payload = request.payload
                ?: throw IllegalStateException("runXray payload is empty")
            val xrayJson = payload.xrayJson
                ?: throw IllegalStateException("xrayJson is empty")
            if (xrayJson.isEmpty()) {
                throw IllegalStateException("xrayJson is empty")
            }
            val updatedPayload = payload.copy(
                xrayJson = RuntimeTunConfig.withTunFd(xrayJson, fd),
            )
            return JsonTool.json.encodeToString(request.copy(payload = updatedPayload))
        } catch (_: IllegalArgumentException) {
            throw IllegalStateException("invalid Xray run request")
        }
    }
}
