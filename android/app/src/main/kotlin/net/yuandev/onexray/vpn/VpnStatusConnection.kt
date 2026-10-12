package net.yuandev.onexray.vpn

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.Parcel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import net.yuandev.onexray.pigeon.VpnStatus

/** Reads the service itself and observes :native death. No last-known VPN state. */
class VpnStatusConnection(
    private val context: Context,
    private val notify: (VpnStatus) -> Unit,
) {
    companion object {
        const val ACTION_BIND = "net.yuandev.onexray.VPN_STATUS_BIND"
        const val DESCRIPTOR = "net.yuandev.onexray.VpnStatus"
        const val READ_STATUS = IBinder.FIRST_CALL_TRANSACTION
    }

    private var binding: ServiceConnection? = null
    private var service: CompletableDeferred<IBinder>? = null
    private var pending: CompletableDeferred<Unit>? = null
    private var target: VpnStatus? = null
    private var eventGeneration = 0
    // Kept after stop/death so their delayed broadcasts cannot describe a new launch.
    private var latestStartRequestId = 0L

    suspend fun read(): VpnStatus = withContext(Dispatchers.Main) {
        target?.let {
            return@withContext if (it == VpnStatus.CONNECTED) VpnStatus.CONNECTING else VpnStatus.DISCONNECTING
        }
        if (service == null && !VpnController.readVpnRunning(context)) {
            return@withContext VpnStatus.DISCONNECTED
        }
        val binder = bind()
        val (status, startRequestId) = withContext(Dispatchers.IO) {
            val request = Parcel.obtain()
            val reply = Parcel.obtain()
            try {
                request.writeInterfaceToken(DESCRIPTOR)
                check(binder.transact(READ_STATUS, request, reply, 0)) { "VPN status query was rejected" }
                reply.readException()
                VpnStatus.entries[reply.readInt()] to reply.readLong()
            } finally {
                request.recycle()
                reply.recycle()
            }
        }
        latestStartRequestId = maxOf(latestStartRequestId, startRequestId)
        status
    }

    suspend fun changed(
        running: Boolean,
        error: String?,
        startRequestId: Long,
        starting: Boolean = false,
    ) = withContext(Dispatchers.Main) {
        if (startRequestId < latestStartRequestId ||
            (target == VpnStatus.CONNECTED && startRequestId != latestStartRequestId)) {
            return@withContext
        }
        // Saved/widget launches use the same monotonic IDs, without a pending UI
        // command. Bind their service anew instead of retaining the old session.
        if (startRequestId > latestStartRequestId) {
            unbind()
            latestStartRequestId = startRequestId
        }
        val generation = ++eventGeneration
        if (running || starting) {
            // Observe process death during startup as well as after success.
            try { bind() } catch (failure: Exception) {
                if (generation != eventGeneration) return@withContext
                pending?.completeExceptionally(failure)
                throw failure
            }
            if (generation != eventGeneration) return@withContext
        } else {
            unbind()
        }
        if (running || error != null) VpnController.lastError = error
        val status = when {
            running -> VpnStatus.CONNECTED
            starting -> VpnStatus.CONNECTING
            else -> VpnStatus.DISCONNECTED
        }
        if (status == target) pending?.complete(Unit)
        else if (!running && !starting) pending?.completeExceptionally(
            IllegalStateException(error ?: "VPN service stopped before connecting")
        )
        notify(status)
    }

    suspend fun command(wanted: VpnStatus, action: (Long) -> Boolean): VpnStatus = withContext(Dispatchers.Main) {
        check(pending == null) { "A VPN command is already running" }
        val current = read()
        if (wanted == VpnStatus.DISCONNECTED && current == VpnStatus.DISCONNECTED) {
            check(action(latestStartRequestId)) { VpnController.lastError ?: "Could not stop VPN" }
            return@withContext VpnStatus.DISCONNECTED
        }
        val completion = CompletableDeferred<Unit>()
        pending = completion
        target = wanted
        if (wanted == VpnStatus.CONNECTED) {
            // Set the expected identity before dispatching start: native failure
            // or success can arrive immediately after the service receives it.
            latestStartRequestId = VpnController.newStartRequestId(after = latestStartRequestId)
        }
        try {
            notify(if (wanted == VpnStatus.CONNECTED) VpnStatus.CONNECTING else VpnStatus.DISCONNECTING)
            check(action(latestStartRequestId)) { VpnController.lastError ?: "VPN command failed" }
            withTimeout(if (wanted == VpnStatus.CONNECTED) 30_000L else 15_000L) { completion.await() }
            wanted
        } finally {
            pending = null
            target = null
        }
    }

    private suspend fun bind(): IBinder {
        service?.let { return withTimeout(3_000) { it.await() } }
        val connected = CompletableDeferred<IBinder>()
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                if (binding === this) connected.complete(binder)
            }
            override fun onServiceDisconnected(name: ComponentName) {
                if (binding !== this) return
                eventGeneration++
                val error = IllegalStateException("VPN service process exited")
                VpnController.lastError = error.message
                connected.completeExceptionally(error)
                if (target == VpnStatus.DISCONNECTED) pending?.complete(Unit)
                else pending?.completeExceptionally(error)
                unbind()
                notify(VpnStatus.DISCONNECTED)
            }
            override fun onBindingDied(name: ComponentName) = onServiceDisconnected(name)
            override fun onNullBinding(name: ComponentName) = onServiceDisconnected(name)
        }
        binding = connection
        service = connected
        try {
            // Do not create a VPN service merely to query its state.
            check(context.bindService(Intent(context, OneVpnService::class.java).setAction(ACTION_BIND), connection, 0)) {
                "Could not bind the running VPN service"
            }
            return withTimeout(3_000) { connected.await() }
        } catch (error: Exception) {
            // This await can resume after another event replaced its binding.
            if (binding === connection) unbind()
            throw error
        }
    }

    private fun unbind() {
        val connection = binding
        binding = null
        service?.takeUnless { it.isCompleted }?.cancel()
        service = null
        if (connection != null) {
            try { context.unbindService(connection) } catch (_: IllegalArgumentException) { }
        }
    }

    fun close() {
        pending?.cancel()
        unbind()
    }
}
