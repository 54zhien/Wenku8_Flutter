package org.mewx.wenku8_flutter

import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var desiredFrameRate = 0f
    private val trackedSurfaces = HashSet<SurfaceView>()
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val fastest = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth &&
                it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        // Android 14+ accepts a frame-rate-only preference, without a resolution
        // or non-seamless mode change. Older Android selects a same-size mode.
        attributes.preferredDisplayModeId =
            if (Build.VERSION.SDK_INT >= 34) 0 else fastest.modeId
        attributes.preferredRefreshRate = fastest.refreshRate
        window.attributes = attributes
        desiredFrameRate = fastest.refreshRate
        window.decorView.post { requestSurfaceRate(window.decorView) }
    }

    private fun requestSurfaceRate(view: View) {
        if (view is SurfaceView) {
            // The surface is a separate frame-rate voter. A window preference
            // alone can leave Android's HIGH category at 90Hz on a 120Hz panel.
            if (Build.VERSION.SDK_INT >= 36) view.requestedFrameRate = desiredFrameRate
            if (trackedSurfaces.add(view)) {
                view.holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) = setSurfaceRate(holder.surface)
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = setSurfaceRate(holder.surface)
                    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
                })
            }
            setSurfaceRate(view.holder.surface)
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) requestSurfaceRate(view.getChildAt(index))
        }
    }

    private fun setSurfaceRate(surface: Surface) {
        if (!surface.isValid || desiredFrameRate <= 0f) return
        if (Build.VERSION.SDK_INT >= 31) {
            surface.setFrameRate(desiredFrameRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)
        } else if (Build.VERSION.SDK_INT >= 30) {
            surface.setFrameRate(desiredFrameRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachWenkuEnginePlugins(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
