package net.yuandev.onexray.pigeon

import android.app.Activity
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Exports an existing file without sending its contents through Pigeon. */
class FileExportApi(private val activity: FragmentActivity) : FileExportHostApi {
    private data class ExportRequest(val path: String, val callback: (Result<Boolean>) -> Unit)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var request: ExportRequest? = null
    private var copying = false
    private var disposed = false
    private val picker = activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val current = request ?: return@registerForActivityResult
        if (result.resultCode != Activity.RESULT_OK) {
            finish(Result.success(false))
            return@registerForActivityResult
        }
        val uri = result.data?.data
        if (uri == null) {
            finish(Result.failure(IllegalStateException("No export document was selected")))
            return@registerForActivityResult
        }
        copying = true
        scope.launch {
            val outcome = withContext(Dispatchers.IO) {
                runCatching {
                    File(current.path).inputStream().use { input ->
                        val output = activity.contentResolver.openOutputStream(uri, "wt")
                            ?: error("The export document cannot be opened for writing")
                        output.use { input.copyTo(it) }
                    }
                    true
                }
            }
            finish(outcome)
        }
    }

    override fun saveFile(path: String, name: String, callback: (Result<Boolean>) -> Unit) {
        if (disposed || request != null) {
            callback(Result.failure(IllegalStateException("File export is unavailable")))
            return
        }
        request = ExportRequest(path, callback)
        try {
            picker.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "text/plain"
                putExtra(Intent.EXTRA_TITLE, name)
            })
        } catch (error: Exception) {
            finish(Result.failure(error))
        }
    }

    private fun finish(result: Result<Boolean>) {
        val callback = request?.callback
        request = null
        copying = false
        callback?.invoke(result)
        if (disposed) scope.cancel()
    }

    fun dispose() {
        disposed = true
        // The Dart caller owns the temporary file. Complete only after an
        // active copy has closed its stream, so cleanup cannot race the copy.
        if (!copying) {
            finish(Result.failure(IllegalStateException("Activity was closed")))
        }
    }
}
