package net.yuandev.onexray.automation

import android.app.Application
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import net.yuandev.onexray.vpn.OneVpnService
import net.yuandev.onexray.vpn.VpnController
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowToast
import org.robolectric.shadows.ShadowVpnService
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 34], application = Application::class, qualifiers = "en-rUS")
class VpnAutomationTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private val store get() = AutomationStore(context)
    private val receiver = VpnAutomationReceiver()

    private fun request(action: String, token: String?) = Intent(action)
        .setComponent(ComponentName(context, VpnAutomationReceiver::class.java))
        .putExtra("token", token)

    private fun savedConfig() {
        VpnController.startFile(context).apply {
            parentFile!!.mkdirs()
            writeText("""{"tun":{"tunDnsIPv4":"8.8.8.8"},"metricsPort":"19400","coreInvokeText":"{\"apiVersion\":3,\"method\":\"runXray\",\"payload\":{\"xrayJson\":\"{}\"}}"}""")
        }
    }

    @Test fun tokenIsStableUntilResetAndReadFreshAcrossInstances() {
        assertEquals(AutomationSettings(), store.read())
        val first = store.setEnabled(true)
        assertTrue(first.token!!.matches(Regex("ox_[A-Za-z0-9_-]{43}")))
        val reader = AutomationStore(context)
        assertTrue(reader.authorized(first.token))
        assertEquals(first, store.setEnabled(true))
        store.setEnabled(false)
        assertFalse(reader.authorized(first.token))
        assertEquals(first, store.setEnabled(true))
        val second = store.resetToken()
        assertNotEquals(first.token, second.token)
        assertFalse(reader.authorized(first.token))
        assertTrue(reader.authorized(second.token))
        assertFalse(reader.authorized(" ${second.token}"))
        assertFalse(reader.authorized(123))
        store.clear()
        assertFalse(reader.authorized(second.token))
        assertEquals(AutomationSettings(), store.read())
    }

    @Test fun unauthorizedCommandsHaveNoLifecycleOrFeedbackSideEffects() {
        val token = store.setEnabled(true).token
        val invalid = listOf(
            request(VpnAutomationReceiver.ACTION_START, null),
            request(VpnAutomationReceiver.ACTION_STOP, "wrong"),
            request("unknown.action", token),
            request(VpnAutomationReceiver.ACTION_START, token).putExtra("token", 42),
        )
        invalid.forEach { receiver.onReceive(context, it) }
        store.setEnabled(false)
        receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_START, token))
        assertNull(shadowOf(context).nextStartedService)
        assertNull(shadowOf(context).nextStartedActivity)
        assertTrue(shadowOf(context).broadcastIntents.isEmpty())
        assertEquals(0, shadowOf(context.getSystemService(NotificationManager::class.java)).size())
        assertEquals(0, ShadowToast.shownToastCount())
        assertFalse(File(context.filesDir, "run/vpn.stop").exists())
    }

    @Test fun validStartReusesSavedRequestAndNeverLaunchesActivity() {
        val token = store.setEnabled(true).token
        savedConfig()
        ShadowVpnService.setPrepareResult(null)
        receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_START, token))
        val intent = shadowOf(context).nextStartedService!!
        assertEquals(ComponentName(context, OneVpnService::class.java), intent.component)
        assertTrue(intent.getBooleanExtra(OneVpnService.EXTRA_REUSE_CONFIGURATION, false))
        assertTrue(intent.getBooleanExtra(OneVpnService.EXTRA_AUTOMATION_START, false))
        assertTrue(intent.getLongExtra(OneVpnService.EXTRA_START_REQUEST_ID, 0L) > 0L)
        assertNull(shadowOf(context).nextStartedActivity)
    }

    @Test fun missingInputsAreReportedBeforeMissingPermission() {
        val token = store.setEnabled(true).token
        ShadowVpnService.setPrepareResult(Intent("needs-permission"))
        receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_START, token))
        assertTrue(VpnController.lastError!!.contains("complete configuration"))
        assertNull(shadowOf(context).nextStartedService)
        assertNull(shadowOf(context).nextStartedActivity)
        assertEquals(0, ShadowToast.shownToastCount())
        assertEquals(1, shadowOf(context.getSystemService(NotificationManager::class.java)).size())
        savedConfig()
        receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_START, token))
        assertTrue(VpnController.lastError!!.contains("allow VPN"))
    }

    @Test fun maintenanceBlocksStartButNotStopAndDoesNotChangeToken() {
        val token = store.setEnabled(true).token
        store.setStartBlocked(true)
        assertThrows(IllegalStateException::class.java) { store.setEnabled(true) }
        assertThrows(IllegalStateException::class.java) { store.resetToken() }
        receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_START, token))
        assertNull(shadowOf(context).nextStartedService)
        ShadowVpnService.setPrepareResult(Intent("needs-permission"))
        repeat(2) { receiver.onReceive(context, request(VpnAutomationReceiver.ACTION_STOP, token)) }
        assertTrue(File(context.filesDir, "run/vpn.stop").isFile)
        assertEquals(2, shadowOf(context).broadcastIntents.count { it.action == OneVpnService.ACTION_STOP_REQUEST })
        assertNull(shadowOf(context).nextStartedActivity)
        store.setStartBlocked(false)
        assertFalse(store.startBlocked)
        assertTrue(store.authorized(token))
    }

    @Test fun settingsBridgePublishesRevocationAndClearWithoutTouchingVpn() {
        val bridge = AutomationApi(context)
        var token: String? = null
        bridge.setEnabled(true) { token = it.getOrThrow().token }
        assertTrue(store.authorized(token))
        bridge.setEnabled(false) { assertFalse(it.getOrThrow().enabled) }
        assertFalse(store.authorized(token))
        bridge.setEnabled(true) { assertEquals(token, it.getOrThrow().token) }
        bridge.resetToken { assertNotEquals(token, it.getOrThrow().token) }
        assertFalse(store.authorized(token))
        bridge.setStartBlocked(true) { it.getOrThrow() }
        bridge.clear { it.getOrThrow() }
        assertEquals(AutomationSettings(), store.read())
        bridge.setStartBlocked(false) { it.getOrThrow() }
        assertNull(shadowOf(context).nextStartedService)
        assertNull(shadowOf(context).nextStartedActivity)
        assertTrue(shadowOf(context).broadcastIntents.isEmpty())
    }

    @Test fun manifestExposesOnlyNewAdapterWithoutWeakeningVpnProtection() {
        val receiverInfo = context.packageManager.getReceiverInfo(ComponentName(context, VpnAutomationReceiver::class.java), 0)
        assertTrue(receiverInfo.exported)
        assertEquals("${context.packageName}:native", receiverInfo.processName)
        val vpnInfo = context.packageManager.getServiceInfo(ComponentName(context, OneVpnService::class.java), 0)
        assertEquals("android.permission.BIND_VPN_SERVICE", vpnInfo.permission)
    }
}
