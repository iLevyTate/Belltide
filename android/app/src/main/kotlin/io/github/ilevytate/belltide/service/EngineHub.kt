package io.github.ilevytate.belltide.service

import android.os.Handler
import android.os.Looper
import java.util.concurrent.CopyOnWriteArrayList

/**
 * In-process bridge between the timer service and the Flutter UI. The service
 * publishes a JSON snapshot whenever state changes; the activity's event channel
 * listens. Both sides run in the same process, so no binding is needed.
 */
object EngineHub {
    const val EMPTY_STATE = """{"timers":[],"finished":[]}"""

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()

    /** Set by the running service so listeners can ask for fresh state at any time. */
    @Volatile
    var snapshotProvider: (() -> String)? = null

    fun current(): String = snapshotProvider?.invoke() ?: EMPTY_STATE

    fun publish(json: String) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            listeners.forEach { it(json) }
        } else {
            main.post { listeners.forEach { it(json) } }
        }
    }

    fun addListener(listener: (String) -> Unit) {
        listeners += listener
    }

    fun removeListener(listener: (String) -> Unit) {
        listeners -= listener
    }
}
