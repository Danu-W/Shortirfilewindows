package id.storyties.shortir_file

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val channelName = "storyties/saf"
    private var pendingResult: MethodChannel.Result? = null
    private var mediaPermissionResult: MethodChannel.Result? = null
    private val REQ_PICK_DEST_FOLDER = 4101
    private val REQ_MEDIA_PERMS = 4102
    private companion object {
        private const val TAG = "ShortirSAF"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMediaPermissions" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val needed = listOf(
                                Manifest.permission.READ_MEDIA_IMAGES,
                                Manifest.permission.READ_MEDIA_VIDEO,
                                Manifest.permission.READ_MEDIA_AUDIO,
                            ).filter {
                                checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                            }
                            if (needed.isEmpty()) {
                                result.success(true)
                            } else {
                                mediaPermissionResult = result
                                requestPermissions(needed.toTypedArray(), REQ_MEDIA_PERMS)
                            }
                        } else {
                            if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                result.success(true)
                            } else {
                                mediaPermissionResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                                    REQ_MEDIA_PERMS,
                                )
                            }
                        }
                    }
                    "pickFolder", "pickDestinationFolder" -> {
                        if (pendingResult != null) {
                            result.error("busy", "Operation in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                            REQ_PICK_DEST_FOLDER,
                        )
                    }
                    "listFolder" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing uri", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(listFolder(uri))
                        } catch (e: SecurityException) {
                            result.error(
                                "denied",
                                "Folder dilindungi sistem",
                                e.message,
                            )
                        }
                    }
                    "treeInfo" -> {
                        val uri = call.argument<String>("uri")
                        if (uri == null) {
                            result.error("bad_args", "Missing uri", null)
                            return@setMethodCallHandler
                        }
                        result.success(treeInfo(uri))
                    }
                    "readBytes" -> {
                        val uri = call.argument<String>("uri")
                        val maxBytes = call.argument<Int>("maxBytes") ?: 10 * 1024 * 1024
                        if (uri == null) {
                            result.error("bad_args", "Missing uri", null)
                            return@setMethodCallHandler
                        }
                        result.success(readBytes(uri, maxBytes))
                    }
                    "readThumbnail" -> {
                        val uri = call.argument<String>("uri")
                        val maxDim = call.argument<Int>("maxDim") ?: 384
                        if (uri == null) {
                            result.error("bad_args", "Missing uri", null)
                            return@setMethodCallHandler
                        }
                        result.success(readThumbnail(uri, maxDim))
                    }
                    "createSubfolder" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val name = call.argument<String>("name")
                        if (treeUri == null || name == null) {
                            result.error("bad_args", "Missing treeUri or name", null)
                            return@setMethodCallHandler
                        }
                        result.success(createSubfolder(treeUri, name))
                    }
                    "transfer" -> {
                        val srcUri = call.argument<String>("srcUri")
                        val destTreeUri = call.argument<String>("destTreeUri")
                        val fileName = call.argument<String>("fileName")
                        val mime = call.argument<String>("mime")
                        val keepSource = call.argument<Boolean>("keepSource") ?: true
                        if (srcUri == null || destTreeUri == null || fileName == null) {
                            result.error("bad_args", "Missing transfer arguments", null)
                            return@setMethodCallHandler
                        }
                        result.success(transfer(srcUri, destTreeUri, fileName, mime, keepSource))
                    }
                    "notifyUpdateAvailable" -> {
                        val title = call.argument<String>("title") ?: "Update tersedia"
                        val body = call.argument<String>("body") ?: ""
                        notifyUpdateAvailable(title, body)
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad_args", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val src = File(path)
                            val destDir = File(cacheDir, "apks")
                            destDir.mkdirs()
                            val dest = File(destDir, "shortir-file.apk")
                            src.copyTo(dest, overwrite = true)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                dest,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_MEDIA_PERMS) {
            val res = mediaPermissionResult
            mediaPermissionResult = null
            val allGranted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            res?.success(allGranted)
        }
    }

    private fun notifyUpdateAvailable(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4103)
            return
        }
        val channelId = "shortir_updates"
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Update Shortir File",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
            manager.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify(1001, notification)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PICK_DEST_FOLDER) {
            val res = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                Log.i(TAG, "picked tree uri=$uri")
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: Exception) {
                }
                res?.success(uri.toString())
            } else {
                res?.success(null)
            }
        }
    }

    private fun createSubfolder(treeUri: String, name: String): String? {
        return try {
            val tree = Uri.parse(treeUri)
            DocumentsContract.createDocument(
                contentResolver,
                tree,
                DocumentsContract.Document.MIME_TYPE_DIR,
                name,
            )?.toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun readThumbnail(uriStr: String, maxDim: Int): ByteArray? {
        return try {
            val uri = Uri.parse(uriStr)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { ins ->
                BitmapFactory.decodeStream(ins, null, bounds)
            }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxDim ||
                bounds.outHeight / (sample * 2) >= maxDim
            ) {
                sample *= 2
            }
            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
            val bmp = contentResolver.openInputStream(uri)?.use { ins ->
                BitmapFactory.decodeStream(ins, null, decodeOpts)
            } ?: return null
            val out = java.io.ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
            bmp.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            Log.w(TAG, "readThumbnail failed: $e")
            null
        }
    }

    private fun readBytes(uriStr: String, maxBytes: Int): ByteArray? {
        return try {
            val input = contentResolver.openInputStream(Uri.parse(uriStr))
            if (input == null) {
                Log.w(TAG, "readBytes null stream uri=$uriStr")
                return null
            }
            input.use { ins ->
                val buf = ins.readNBytes(maxBytes + 1)
                Log.i(TAG, "readBytes uri=$uriStr bytes=${buf.size}")
                if (buf.size > maxBytes) null else buf
            }
        } catch (e: Exception) {
            Log.e(TAG, "readBytes failed uri=$uriStr", e)
            null
        }
    }

    private fun treeInfo(treeUri: String): Map<String, Any?> {
        return try {
            val tree = Uri.parse(treeUri)
            val docId = DocumentsContract.getTreeDocumentId(tree)
            var display = ""
            try {
                val docUri = DocumentsContract.buildDocumentUriUsingTree(tree, docId)
                contentResolver.query(
                    docUri,
                    arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        display = cursor.getString(0) ?: ""
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "treeInfo display query failed: $e")
            }
            Log.i(TAG, "treeInfo docId='$docId' display='$display' uri=$treeUri")
            mapOf("docId" to docId, "displayName" to display)
        } catch (e: Exception) {
            Log.e(TAG, "treeInfo failed: $e")
            mapOf("docId" to "", "displayName" to "")
        }
    }

    private fun listFolder(treeUri: String): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
        val tree = Uri.parse(treeUri)
        val treeDocId = DocumentsContract.getTreeDocumentId(tree)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, treeDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val childDocId = cursor.getString(0) ?: continue
                if (childDocId == treeDocId) continue
                if (childDocId.endsWith("/")) continue
                var name = cursor.getString(1)
                val mime = cursor.getString(2) ?: ""
                val size = cursor.getLong(3)
                val isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR
                if (name.isNullOrBlank()) {
                    val decoded = try {
                        java.net.URLDecoder.decode(childDocId, "UTF-8")
                    } catch (_: Exception) {
                        childDocId
                    }
                    val colon = decoded.indexOf(':')
                    val inner = if (colon >= 0) decoded.substring(colon + 1) else decoded
                    val parts = inner.split('/').filter { it.isNotBlank() }
                    name = parts.lastOrNull() ?: decoded
                }
                val childUri = DocumentsContract.buildDocumentUriUsingTree(tree, childDocId).toString()
                items.add(
                    mapOf(
                        "name" to name,
                        "uri" to childUri,
                        "isDirectory" to isDirectory,
                        "size" to size,
                    ),
                )
                if (items.size >= 5000) break
            }
        }
        Log.i(TAG, "listFolder tree=$treeDocId children=$childrenUri count=${items.size} first=${items.take(3)}")
        return items
    }

    private fun transfer(
        srcUri: String,
        destTreeUri: String,
        fileName: String,
        mime: String?,
        keepSource: Boolean,
    ): String? {
        val tree = Uri.parse(destTreeUri)
        val docId = DocumentsContract.getTreeDocumentId(tree)
        val existing = HashSet<String>()
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    cursor.getString(0)?.let { existing.add(it) }
                }
            }
        } catch (_: Exception) {
        }

        var targetName = fileName
        if (existing.contains(fileName)) {
            val dot = fileName.lastIndexOf('.')
            val base = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var counter = 1
            while (existing.contains(targetName) && counter < 1000) {
                targetName = "$base ($counter)$ext"
                counter++
            }
        }

        val mimeType = mime?.takeIf { it.isNotEmpty() } ?: "application/octet-stream"
        val dest = try {
            DocumentsContract.createDocument(
                contentResolver,
                tree,
                mimeType,
                targetName,
            ) ?: return null
        } catch (_: Exception) {
            return null
        }

        try {
            val input: InputStream = if (srcUri.startsWith("content://")) {
                contentResolver.openInputStream(Uri.parse(srcUri)) ?: return null
            } else {
                File(srcUri).inputStream()
            }
            input.use { ins ->
                val out = contentResolver.openOutputStream(dest) ?: return null
                out.use { outs -> ins.copyTo(outs) }
            }
        } catch (_: Exception) {
            try {
                contentResolver.delete(dest, null, null)
            } catch (_: Exception) {
            }
            return null
        }

        if (!keepSource) {
            try {
                if (srcUri.startsWith("content://")) {
                    contentResolver.delete(Uri.parse(srcUri), null, null)
                } else {
                    File(srcUri).delete()
                }
            } catch (_: Exception) {
            }
        }
        return dest.toString()
    }
}
