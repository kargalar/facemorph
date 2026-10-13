package app.facemorph

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "app.facemorph/photo-folder"
        private const val FILE_EXPORT_CHANNEL = "app.facemorph/file-export"
        private const val REQUEST_CODE = 4201
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickPhotoFolder" -> pickPhotoFolder(result)
                    "materializePhoto" -> materializePhoto(call, result)
                    "saveToDownloads" -> saveToDownloads(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_EXPORT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> saveToDownloads(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickPhotoFolder(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("already_active", "A folder picker is already active.", null)
            return
        }
        pendingResult = result
        try {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                },
                REQUEST_CODE,
            )
        } catch (error: Exception) {
            pendingResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun materializePhoto(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val uri = arguments?.get("uri") as? String
        val name = arguments?.get("name") as? String
        if (uri == null || name == null) {
            result.error("invalid_photo", "Photo URI and name are required.", null)
            return
        }
        Thread {
            val path = copyPhotoFile(Uri.parse(uri), name)
            runOnUiThread { result.success(path) }
        }.start()
    }

    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val sourcePath = arguments?.get("sourcePath") as? String
        val fileName = arguments?.get("fileName") as? String
        if (sourcePath == null || fileName == null) {
            result.error("invalid_file", "Source path and file name are required.", null)
            return
        }

        Thread {
            try {
                val source = File(sourcePath)
                if (!source.isFile) throw IllegalStateException("Video file not found.")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                        put(MediaStore.Downloads.MIME_TYPE, "video/mp4")
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        values,
                    ) ?: throw IllegalStateException("Could not create Downloads file.")
                    try {
                        contentResolver.openOutputStream(uri)?.use { output ->
                            source.inputStream().use { input -> input.copyTo(output) }
                        } ?: throw IllegalStateException("Could not open Downloads file.")
                        values.clear()
                        values.put(MediaStore.Downloads.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                } else {
                    val downloads = Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS,
                    )
                    if (!downloads.exists() && !downloads.mkdirs()) {
                        throw IllegalStateException("Could not create Downloads folder.")
                    }
                    source.copyTo(File(downloads, fileName), overwrite = true)
                }
                runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("save_failed", error.message, null)
                }
            }
        }.start()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingResult
        pendingResult = null
        val uri = data?.data
        if (result == null || resultCode != Activity.RESULT_OK || uri == null) {
            result?.success(null)
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // The temporary grant is enough for this import.
        }

        Thread {
            try {
                val files = listPhotoFiles(uri)
                runOnUiThread { result.success(files) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("folder_read_failed", error.message, null)
                }
            }
        }.start()
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun listPhotoFiles(treeUri: Uri): List<Map<String, String>> {
        val files = mutableListOf<Map<String, String>>()
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        collectPhotoFiles(treeUri, rootDocumentId, files)
        return files
    }

    private fun collectPhotoFiles(
        treeUri: Uri,
        directoryDocumentId: String,
        files: MutableList<Map<String, String>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            directoryDocumentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex) ?: continue
                val mimeType = cursor.getString(mimeIndex)
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (!name.startsWith(".")) {
                        collectPhotoFiles(treeUri, documentId, files)
                    }
                    continue
                }
                if (!isSupportedImage(name)) continue

                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    documentId,
                )
                files.add(mapOf("uri" to documentUri.toString(), "name" to name))
            }
        }
    }

    private fun copyPhotoFile(uri: Uri, name: String): String? {
        val target = File(
            cacheDir,
            "facemorph_import_${System.nanoTime()}_${safeName(name)}",
        )
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            target.path
        } catch (_: Exception) {
            if (target.exists()) target.delete()
            null
        }
    }

    private fun isSupportedImage(name: String): Boolean {
        val lowerName = name.lowercase()
        return lowerName.endsWith(".jpg") ||
            lowerName.endsWith(".jpeg") ||
            lowerName.endsWith(".png")
    }

    private fun safeName(name: String): String =
        name.replace(Regex("[^a-zA-Z0-9._-]"), "_")
}
