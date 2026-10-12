package net.yuandev.onexray.pigeon

import android.Manifest
import android.app.Activity.RESULT_OK
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.VpnService
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import com.elvishew.xlog.XLog
import com.hjq.permissions.Permission
import com.hjq.permissions.XXPermissions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import libXray.LibXray
import net.yuandev.onexray.vpn.VpnController
import net.yuandev.onexray.vpn.VpnStatusConnection
import java.io.ByteArrayOutputStream

class AppHostApi(
    private val context: Context,
) : BridgeHostApi {
    private val vpnStatus = VpnStatusConnection(context) { status ->
        scope.launch { flutterApi?.vpnStatusChanged(status) }
    }
    private val activity = context as FragmentActivity
    private val prepareResult =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            val callback = permissionCallback
            permissionCallback = null
            if (it.resultCode == RESULT_OK) {
                callback?.invoke(queryPermissionNow())
            } else {
                callback?.invoke(androidPermissionDenied())
                onVpnStatusChanged(false)
            }
        }

    fun onVpnStatusChanged(
        running: Boolean,
        error: String? = null,
        startRequestId: Long = 0L,
        starting: Boolean = false,
    ) {
        XLog.d("AppHostApi: onVpnStatusChanged running=$running starting=$starting request=$startRequestId")
        scope.launch(Dispatchers.Main.immediate) {
            try { vpnStatus.changed(running, error, startRequestId, starting) }
            catch (failure: Exception) {
                XLog.e("VPN status notification failed", failure)
            }
        }
    }

    private var flutterApi: AppFlutterApi? = null

    fun onInit(api: AppFlutterApi) {
        XLog.init()
        flutterApi = api
        scope.launch {
            try { api.vpnStatusChanged(vpnStatus.read()) }
            catch (error: Exception) { XLog.e("Initial VPN status failed", error) }
        }
    }

    fun onDestroy() {
        vpnStatus.close()
        scope.cancel()
    }

    private var permissionCallback: ((PlatformPermissionResult) -> Unit)? = null

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val invokeMutex = Mutex()

    override fun getTunFilesDir(callback: (Result<String>) -> Unit) {
        val dirPath = context.filesDir.path
        callback(Result.success(dirPath))
    }

    override fun readVpnStatus(callback: (Result<NativeVpnCommandResult>) -> Unit) {
        scope.launch {
            try {
                val status = vpnStatus.read()
                callback(Result.success(NativeVpnCommandResult(
                    state = NativeVpnCommandState.SUCCESS,
                    permission = queryPermissionNow(),
                    status = status,
                    message = if (status == VpnStatus.DISCONNECTED) VpnController.lastError else null
                )))
            } catch (error: Exception) {
                VpnController.lastError = error.message ?: error.toString()
                callback(Result.success(commandFailed(queryPermissionNow())))
            }
        }
    }

    override fun startVpn(callback: (Result<NativeVpnCommandResult>) -> Unit) {
        XLog.d("AppHostApi: startVpn called")
        scope.launch {
            val permission = queryPermissionNow()
            if (permission.state != PlatformPermissionState.GRANTED) {
                callback(Result.success(waitingForPermission(permission)))
                return@launch
            }
            try {
                val status = vpnStatus.command(VpnStatus.CONNECTED) { startRequestId ->
                    VpnController.startVpn(context, startRequestId = startRequestId)
                }
                callback(Result.success(commandSuccess(permission, status)))
            } catch (error: Exception) {
                VpnController.lastError = error.message ?: error.toString()
                callback(Result.success(commandFailed(permission)))
            }
        }
    }

    override fun stopVpn(callback: (Result<NativeVpnCommandResult>) -> Unit) {
        XLog.d("AppHostApi: stopVpn called")
        scope.launch {
            try {
                val status = vpnStatus.command(VpnStatus.DISCONNECTED) { VpnController.stopVpn(context) }
                callback(Result.success(commandSuccess(queryPermissionNow(), status)))
            } catch (error: Exception) {
                VpnController.lastError = error.message ?: error.toString()
                callback(Result.success(commandFailed(queryPermissionNow())))
            }
        }
    }

    override fun invoke(requestJson: String, callback: (Result<String>) -> Unit) {
        scope.launch {
            // Temporary cores share process-global Xray state. The VPN runs in :native.
            invokeMutex.withLock {
                callback(runCatching { LibXray.invoke(requestJson) })
            }
        }
    }

    override fun queryPlatformPermission(callback: (Result<PlatformPermissionResult>) -> Unit) {
        scope.launch {
            callback(Result.success(queryPermissionNow()))
        }
    }

    override fun requestPlatformPermission(callback: (Result<PlatformPermissionResult>) -> Unit) {
        scope.launch {
            val permission = queryPermissionNow()
            if (permission.state == PlatformPermissionState.GRANTED) {
                callback(Result.success(permission))
                return@launch
            }
            val prepare = VpnService.prepare(context)
            if (prepare == null) {
                callback(Result.success(queryPermissionNow()))
                return@launch
            }
            if (permissionCallback != null) {
                callback(
                    Result.success(
                        PlatformPermissionResult(
                            PlatformPermissionKind.ANDROID_VPN,
                            PlatformPermissionState.AWAITING_USER_APPROVAL,
                            "Android VPN permission is already pending.",
                        )
                    )
                )
                return@launch
            }
            permissionCallback = { result ->
                callback(Result.success(result))
            }
            activity.runOnUiThread {
                prepareResult.launch(prepare)
            }
        }
    }


    override fun getInstalledApps(callback: (Result<List<AndroidAppInfo>>) -> Unit) {
        scope.launch {
            checkInstalledAppPermission {
                if (it) {
                    val packageManager = context.packageManager
                    val installedApps = packageManager.getInstalledApplications(0)
                    val apps = mutableListOf<AndroidAppInfo>()
                    for (info in installedApps) {
                        val appInfo =
                            AndroidAppInfo(
                                packageManager.getApplicationLabel(info).toString(),
                                info.packageName,
                            )
                        apps.add(appInfo)
                    }
                    callback(Result.success(apps))
                } else {
                    callback(Result.success(listOf()))
                }
            }
        }
    }

    override fun getAppIcon(packageName: String, callback: (Result<ByteArray?>) -> Unit) {
        scope.launch {
            callback(Result.success(loadAppIconBytes(packageName)))
        }
    }

    private fun checkInstalledAppPermission(callback: (Boolean) -> Unit) {
        // android 11, level 30
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val permissions = mutableListOf<String>()
            permissions.add(Manifest.permission.QUERY_ALL_PACKAGES)
            permissions.add(Permission.GET_INSTALLED_APPS)
            XXPermissions.with(context)
                .permission(permissions)
                .request { _, allGranted ->
                    callback(allGranted)
                }
        } else {
            callback(true)
        }
    }

    private fun loadAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = context.packageManager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888)
            try {
                drawable.setBounds(0, 0, ICON_SIZE_PX, ICON_SIZE_PX)
                drawable.draw(Canvas(bitmap))
                val stream = ByteArrayOutputStream()
                if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    stream.toByteArray()
                } else {
                    null
                }
            } finally {
                bitmap.recycle()
            }
        } catch (e: Exception) {
            XLog.d("AppHostApi: getAppIcon failed for $packageName: $e")
            null
        }
    }

    // macOS
    override fun appleVpnCapabilities(callback: (Result<AppleVpnCapabilities>) -> Unit) {
        callback(Result.success(AppleVpnCapabilities(false, false)))
    }

    override fun useSystemExtension(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(false))
    }

    override fun queryLaunchAtLogin(callback: (Result<NativeLaunchAtLoginResult>) -> Unit) {
        callback(
            Result.success(
                NativeLaunchAtLoginResult(
                    NativeLaunchAtLoginState.UNAVAILABLE,
                    null,
                )
            )
        )
    }

    override fun setLaunchAtLogin(
        enabled: Boolean,
        callback: (Result<NativeLaunchAtLoginResult>) -> Unit,
    ) {
        callback(
            Result.success(
                NativeLaunchAtLoginResult(
                    NativeLaunchAtLoginState.UNAVAILABLE,
                    null,
                )
            )
        )
    }

    override fun openLaunchAtLoginSettings(callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(false))
    }

    //ios
    override fun setAppIcon(appIcon: String, callback: (Result<Boolean>) -> Unit) {
        callback(Result.success(true))
    }

    override fun getCurrentAppIcon(callback: (Result<String>) -> Unit) {
        callback(Result.success(""))
    }

    private fun queryPermissionNow(): PlatformPermissionResult = VpnController.queryPermission(context)

    private fun commandFailed(permission: PlatformPermissionResult): NativeVpnCommandResult =
        NativeVpnCommandResult(
            state = NativeVpnCommandState.FAILED,
            permission = permission,
            message = VpnController.lastError,
        )

    private fun androidPermissionDenied() = PlatformPermissionResult(
        PlatformPermissionKind.ANDROID_VPN,
        PlatformPermissionState.DENIED,
        null,
    )

    private fun commandSuccess(permission: PlatformPermissionResult, status: VpnStatus) = NativeVpnCommandResult(
        state = NativeVpnCommandState.SUCCESS,
        status = status,
        permission = permission,
    )

    private fun waitingForPermission(permission: PlatformPermissionResult) = NativeVpnCommandResult(
        state = NativeVpnCommandState.WAITING_FOR_PLATFORM_PERMISSION,
        permission = permission,
    )

    private companion object {
        // The per-app list renders icons in a 31dp slot; 96px covers 3x density.
        const val ICON_SIZE_PX = 96
    }
}
