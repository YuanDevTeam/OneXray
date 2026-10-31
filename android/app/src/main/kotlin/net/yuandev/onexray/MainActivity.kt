package net.yuandev.onexray

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.elvishew.xlog.XLog
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import net.yuandev.onexray.pigeon.AppFlutterApi
import net.yuandev.onexray.pigeon.AppHostApi
import net.yuandev.onexray.pigeon.BridgeHostApi
import net.yuandev.onexray.pigeon.BackupHostApi
import net.yuandev.onexray.pigeon.BackupApi
import net.yuandev.onexray.pigeon.FileExportHostApi
import net.yuandev.onexray.pigeon.FileExportApi
import net.yuandev.onexray.vpn.OneVpnService
import net.yuandev.onexray.automation.AutomationApi
import net.yuandev.onexray.pigeon.AndroidAutomationHostApi

class MainActivity : FlutterFragmentActivity() {

    private val hostApi = AppHostApi(this)
    private val backupApi = BackupApi(this)
    private val fileExportApi = FileExportApi(this)
    private var vpnStatusReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        registerVpnStatusReceiver()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val flutterApi = AppFlutterApi(flutterEngine.dartExecutor)
        BridgeHostApi.setUp(flutterEngine.dartExecutor, hostApi)
        BackupHostApi.setUp(flutterEngine.dartExecutor, backupApi)
        FileExportHostApi.setUp(flutterEngine.dartExecutor, fileExportApi)
        AndroidAutomationHostApi.setUp(flutterEngine.dartExecutor, AutomationApi(this))

        hostApi.onInit(flutterApi)
    }

    // 接收器在 onCreate 中注册、onDestroy 中注销，避免在 onPause（系统弹窗导致 Activity 暂停）
    // 期间错过 OneVpnService 发出的 VPN 状态广播，否则 Dart 侧会因收不到 CONNECTED 而超时断开。
    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerVpnStatusReceiver() {
        if (vpnStatusReceiver != null) {
            return
        }
        vpnStatusReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == OneVpnService.ACTION_VPN_STATUS) {
                    val running = intent.getBooleanExtra(OneVpnService.EXTRA_RUNNING, false)
                    val starting = intent.getBooleanExtra(OneVpnService.EXTRA_STARTING, false)
                    val startRequestId = intent.getLongExtra(OneVpnService.EXTRA_START_REQUEST_ID, 0L)
                    XLog.d("MainActivity: received VPN status changed: $running starting=$starting request=$startRequestId")
                    // 将状态交给现有 hostApi（可触发 Flutter 通知或内部状态更新）
                    hostApi.onVpnStatusChanged(
                        running,
                        intent.getStringExtra(OneVpnService.EXTRA_ERROR),
                        startRequestId,
                        starting,
                    )
                }
            }
        }
        val filter = IntentFilter(OneVpnService.ACTION_VPN_STATUS).apply {
            priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        }
        vpnStatusReceiver?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(it, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(it, filter)
            }
        }
    }

    override fun onDestroy() {
        backupApi.dispose()
        fileExportApi.dispose()
        hostApi.onDestroy()
        // 防御式注销
        vpnStatusReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        vpnStatusReceiver = null
        super.onDestroy()
    }
}
