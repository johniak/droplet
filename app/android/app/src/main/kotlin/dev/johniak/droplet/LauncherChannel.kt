package dev.johniak.droplet

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Launches emulators with a ROM: path, FileProvider URI or SAF document URI. */
class LauncherChannel(private val activity: Activity) {
    companion object {
        const val NAME = "dev.johniak.droplet/launcher"
        const val PICK_TREE = 4711
        private const val TOKEN_ROM = " ROM "
        private const val TOKEN_SAF = " ROMSAF "
        private const val TOKEN_PROVIDER = " ROMPROVIDER "
        private const val MIME = "application/octet-stream"
    }

    private var pendingPick: MethodChannel.Result? = null

    fun attach(channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installedPackages" -> result.success(installed(call.argument<List<String>>("candidates") ?: emptyList()))
                "launch" -> result.success(launch(call.arguments as Map<*, *>))
                "pickRomTree" -> pickTree(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun installed(candidates: List<String>): List<String> = candidates.filter {
        try { activity.packageManager.getPackageInfo(it, 0); true } catch (e: PackageManager.NameNotFoundException) { false }
    }

    private fun providerUri(path: String): Uri =
        FileProvider.getUriForFile(activity, "${activity.packageName}.files", File(path))

    /** Document URI inside the persisted tree, or null when the file is outside it. */
    private fun safUri(path: String, treeUri: String?, treePath: String?): Uri? {
        if (treeUri == null || treePath == null) return null
        val tree = Uri.parse(treeUri)
        val base = treePath.trimEnd('/')
        if (!path.startsWith("$base/")) return null
        val rel = path.substring(base.length + 1)
        val docId = DocumentsContract.getTreeDocumentId(tree)
        return DocumentsContract.buildDocumentUriUsingTree(tree, "$docId/$rel")
    }

    /** Returns null on success, otherwise a short error string for the UI. */
    private fun launch(spec: Map<*, *>): String? {
        val pkg = spec["package"] as String
        val romPath = spec["romPath"] as String
        val treeUri = spec["romTreeUri"] as String?
        val treePath = spec["romTreePath"] as String?
        val mode = spec["dataMode"] as String
        val needsSaf = mode == "saf" || (spec["extras"] as Map<*, *>).values.any { it == TOKEN_SAF }
        val saf = safUri(romPath, treeUri, treePath)
        if (needsSaf && saf == null) return "saf-tree-missing"
        val provider = providerUri(romPath)

        val intent = Intent()
        (spec["activity"] as String?)?.let { intent.setClassName(pkg, it) } ?: intent.setPackage(pkg)
        intent.action = spec["action"] as String? ?: if (spec["activity"] != null) Intent.ACTION_MAIN else Intent.ACTION_VIEW
        (spec["category"] as String?)?.let { intent.addCategory(it) }
        val uris = mutableListOf<Uri>()
        when (mode) {
            "path" -> intent.data = Uri.fromFile(File(romPath))
            "saf" -> { intent.setDataAndType(saf, MIME); uris += saf!! }
            "provider" -> { intent.setDataAndType(provider, MIME); uris += provider }
        }
        for ((k, v) in spec["extras"] as Map<*, *>) {
            val key = k as String
            when (v) {
                is Boolean -> intent.putExtra(key, v)
                is String -> {
                    val value = when (v) {
                        TOKEN_ROM -> romPath
                        TOKEN_SAF -> { uris += saf!!; saf.toString() }
                        TOKEN_PROVIDER -> { uris += provider; provider.toString() }
                        else -> v.replace(TOKEN_ROM, romPath)
                    }
                    intent.putExtra(key, value)
                }
            }
        }
        var flags = Intent.FLAG_ACTIVITY_NEW_TASK
        if (spec["clearTask"] == true) flags = flags or Intent.FLAG_ACTIVITY_CLEAR_TASK
        if (spec["clearTop"] == true) flags = flags or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val grant = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        if (uris.isNotEmpty()) flags = flags or grant
        intent.flags = flags
        for (u in uris) {
            try { activity.grantUriPermission(pkg, u, grant) } catch (_: Exception) { }
        }
        return try {
            activity.startActivity(intent); null
        } catch (e: ActivityNotFoundException) {
            "activity-not-found"
        } catch (e: SecurityException) {
            "security: ${e.message}"
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingPick != null) { result.success(null); return }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        activity.startActivityForResult(intent, PICK_TREE)
    }

    /** Called from MainActivity.onActivityResult. Returns true when handled. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        activity.contentResolver.takePersistableUriPermission(
            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        result.success(mapOf("uri" to uri.toString(), "path" to treePath(uri)))
        return true
    }

    /** `primary:EMU/ROMs` -> /storage/emulated/0/EMU/ROMs; other volumes -> null. */
    private fun treePath(uri: Uri): String? {
        val id = DocumentsContract.getTreeDocumentId(uri)
        val parts = id.split(":", limit = 2)
        if (parts[0] != "primary") return null
        val root = Environment.getExternalStorageDirectory().absolutePath
        return if (parts.size == 1 || parts[1].isEmpty()) root else "$root/${parts[1]}"
    }
}
