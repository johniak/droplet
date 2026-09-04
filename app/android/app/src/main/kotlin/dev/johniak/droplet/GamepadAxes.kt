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
        /** A new direction needs a firm push... */
        const val ENGAGE = 0.6f

        /** ...and survives until the axis falls back below this. Two
         *  thresholds, not one: a worn stick resting on a single threshold
         *  would flip on consecutive samples (~100 Hz) and fire a burst of
         *  key presses, and on a diagonal the two axes would trade the focus
         *  back and forth. */
        const val RELEASE = 0.4f

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
        update(direction(x, y, heldNav), ::heldNav, { heldNav = it }, repeatNav)
        val rz = event.getAxisValue(MotionEvent.AXIS_RZ)
        update(scroll(rz, heldScroll), ::heldScroll, { heldScroll = it }, repeatScroll)
        return true
    }

    /** Hat wins when it moves; otherwise the analog stick. */
    private fun pick(hat: Float, stick: Float) = if (kotlin.math.abs(hat) > ENGAGE) hat else stick

    private fun direction(x: Float, y: Float, current: Int?): Int? {
        // Whatever we already report survives on its own axis alone: a
        // diagonal keeps going the way it started until that axis lets go.
        when (current) {
            KeyEvent.KEYCODE_DPAD_LEFT -> if (x < -RELEASE) return current
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (x > RELEASE) return current
            KeyEvent.KEYCODE_DPAD_UP -> if (y < -RELEASE) return current
            KeyEvent.KEYCODE_DPAD_DOWN -> if (y > RELEASE) return current
        }
        val ax = kotlin.math.abs(x)
        val ay = kotlin.math.abs(y)
        return when {
            ax < ENGAGE && ay < ENGAGE -> null
            ax >= ay -> if (x > 0) KeyEvent.KEYCODE_DPAD_RIGHT else KeyEvent.KEYCODE_DPAD_LEFT
            else -> if (y > 0) KeyEvent.KEYCODE_DPAD_DOWN else KeyEvent.KEYCODE_DPAD_UP
        }
    }

    /** The right stick's vertical axis, with the same hysteresis. */
    private fun scroll(rz: Float, current: Int?): Int? = when {
        current == KeyEvent.KEYCODE_PAGE_DOWN && rz > RELEASE -> current
        current == KeyEvent.KEYCODE_PAGE_UP && rz < -RELEASE -> current
        rz > ENGAGE -> KeyEvent.KEYCODE_PAGE_DOWN
        rz < -ENGAGE -> KeyEvent.KEYCODE_PAGE_UP
        else -> null
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
