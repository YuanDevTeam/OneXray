package net.yuandev.onexray.vpn

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.os.Binder
import android.os.Parcel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import net.yuandev.onexray.pigeon.VpnStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class VpnStatusConnectionTest {
    @Test fun delayedPreviousStopBroadcastDoesNotFailTheNextStart() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val context = StatusContext(RuntimeEnvironment.getApplication())
        val notifications = mutableListOf<VpnStatus>()
        val connection = VpnStatusConnection(context) { notifications.add(it) }
        try {
            // Bind the existing session through the production changed/bind path.
            val previousStartId = context.startRequestId
            connection.changed(true, null, previousStartId)
            assertEquals(VpnStatus.CONNECTED, connection.read())
            val stopSent = CompletableDeferred<Unit>()
            val stopped = async {
                connection.command(VpnStatus.DISCONNECTED) {
                    stopSent.complete(Unit)
                    true
                }
            }
            stopSent.await()

            // The Binder reports service loss before Android delivers its final
            // status broadcast. This already completes the previous stop.
            context.disconnectCurrentService()
            assertEquals(VpnStatus.DISCONNECTED, stopped.await())

            val startSent = CompletableDeferred<Unit>()
            val starting = async {
                // Capture failure so the assertion below, rather than child
                // cancellation, reports the precise regression.
                runCatching {
                    connection.command(VpnStatus.CONNECTED) { startRequestId ->
                        context.startRequestId = startRequestId
                        context.status = VpnStatus.CONNECTING
                        startSent.complete(Unit)
                        true
                    }
                }
            }
            startSent.await()
            assertEquals(VpnStatus.CONNECTING, connection.read())
            notifications.clear()

            // Late false from the already-stopped session must not reject the
            // current start and trigger the App's cleanup stop of the new TUN.
            connection.changed(false, null, previousStartId)
            runCurrent()
            assertFalse(
                "The next start must keep waiting for its own CONNECTED event; " +
                    "the previous stop broadcast must not fail it",
                starting.isCompleted,
            )
            assertFalse(notifications.contains(VpnStatus.DISCONNECTED))

            context.status = VpnStatus.CONNECTED
            connection.changed(true, null, context.startRequestId)
            assertEquals(VpnStatus.CONNECTED, starting.await().getOrThrow())
            assertEquals(VpnStatus.CONNECTED, connection.read())
        } finally {
            connection.close()
            Dispatchers.resetMain()
        }
    }

    @Test fun staleSuccessAndErrorDoNotCompleteOrFailThePendingStart() = withStatus { context, connection, notifications ->
        val previousId = context.startRequestId
        connection.changed(true, null, previousId)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, null, previousId)
        val starting = startPending(context, connection)
        VpnController.lastError = null
        notifications.clear()
        connection.changed(true, null, previousId)
        connection.changed(false, "previous Core failed", previousId)
        runCurrent()
        assertFalse(starting.isCompleted)
        assertEquals(emptyList<VpnStatus>(), notifications)
        assertEquals(null, VpnController.lastError)
        context.status = VpnStatus.CONNECTED
        connection.changed(true, null, context.startRequestId)
        assertEquals(VpnStatus.CONNECTED, starting.await().getOrThrow())
    }

    @Test fun currentStartErrorFailsImmediatelyAndPreservesItsMessage() = withStatus { context, connection, notifications ->
        val starting = startPending(context, connection)
        connection.changed(false, null, context.startRequestId, starting = true)
        assertEquals(VpnStatus.CONNECTING, notifications.last())
        assertFalse(starting.isCompleted)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, "current Core failed", context.startRequestId)
        assertEquals("current Core failed", starting.await().exceptionOrNull()?.message)
        assertEquals("current Core failed", VpnController.lastError)
        assertEquals(VpnStatus.DISCONNECTED, notifications.last())
    }

    @Test fun currentStartCancelledWithoutAnErrorStillFailsImmediately() = withStatus { context, connection, _ ->
        val starting = startPending(context, connection)
        connection.changed(false, null, context.startRequestId, starting = true)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, null, context.startRequestId)
        assertEquals("VPN service stopped before connecting", starting.await().exceptionOrNull()?.message)
    }

    @Test fun currentServiceDeathDuringStartupFailsWithoutWaitingForTimeout() = withStatus { context, connection, notifications ->
        val starting = startPending(context, connection)
        // The service's starting event establishes the real death subscription.
        connection.changed(false, null, context.startRequestId, starting = true)
        assertFalse(starting.isCompleted)
        context.disconnectCurrentService()
        assertEquals("VPN service process exited", starting.await().exceptionOrNull()?.message)
        assertEquals(VpnStatus.DISCONNECTED, notifications.last())
    }

    @Test fun stopStillCompletesWhenTheCurrentBinderDisconnects() = withStatus { context, connection, _ ->
        connection.changed(true, null, context.startRequestId)
        val stopSent = CompletableDeferred<Unit>()
        val stopped = async {
            connection.command(VpnStatus.DISCONNECTED) {
                stopSent.complete(Unit)
                true
            }
        }
        stopSent.await()
        context.disconnectCurrentService()
        assertEquals(VpnStatus.DISCONNECTED, stopped.await())
    }

    @Test fun callbacksFromAnUnboundPreviousServiceDoNotFailTheNewStart() = withStatus { context, connection, notifications ->
        connection.changed(true, null, context.startRequestId)
        val previousConnection = requireNotNull(context.currentConnection)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, null, context.startRequestId)
        val starting = startPending(context, connection)
        connection.changed(false, null, context.startRequestId, starting = true)
        notifications.clear()
        previousConnection.onServiceDisconnected(context.component)
        previousConnection.onBindingDied(context.component)
        previousConnection.onNullBinding(context.component)
        runCurrent()
        assertFalse(starting.isCompleted)
        assertEquals(emptyList<VpnStatus>(), notifications)
        context.status = VpnStatus.CONNECTED
        connection.changed(true, null, context.startRequestId)
        assertEquals(VpnStatus.CONNECTED, starting.await().getOrThrow())
    }

    @Test fun aRepeatedStartCannotUseTheExistingSessionAsNewStartConfirmation() = withStatus { context, connection, notifications ->
        val existingId = context.startRequestId
        connection.changed(true, null, existingId)
        val sent = CompletableDeferred<Unit>()
        val starting = async {
            runCatching {
                connection.command(VpnStatus.CONNECTED) { candidateId ->
                    assertFalse(existingId == candidateId)
                    // The service ignores start while it already owns resources;
                    // its actual Binder identity therefore stays existingId.
                    sent.complete(Unit)
                    true
                }
            }
        }
        sent.await()
        notifications.clear()
        connection.changed(true, null, existingId)
        runCurrent()
        assertFalse(starting.isCompleted)
        assertEquals(emptyList<VpnStatus>(), notifications)
        connection.close()
        assertFalse(starting.await().isSuccess)
    }

    @Test fun anExternalLaunchFailureRemainsVisibleWithoutAPendingUiCommand() = withStatus { context, connection, notifications ->
        connection.changed(true, null, context.startRequestId)
        context.startRequestId = VpnController.newStartRequestId(after = context.startRequestId)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, "saved configuration failed", context.startRequestId)
        assertEquals("saved configuration failed", VpnController.lastError)
        assertEquals(VpnStatus.DISCONNECTED, notifications.last())
    }

    @Test fun cancelledOlderBindAwaitDoesNotUnbindTheNewerLaunch() = withStatus { context, connection, notifications ->
        context.connectImmediately = false
        context.status = VpnStatus.CONNECTING
        val previousId = context.startRequestId
        val previousEvent = async {
            runCatching { connection.changed(false, null, previousId, starting = true) }
        }
        runCurrent()
        val previousBinding = requireNotNull(context.currentConnection)

        // The second startup cancels the old bind await, then installs its own
        // ServiceConnection before the old await's catch resumes.
        context.startRequestId = VpnController.newStartRequestId(after = previousId)
        val currentId = context.startRequestId
        val currentEvent = async {
            runCatching { connection.changed(false, null, currentId, starting = true) }
        }
        runCurrent()
        assertFalse(
            "The cancelled old bind must not cancel the newer service connection",
            currentEvent.isCompleted,
        )
        val currentBinding = requireNotNull(context.currentConnection)
        assertFalse(previousBinding === currentBinding)

        // Android can deliver the old connection callback late as well. It must
        // be ignored without stealing the newer connection's completion.
        context.connectService(previousBinding)
        runCurrent()
        assertFalse(currentEvent.isCompleted)
        context.connectService(currentBinding)
        currentEvent.await().getOrThrow()
        previousEvent.await().getOrThrow()
        assertEquals(VpnStatus.CONNECTING, connection.read())

        context.status = VpnStatus.CONNECTED
        connection.changed(true, null, currentId)
        assertEquals(VpnStatus.CONNECTED, connection.read())
        assertEquals(VpnStatus.CONNECTED, notifications.last())

        // The current binding remains subscribed after successful startup.
        context.disconnectCurrentService()
        assertEquals(VpnStatus.DISCONNECTED, notifications.last())
        assertEquals("VPN service process exited", VpnController.lastError)
    }

    @Test fun externalSavedLaunchIsObservedAndRejectsEarlierSessionEvents() = withStatus { context, connection, notifications ->
        val previousId = context.startRequestId
        connection.changed(true, null, previousId)
        context.status = VpnStatus.DISCONNECTED
        connection.changed(false, null, previousId)
        // Saved/widget dispatch has no pending UI command, but uses the same ID
        // generator as VpnController.startVpn's default argument.
        context.startRequestId = VpnController.newStartRequestId(after = previousId)
        context.status = VpnStatus.CONNECTING
        connection.changed(false, null, context.startRequestId, starting = true)
        assertEquals(VpnStatus.CONNECTING, connection.read())
        context.status = VpnStatus.CONNECTED
        connection.changed(true, null, context.startRequestId)
        assertEquals(VpnStatus.CONNECTED, connection.read())
        notifications.clear()
        connection.changed(false, "old saved launch failed", previousId)
        connection.changed(true, null, previousId)
        connection.changed(false, null, previousId, starting = true)
        assertEquals(emptyList<VpnStatus>(), notifications)
        assertEquals(null, VpnController.lastError)
        assertEquals(VpnStatus.CONNECTED, connection.read())
    }

    private fun withStatus(
        block: suspend TestScope.(StatusContext, VpnStatusConnection, MutableList<VpnStatus>) -> Unit,
    ) = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val context = StatusContext(RuntimeEnvironment.getApplication())
        val notifications = mutableListOf<VpnStatus>()
        val connection = VpnStatusConnection(context) { notifications.add(it) }
        VpnController.lastError = null
        try {
            block(context, connection, notifications)
        } finally {
            connection.close()
            Dispatchers.resetMain()
            VpnController.lastError = null
        }
    }

    private suspend fun CoroutineScope.startPending(
        context: StatusContext,
        connection: VpnStatusConnection,
    ): Deferred<Result<VpnStatus>> {
        val sent = CompletableDeferred<Unit>()
        val starting = async {
            runCatching {
                connection.command(VpnStatus.CONNECTED) { startRequestId ->
                    context.startRequestId = startRequestId
                    context.status = VpnStatus.CONNECTING
                    sent.complete(Unit)
                    true
                }
            }
        }
        sent.await()
        return starting
    }

    /** Real Binder transactions; only Android's service delivery is controlled. */
    private class StatusContext(base: Context) : ContextWrapper(base) {
        var status = VpnStatus.CONNECTED
        var startRequestId = 100L
        var connectImmediately = true
        var currentConnection: ServiceConnection? = null
            private set
        val component = ComponentName(base, OneVpnService::class.java)

        override fun bindService(intent: Intent, connection: ServiceConnection, flags: Int): Boolean {
            assertEquals(VpnStatusConnection.ACTION_BIND, intent.action)
            assertEquals(0, flags)
            currentConnection = connection
            if (connectImmediately) connectService(connection)
            return true
        }

        fun connectService(connection: ServiceConnection) {
            connection.onServiceConnected(component, object : Binder() {
                override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
                    assertEquals(VpnStatusConnection.READ_STATUS, code)
                    data.enforceInterface(VpnStatusConnection.DESCRIPTOR)
                    requireNotNull(reply).writeNoException()
                    reply.writeInt(status.ordinal)
                    reply.writeLong(startRequestId)
                    return true
                }
            })
        }

        override fun unbindService(connection: ServiceConnection) {
            if (currentConnection === connection) currentConnection = null
        }

        fun disconnectCurrentService() {
            status = VpnStatus.DISCONNECTED
            requireNotNull(currentConnection).onServiceDisconnected(component)
        }
    }
}
