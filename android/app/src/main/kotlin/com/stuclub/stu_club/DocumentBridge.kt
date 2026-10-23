package com.stuclub.stu_club

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.plugin.common.MethodChannel

class DocumentBridge(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null
    fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result): Boolean {
        if (method == "notify") {
            if (Build.VERSION.SDK_INT >= 26) {
                val manager = activity.getSystemService(NotificationManager::class.java)
                manager.createNotificationChannel(NotificationChannel("stuclub_updates", "StuClub", NotificationManager.IMPORTANCE_DEFAULT))
                val notification = android.app.Notification.Builder(activity, "stuclub_updates")
                    .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(args?.get("title") as? String ?: "StuClub")
                    .setContentText(args?.get("text") as? String ?: "تحديث جديد").setAutoCancel(true)
                    .setVisibility(android.app.Notification.VISIBILITY_PRIVATE).build()
                manager.notify(1001, notification)
            }
            result.success(null); return true
        }
        if (method !in listOf("pickDocument", "saveDocument")) return false
        if (pending != null) { result.error("BUSY", "يوجد اختيار ملف قيد التنفيذ", null); return true }
        pending = result
        try {
            if (method == "pickDocument") {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf", "text/plain", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"))
                }
                activity.startActivityForResult(intent, 701)
            } else {
                saveBytes = Base64.decode(args?.get("data") as String, Base64.NO_WRAP)
                if (saveBytes!!.size > 10 * 1024 * 1024) throw IllegalArgumentException()
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE); type = args["mime"] as? String ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, args["name"] as? String ?: "document")
                }
                activity.startActivityForResult(intent, 702)
            }
        } catch (_: Exception) { pending = null; saveBytes = null; result.error("DOCUMENT", "تعذر فتح الملفات", null) }
        return true
    }
    fun onResult(code: Int, resultCode: Int, data: Intent?) {
        if (code !in listOf(701,702)) return
        val result = pending ?: return
        pending = null
        try {
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
            if (code == 702) {
                activity.contentResolver.openOutputStream(uri)?.use { it.write(saveBytes ?: throw IllegalStateException()) }
                    ?: throw IllegalStateException()
                result.success(true)
            } else {
                var name = "document"
                activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) name = cursor.getString(0)
                }
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val out = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192); var total = 0
                    while (true) { val count = input.read(buffer); if (count == -1) break; total += count
                        if (total > 10 * 1024 * 1024) throw IllegalArgumentException(); out.write(buffer,0,count) }
                    out.toByteArray()
                } ?: throw IllegalStateException()
                result.success(mapOf("name" to name, "data" to Base64.encodeToString(bytes,Base64.NO_WRAP)))
            }
        } catch (_: Exception) { result.error("DOCUMENT", "تعذر قراءة أو حفظ المستند؛ الحد الأقصى ١٠ ميجابايت", null) }
        finally { saveBytes = null }
    }
}
