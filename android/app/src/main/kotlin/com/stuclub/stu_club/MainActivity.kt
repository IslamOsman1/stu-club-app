package com.stuclub.stu_club

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val documents by lazy { DocumentBridge(this) }
    override fun onActivityResult(requestCode:Int, resultCode:Int, data:android.content.Intent?) {
        super.onActivityResult(requestCode,resultCode,data);documents.onResult(requestCode,resultCode,data)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("stuclub_session", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("stuclub_session", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val prefs = getSharedPreferences("stuclub_private", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stuclub/secure").setMethodCallHandler { call, result ->
            if(documents.handle(call.method,call.arguments as? Map<*,*>,result)) return@setMethodCallHandler
            try {
                when (call.method) {
                    "isEmulator" -> result.success(Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish" || Build.MODEL.contains("sdk_gphone"))
                    "read" -> {
                        val name = call.arguments as String
                        val saved = prefs.getString(name, null)
                        if (saved == null) result.success(null)
                        else {
                            val parts = saved.split(":")
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                            result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                        }
                    }
                    "write" -> {
                        val name = call.argument<String>("key")!!
                        val value = call.argument<String>("value")!!
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, key())
                        val encoded = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
                        if (!prefs.edit().putString(name, encoded).commit()) throw IllegalStateException("Storage failed")
                        result.success(null)
                    }
                    "delete" -> {
                        if (!prefs.edit().remove(call.arguments as String).commit()) throw IllegalStateException("Storage failed")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("SECURE_STORAGE", "تعذر قراءة الجلسة أو حفظها", null) }
        }
    }
}

