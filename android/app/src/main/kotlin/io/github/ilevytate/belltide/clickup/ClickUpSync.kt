package io.github.ilevytate.belltide.clickup

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.core.content.edit
import io.github.ilevytate.belltide.engine.TimerConfig
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Logs running time to ClickUp. The timer service records a stretch of time when a
 * linked timer pauses, stops or finishes; entries are queued on the device and
 * uploaded in the background, so nothing is lost while offline.
 *
 * ClickUp allows one running timer per user, so Belltide creates finished time
 * entries instead. That is what lets several linked timers run at once.
 */
class ClickUpSync private constructor(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val tokens = TokenCipher()
    private val store = PrefsSyncStore()
    private val syncer = TimeEntrySyncer(store, TimeEntryUploader(UrlConnectionTransport()))
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)?.let { tokens.decrypt(it) }
        set(value) = prefs.edit {
            if (value.isNullOrBlank()) remove(KEY_TOKEN) else putString(KEY_TOKEN, tokens.encrypt(value))
        }

    var loggingEnabled: Boolean
        get() = prefs.getBoolean(KEY_LOG_TIME, true)
        set(value) = prefs.edit { putBoolean(KEY_LOG_TIME, value) }

    /** Queues a stretch of running time for a timer linked to a task. */
    fun recordSegment(config: TimerConfig, startWallMs: Long, durationMs: Long) {
        val task = config.task ?: return
        if (!loggingEnabled || durationMs < MIN_ENTRY_MS || token == null) return
        store.add(
            PendingTimeEntry(
                id = UUID.randomUUID().toString(),
                teamId = task.teamId,
                taskId = task.taskId,
                taskName = task.name,
                description = "${config.name.ifBlank { "Timer" }} (Belltide)",
                startMs = startWallMs,
                durationMs = durationMs,
            ),
        )
        flush()
    }

    /** Uploads queued entries in the background; [done] runs on the main thread. */
    fun flush(done: (() -> Unit)? = null) {
        executor.execute {
            try {
                val sent = syncer.flush(token)
                if (sent > 0) Log.d(TAG, "Sent $sent time entries")
                store.lastError?.let { Log.w(TAG, "Time entry sync: $it") }
            } catch (e: Exception) {
                Log.w(TAG, "Time entry sync failed", e)
            }
            if (done != null) main.post(done)
        }
    }

    fun status(): Map<String, Any?> = mapOf(
        "pending" to store.entries().size,
        "lastError" to store.lastError,
        "lastSyncedAt" to store.lastSyncedAt,
    )

    fun clearQueue() {
        store.clear()
        store.lastError = null
    }

    private inner class PrefsSyncStore : SyncStore {
        @Synchronized
        override fun entries() = PendingTimeEntry.listFromJson(prefs.getString(KEY_QUEUE, null))

        @Synchronized
        override fun add(entry: PendingTimeEntry) = save(entries() + entry)

        @Synchronized
        override fun remove(id: String) = save(entries().filter { it.id != id })

        @Synchronized
        override fun clear() = save(emptyList())

        private fun save(list: List<PendingTimeEntry>) = prefs.edit {
            if (list.isEmpty()) remove(KEY_QUEUE) else putString(KEY_QUEUE, PendingTimeEntry.listToJson(list))
        }

        override var lastError: String?
            get() = prefs.getString(KEY_LAST_ERROR, null)
            set(value) = prefs.edit { if (value == null) remove(KEY_LAST_ERROR) else putString(KEY_LAST_ERROR, value) }

        override var lastSyncedAt: Long
            get() = prefs.getLong(KEY_LAST_SYNCED, 0)
            set(value) = prefs.edit { putLong(KEY_LAST_SYNCED, value) }
    }

    companion object {
        private const val TAG = "BelltideClickUp"
        private const val PREFS = "belltide_clickup"
        private const val KEY_TOKEN = "token"
        private const val KEY_LOG_TIME = "log_time"
        private const val KEY_QUEUE = "pending_time_entries"
        private const val KEY_LAST_ERROR = "last_error"
        private const val KEY_LAST_SYNCED = "last_synced_at"

        /** Shorter stretches (a quick start and stop) aren't worth an entry. */
        const val MIN_ENTRY_MS = 1_000L

        @Volatile
        private var instance: ClickUpSync? = null

        fun get(context: Context): ClickUpSync =
            instance ?: synchronized(this) {
                instance ?: ClickUpSync(context).also { instance = it }
            }
    }
}

/**
 * Encrypts the API token with an AES key held in the Android Keystore, so the token
 * is never stored in plain text. If the key is lost (for example after a backup is
 * restored to another phone), decryption fails and the user reconnects.
 */
private class TokenCipher {
    fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return b64(cipher.iv) + ":" + b64(sealed)
    }

    fun decrypt(stored: String): String? = runCatching {
        val (iv, sealed) = stored.split(":", limit = 2)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, unb64(iv)))
        String(cipher.doFinal(unb64(sealed)), Charsets.UTF_8)
    }.getOrNull()

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun b64(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun unb64(text: String) = Base64.decode(text, Base64.NO_WRAP)

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "belltide_clickup_token"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}

/** HttpURLConnection-based transport; runs on the sync thread. */
private class UrlConnectionTransport : HttpTransport {
    override fun post(url: String, headers: Map<String, String>, body: String): HttpResponse {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.doOutput = true
            headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            return HttpResponse(code, text)
        } finally {
            connection.disconnect()
        }
    }
}
