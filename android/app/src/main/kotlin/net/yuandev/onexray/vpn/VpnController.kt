package net.yuandev.onexray.vpn

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutManager
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.TileService
import android.widget.Toast
import androidx.core.content.ContextCompat
import com.elvishew.xlog.XLog
import net.yuandev.onexray.MainActivity
import net.yuandev.onexray.R
import net.yuandev.onexray.pigeon.PlatformPermissionKind
import net.yuandev.onexray.pigeon.PlatformPermissionResult
import net.yuandev.onexray.pigeon.PlatformPermissionState
import net.yuandev.onexray.tile.OneQuickSettingsTileService
import java.io.File
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.SocketException
import java.util.concurrent.atomic.AtomicLong

object VpnController {
    enum class SavedStartResult { STARTED, OPEN_APP, FAILED }

    var lastError: String? = null
    private val lastStartRequestId = AtomicLong(0)
    private const val stopRequestRelativePath = "run/vpn.stop"
    private val vpnAddresses by lazy {
        setOf(
            InetAddress.getByName(OneVpnService.IPV4_ADDRESS),
            InetAddress.getByName(OneVpnService.IPV6_ADDRESS),
        )
    }

    fun readVpnRunning(context: Context): Boolean {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return false
            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()
                if (!isVpnInterfaceName(networkInterface.name) || !networkInterface.isUp) {
                    continue
                }
                val addresses = networkInterface.inetAddresses
                while (addresses.hasMoreElements()) {
                    if (matchesVpnAddress(addresses.nextElement())) {
                        return true
                    }
                }
            }
        } catch (_: SocketException) {
            return false
        }

        return false
    }

    fun buildShortcutStartIntent(context: Context): Intent {
        // Missing configuration or permission still goes through the App coordinator.
        val shortcutIntent = try {
            context.getSystemService(ShortcutManager::class.java)
                ?.dynamicShortcuts?.firstOrNull { it.id == "startVpn" }
                ?.intent?.let { Intent(it) }
        } catch (_: RuntimeException) {
            XLog.w("VpnController: unable to read start shortcut; opening App")
            null
        }
        return (shortcutIntent ?: Intent(context, MainActivity::class.java)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    fun buildStartIntent(context: Context): Intent =
        Intent(context, OneVpnService::class.java).apply {
            action = OneVpnService.ACTION_START
        }

    fun queryPermission(context: Context): PlatformPermissionResult {
        val kind = when {
            VpnService.prepare(context) != null -> PlatformPermissionKind.ANDROID_VPN
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.CINNAMON_BUN &&
                context.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) !=
                PackageManager.PERMISSION_GRANTED -> PlatformPermissionKind.ANDROID_LOCAL_NETWORK
            else -> return PlatformPermissionResult(
                PlatformPermissionKind.ANDROID_VPN, PlatformPermissionState.GRANTED, null,
            )
        }
        return PlatformPermissionResult(kind, PlatformPermissionState.NOT_DETERMINED, null)
    }

    fun startFile(context: Context): File = File(context.filesDir, "run/start.json")

    fun startSavedVpn(context: Context, automation: Boolean = false): SavedStartResult {
        lastError = null
        try {
            SavedVpnConfig.read(startFile(context))
            val permission = queryPermission(context)
            if (permission.state != PlatformPermissionState.GRANTED) {
                lastError = context.getString(if (permission.kind == PlatformPermissionKind.ANDROID_LOCAL_NETWORK)
                    R.string.automation_lan_permission else R.string.automation_vpn_permission)
                return SavedStartResult.OPEN_APP
            }
        } catch (error: Exception) {
            lastError = context.getString(R.string.automation_configuration_required, error.message ?: "")
            return SavedStartResult.OPEN_APP
        }
        return if (startVpn(context, reuseConfiguration = true, automation = automation)) SavedStartResult.STARTED
            else SavedStartResult.FAILED
    }

    /** Internal native launch identity, unrelated to subscription or profile IDs. */
    fun newStartRequestId(after: Long = 0): Long {
        while (true) {
            val previous = lastStartRequestId.get()
            val next = maxOf(SystemClock.elapsedRealtimeNanos(), previous + 1, after + 1)
            if (lastStartRequestId.compareAndSet(previous, next)) return next
        }
    }

    fun startVpn(
        context: Context,
        reuseConfiguration: Boolean = false,
        automation: Boolean = false,
        startRequestId: Long = newStartRequestId(),
    ): Boolean {
        lastError = null
        if (!clearStopRequest(context)) {
            lastError = "Unable to clear the VPN stop marker."
            return false
        }
        return try {
            val intent = buildStartIntent(context)
                .putExtra(OneVpnService.EXTRA_REUSE_CONFIGURATION, reuseConfiguration)
                .putExtra(OneVpnService.EXTRA_AUTOMATION_START, automation)
                .putExtra(OneVpnService.EXTRA_START_REQUEST_ID, startRequestId)
            ContextCompat.startForegroundService(context, intent)
            true
        } catch (error: RuntimeException) {
            XLog.e("VpnController: failed to start VPN service", error)
            lastError = error.message ?: error.toString()
            false
        }
    }

    fun reportStartFailure(context: Context, reason: String?, showToast: Boolean = true, stopping: Boolean = false) {
        val title = context.getString(if (stopping) R.string.notification_vpn_stop_failed else R.string.notification_vpn_start_failed)
        val text = reason?.takeIf { it.isNotBlank() } ?: title
        if (showToast) Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = "net.yuandev.onexray"
            manager.createNotificationChannel(NotificationChannel(
                channel, context.getString(R.string.quick_settings_tile_label), NotificationManager.IMPORTANCE_DEFAULT,
            ))
            val openApp = PendingIntent.getActivity(
                context, 3, Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            manager.notify(if (showToast && !stopping) OneVpnService.NOTIFICATION_ID else 4, Notification.Builder(context, channel)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(openApp)
                .setAutoCancel(true)
                .build())
        } catch (error: Exception) {
            // Notification permission must not change the VPN result or open the App.
            XLog.e("Unable to show VPN start failure", error)
        }
    }

    fun stopVpn(context: Context): Boolean {
        lastError = null
        val markerWritten = writeStopRequest(context)
        val broadcastSent = try {
            context.sendBroadcast(
                Intent(OneVpnService.ACTION_STOP_REQUEST).setPackage(context.packageName)
            )
            true
        } catch (error: RuntimeException) {
            XLog.e("VpnController: failed to broadcast VPN stop", error)
            lastError = error.message ?: error.toString()
            false
        }
        if (!markerWritten && lastError == null) lastError = "Unable to write the VPN stop marker."
        return markerWritten && broadcastSent
    }

    fun consumeStopRequest(context: Context): Boolean {
        val file = stopRequestFile(context)
        return try {
            if (!file.isFile) {
                false
            } else {
                if (!file.delete()) {
                    XLog.w("VpnController: failed to consume VPN stop marker")
                }
                true
            }
        } catch (error: Exception) {
            XLog.e("VpnController: failed to read VPN stop marker", error)
            true
        }
    }

    fun requestTileRefresh(context: Context) {
        TileService.requestListeningState(
            context,
            ComponentName(context, OneQuickSettingsTileService::class.java)
        )
    }

    private fun isVpnInterfaceName(name: String?): Boolean =
        !name.isNullOrBlank() && name.startsWith("tun")

    private fun matchesVpnAddress(address: InetAddress?): Boolean =
        address != null && vpnAddresses.any { it == address }

    private fun stopRequestFile(context: Context): File =
        File(context.filesDir, stopRequestRelativePath)

    private fun writeStopRequest(context: Context): Boolean = try {
        val file = stopRequestFile(context)
        val parent = file.parentFile
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            XLog.e("VpnController: failed to create VPN run directory")
            false
        } else {
            file.writeText("stop")
            true
        }
    } catch (error: Exception) {
        XLog.e("VpnController: failed to write VPN stop marker", error)
        false
    }

    private fun clearStopRequest(context: Context): Boolean = try {
        val file = stopRequestFile(context)
        !file.exists() || file.delete().also { deleted ->
            if (!deleted) {
                XLog.e("VpnController: failed to clear VPN stop marker")
            }
        }
    } catch (error: Exception) {
        XLog.e("VpnController: failed to clear VPN stop marker", error)
        false
    }
}
