package dev.johniak.droplet

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

/**
 * Turns joystick axes into key events Flutter already understands: the left
 * stick and the hat become D-pad keys (focus navigation), the right stick's
 * vertical axis becomes PageUp/PageDown (scrolling). Holding a direction
 * repeats like a held key.
 *
 * A D-pad reported as real `KEYCODE_DPAD_*` keys never reaches this code, so
 * nothing is ever synthesised twice.
 */
class GamepadAxes(private val dispatch: (KeyEvent) -> Unit) {
    companion object {
        const val DEADZONE = 0.5f
        const val FIRST_REPEAT_MS = 400L
        const val REPEAT_MS = 120L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var heldNav: Int? = null // current D-pad keycode from left stick / hat
    private var heldScroll: Int? = null // current PAGE_* keycode from right stick
    private val repeatNav = object : Runnable {
        override fun run() {
            heldNav?.let { press(it); handler.postDelayed(this, REPEAT_MS) }
        }
    }
    private val repeatScroll = object : Runnable {
        override fun run() {
            heldScroll?.let { press(it); handler.postDelayed(this, REPEAT_MS) }
        }
    }

    /** Returns true when the event was a joystick move we consumed. */
    fun onMotion(event: MotionEvent): Boolean {
        val isStick = event.source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
        if (!isStick || event.action != MotionEvent.ACTION_MOVE) return false
        val x = pick(event.getAxisValue(MotionEvent.AXIS_HAT_X), event.getAxisValue(MotionEvent.AXIS_X))
        val y = pick(event.getAxisValue(MotionEvent.AXIS_HAT_Y), event.getAxisValue(MotionEvent.AXIS_Y))
        update(direction(x, y), ::heldNav, { heldNav = it }, repeatNav)
        val rz = event.getAxisValue(MotionEvent.AXIS_RZ)
        val scroll = when {
            rz > DEADZONE -> KeyEvent.KEYCODE_PAGE_DOWN
            rz < -DEADZONE -> KeyEvent.KEYCODE_PAGE_UP
            else -> null
        }
        update(scroll, ::heldScroll, { heldScroll = it }, repeatScroll)
        return true
    }

    /** Hat wins when it moves; otherwise the analog stick. */
    private fun pick(hat: Float, stick: Float) = if (kotlin.math.abs(hat) > DEADZONE) hat else stick

    private fun direction(x: Float, y: Float): Int? = when {
        kotlin.math.abs(x) < DEADZONE && kotlin.math.abs(y) < DEADZONE -> null
        kotlin.math.abs(x) >= kotlin.math.abs(y) ->
            if (x > 0) KeyEvent.KEYCODE_DPAD_RIGHT else KeyEvent.KEYCODE_DPAD_LEFT
        else -> if (y > 0) KeyEvent.KEYCODE_DPAD_DOWN else KeyEvent.KEYCODE_DPAD_UP
    }

    private fun update(next: Int?, held: () -> Int?, set: (Int?) -> Unit, repeat: Runnable) {
        val current = held()
        if (next == current) return
        handler.removeCallbacks(repeat)
        set(next)
        if (next != null) {
            press(next)
            handler.postDelayed(repeat, FIRST_REPEAT_MS)
        }
    }

    private fun press(keyCode: Int) {
        val now = SystemClock.uptimeMillis()
        dispatch(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, 0, 0, 0, 0, InputDevice.SOURCE_KEYBOARD))
        dispatch(KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0, 0, 0, 0, 0, InputDevice.SOURCE_KEYBOARD))
    }

    /** Stops every pending repeat — the app is going away. */
    fun release() {
        handler.removeCallbacks(repeatNav)
        handler.removeCallbacks(repeatScroll)
        heldNav = null
        heldScroll = null
    }
}
