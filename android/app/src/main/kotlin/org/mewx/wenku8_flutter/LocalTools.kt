package org.mewx.wenku8_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.Executors

/** Explicit document/folder/share actions; never touches the Wenku8 bridge/session. */
class LocalTools(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private data class Pending(val result: MethodChannel.Result, val export: String?, val legacy: Boolean = false)
    private var pending: Pending? = null
    private var closed = false
    companion object {
        private const val REQUEST = 8019
        private const val MAX_BYTES = 4 * 1024 * 1024
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getKeepScreenOn" -> result.success(
                activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
            )
            "keepScreenOn" -> {
                if (call.arguments == true) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                if (text.isBlank() || text.length > 10000) {
                    result.error("input", "Invalid share text", null)
                } else try {
                    activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }, "分享图书"))
                    result.success(null)
                } catch (_: Exception) { result.error("share", "Share sheet did not open", null) }
            }
            "exportBackup", "importBackup", "importLegacyData" -> {
                if (pending != null || closed) {
                    result.error("busy", "A document operation is already active", null)
                    return
                }
                val text = if (call.method == "exportBackup") call.argument<String>("text") else null
                val legacy = call.method == "importLegacyData"
                if (call.method == "exportBackup" && (text == null || text.toByteArray(Charsets.UTF_8).size > MAX_BYTES)) {
                    result.error("size", "Backup exceeds the document limit", null)
                    return
                }
                val intent = Intent(if (legacy) Intent.ACTION_OPEN_DOCUMENT_TREE else if (text == null) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT).apply {
                    if (!legacy) {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (text == null) "*/*" else "application/json"
                        if (text == null) putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                        else putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "wenku8-backup.json")
                    }
                }
                pending = Pending(result, text, legacy)
                try {
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, REQUEST)
                } catch (_: Exception) {
                    pending = null
                    result.error("picker", "Document picker could not open", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val operation = pending ?: return true
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            pending = null
            operation.result.success(if (operation.export == null) null else false)
            return true
        }
        io.execute {
            try {
                val response: Any = if (operation.legacy) {
                    readLegacyTree(uri)
                } else if (operation.export != null) {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use { output ->
                        output.write(operation.export.toByteArray(Charsets.UTF_8))
                        output.flush()
                    } ?: throw IllegalStateException("Document is not writable")
                    true
                } else {
                    val bytes = ByteArrayOutputStream()
                    activity.contentResolver.openInputStream(uri)?.use { input ->
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (bytes.size() + count > MAX_BYTES) throw IllegalArgumentException("Document is too large")
                            bytes.write(buffer, 0, count)
                        }
                    } ?: throw IllegalStateException("Document is not readable")
                    Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes.toByteArray())).toString()
                }
                activity.runOnUiThread {
                    if (!closed) {
                        pending = null
                        operation.result.success(response)
                    }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (!closed) {
                        pending = null
                        operation.result.error("document", "Document read or write failed", null)
                    }
                }
            }
        }
        return true
    }

    /** Only documented record/index files from the explicitly selected tree.
     * Never read cert.wk8, account files, images or arbitrary nested folders. */
    private fun readLegacyTree(tree: Uri): Map<String, Any> {
        data class Document(val id: String, val name: String, val directory: Boolean, val modified: Long)
        fun children(id: String): List<Document> {
            val uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            return activity.contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
                val records = ArrayList<Document>()
                while (cursor.moveToNext()) {
                    check(records.size < 10000) { "Folder too large" }
                    records.add(Document(cursor.getString(0), cursor.getString(1),
                        cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR, cursor.getLong(3)))
                }
                records
            } ?: throw IllegalStateException("Folder is not readable")
        }
        val root = children(DocumentsContract.getTreeDocumentId(tree))
        val saves = root.firstOrNull { it.directory && it.name == "saves" }?.let { children(it.id) } ?: root
        val records = saves.filter { !it.directory && it.name in setOf("bookshelf_local.wk8", "read_saves.wk8", "read_saves_v1.wk8", "search_history.wk8") }
        require(records.isNotEmpty()) { "No legacy records" }
        val indices = saves.firstOrNull { it.directory && it.name == "intro" }?.let { children(it.id) }
            ?.filter { !it.directory && Regex("[1-9][0-9]{0,9}-volume\\.xml").matches(it.name) } ?: emptyList()
        val output = LinkedHashMap<String, Any>()
        var total = 0
        var skipped = 0
        for (document in records + indices) {
            val content = activity.contentResolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, document.id))?.use { input ->
                val bytes = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var oversized = false
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > MAX_BYTES || total + bytes.size() + count > 8 * 1024 * 1024) {
                        if (document in records) throw IllegalArgumentException("Records too large")
                        skipped++
                        oversized = true
                        break
                    }
                    bytes.write(buffer, 0, count)
                }
                if (oversized) null else bytes.toByteArray()
            } ?: continue
            try {
                val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(content)).toString()
                total += content.size
                output[document.name] = mapOf("text" to text, "modifiedAt" to document.modified)
            } catch (_: Exception) { skipped++ }
        }
        require(records.any { output.containsKey(it.name) }) { "No readable legacy records" }
        return mapOf("documents" to output, "skippedFiles" to skipped)
    }

    fun close() {
        closed = true
        pending?.result?.error("closed", "Activity closed", null)
        pending = null
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        io.shutdown()
    }
}
