package com.gpscamera.gps_camera_pro

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.ColorSpaceTransform
import android.hardware.camera2.params.RggbChannelVector
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.FileOutputStream
import kotlin.math.abs

/**
 * A self-contained Camera2 preview + still-capture pipeline that renders into a
 * Flutter [TextureRegistry] surface and lets Dart drive **real manual sensor
 * controls** — ISO, shutter (exposure time), white balance (preset or Kelvin),
 * manual focus distance and exposure compensation — which the off-the-shelf
 * Flutter camera plugins cannot apply.
 *
 * All controls are pushed straight into the repeating preview [CaptureRequest]
 * so the live preview updates immediately; the same values are used for the
 * still capture.
 */
class ProCamera2(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : EventChannel.StreamHandler {

    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null

    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private var previewSurface: Surface? = null
    private var imageReader: ImageReader? = null
    private var requestBuilder: CaptureRequest.Builder? = null

    private var cameraId: String? = null
    private var chars: CameraCharacteristics? = null
    private var previewSize = Size(1920, 1080)
    private var sensorActiveArray: android.graphics.Rect? = null

    private var events: EventChannel.EventSink? = null

    // Current control state. Null = auto for that axis.
    private var manualIso: Int? = null
    private var manualExposureNs: Long? = null
    private var awbMode: Int? = null          // null = auto; >=0 camera2 AWB mode; -1 = manual kelvin
    private var kelvin: Int? = null
    private var manualFocus: Float? = null     // diopters; null = AF auto
    private var evComp: Int = 0
    private var zoomRatio: Float = 1f

    init {
        EventChannel(messenger, "$NS/events").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
    override fun onCancel(arguments: Any?) { events = null }

    private fun emit(event: String, extra: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>()
        payload["event"] = event
        payload.putAll(extra)
        Handler(context.mainLooper).post { events?.success(payload) }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> open(call, result)
            "setControls" -> { setControls(call); result.success(true) }
            "capture" -> capture(call, result)
            "close" -> { close(); result.success(true) }
            else -> result.notImplemented()
        }
    }

    private fun startBg() {
        if (bgThread != null) return
        bgThread = HandlerThread("ProCamera2").also { it.start() }
        bgHandler = Handler(bgThread!!.looper)
    }

    private fun stopBg() {
        bgThread?.quitSafely()
        bgThread = null
        bgHandler = null
    }

    private fun pickCamera(front: Boolean): String? {
        val want = if (front) CameraCharacteristics.LENS_FACING_FRONT
        else CameraCharacteristics.LENS_FACING_BACK
        for (id in manager.cameraIdList) {
            val c = manager.getCameraCharacteristics(id)
            if (c.get(CameraCharacteristics.LENS_FACING) == want) return id
        }
        return manager.cameraIdList.firstOrNull()
    }

    private fun chooseSize(targetW: Int, targetH: Int): Size {
        val map = chars?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = map?.getOutputSizes(SurfaceTexture::class.java) ?: return Size(1920, 1080)
        val targetRatio = targetW.toDouble() / targetH.toDouble()
        // Prefer a size close to the requested resolution with a matching ratio.
        return sizes.minByOrNull {
            val ratio = it.width.toDouble() / it.height.toDouble()
            abs(it.width - targetW) + abs(it.height - targetH) + abs(ratio - targetRatio) * 2000
        } ?: sizes.first()
    }

    @Suppress("MissingPermission")
    private fun open(call: MethodCall, result: MethodChannel.Result) {
        try {
            startBg()
            val targetW = (call.argument<Int>("width")) ?: 1920
            val targetH = (call.argument<Int>("height")) ?: 1080
            val front = call.argument<Boolean>("front") ?: false
            cameraId = pickCamera(front) ?: run { result.error("no_camera", "No camera", null); return }
            chars = manager.getCameraCharacteristics(cameraId!!)
            sensorActiveArray = chars?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            previewSize = chooseSize(targetW, targetH)
            Log.i(TAG, "open: camera=$cameraId previewSize=$previewSize target=${targetW}x$targetH")

            // SurfaceProducer is the Impeller-compatible texture path (the old
            // SurfaceTexture entry renders black under Vulkan/Impeller). The
            // producer may (re)create its backing surface, so we rebuild the
            // capture session via its callback rather than caching one surface.
            val producer = textures.createSurfaceProducer()
            surfaceProducer = producer
            producer.setSize(previewSize.width, previewSize.height)
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    Log.i(TAG, "surface available -> (re)create session")
                    if (device != null) createSession()
                }
                override fun onSurfaceCleanup() {
                    Log.i(TAG, "surface cleanup")
                    try { session?.close() } catch (_: Exception) {}
                    session = null
                }
            })

            // Largest JPEG for stills.
            val map = chars?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val jpegSize = map?.getOutputSizes(ImageFormat.JPEG)?.maxByOrNull { it.width.toLong() * it.height }
                ?: previewSize
            imageReader = ImageReader.newInstance(jpegSize.width, jpegSize.height, ImageFormat.JPEG, 2)

            manager.openCamera(cameraId!!, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    Log.i(TAG, "camera onOpened")
                    device = camera
                    createSession()
                }
                override fun onDisconnected(camera: CameraDevice) { Log.w(TAG, "onDisconnected"); close() }
                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "camera device error=$error")
                    emit("error", mapOf("code" to "device_error", "detail" to error))
                    close()
                }
            }, bgHandler)

            result.success(
                mapOf(
                    "textureId" to producer.id(),
                    "previewWidth" to previewSize.width,
                    "previewHeight" to previewSize.height,
                )
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "open access exception", e)
            result.error("open_failed", e.message, null)
        } catch (e: Exception) {
            Log.e(TAG, "open exception", e)
            result.error("open_failed", e.message, null)
        }
    }

    private fun createSession() {
        try {
            val dev = device ?: return
            val preview = surfaceProducer?.surface ?: run {
                Log.w(TAG, "no producer surface yet")
                return
            }
            previewSurface = preview
            val reader = imageReader ?: return
            val targets = listOf(preview, reader.surface)
            @Suppress("DEPRECATION")
            dev.createCaptureSession(targets, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    session = s
                    val b = dev.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    b.addTarget(preview)
                    requestBuilder = b
                    applyControlsToBuilder(b)
                    startRepeating()
                    Log.i(TAG, "session configured, repeating started")
                    emit("opened")
                }
                override fun onConfigureFailed(s: CameraCaptureSession) {
                    Log.e(TAG, "session configure FAILED")
                    emit("error", mapOf("code" to "session_failed"))
                }
            }, bgHandler)
        } catch (e: Exception) {
            emit("error", mapOf("code" to "session_exception", "detail" to e.message))
        }
    }

    private fun startRepeating() {
        val s = session ?: return
        val b = requestBuilder ?: return
        try {
            s.setRepeatingRequest(b.build(), null, bgHandler)
        } catch (e: Exception) {
            Log.e(TAG, "repeating request failed", e)
            emit("error", mapOf("code" to "repeat_failed", "detail" to e.message))
        }
    }

    private fun setControls(call: MethodCall) {
        // Negative values are an "auto" sentinel that clears that manual axis.
        if (call.hasArgument("iso")) {
            val v = call.argument<Int>("iso"); manualIso = if (v == null || v < 0) null else v
        }
        if (call.hasArgument("exposureNs")) {
            val v = (call.argument<Number>("exposureNs"))?.toLong()
            manualExposureNs = if (v == null || v < 0) null else v
        }
        if (call.hasArgument("awbMode")) awbMode = call.argument<Int>("awbMode")
        if (call.hasArgument("kelvin")) {
            val v = call.argument<Int>("kelvin"); kelvin = if (v == null || v < 0) null else v
        }
        if (call.hasArgument("focusDistance")) {
            val v = (call.argument<Number>("focusDistance"))?.toFloat()
            manualFocus = if (v == null || v < 0f) null else v
        }
        if (call.hasArgument("ev")) evComp = call.argument<Int>("ev") ?: 0
        if (call.hasArgument("zoom")) zoomRatio = (call.argument<Number>("zoom"))?.toFloat() ?: 1f
        val b = requestBuilder ?: return
        applyControlsToBuilder(b)
        startRepeating()
    }

    /** Pushes the current control state into [b]. */
    private fun applyControlsToBuilder(b: CaptureRequest.Builder) {
        val c = chars ?: return
        b.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)

        // Manual exposure (ISO + shutter). camera2 requires AE OFF and BOTH
        // sensitivity and exposure time; if only one is set we fill the other
        // from the sensor's range so the request is valid.
        val iso = manualIso
        val exp = manualExposureNs
        if (iso != null || exp != null) {
            b.set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_OFF)
            val isoRange = c.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
            val expRange = c.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
            val isoVal = iso ?: 100
            val expVal = exp ?: 16_666_666L // ~1/60s default
            isoRange?.let { b.set(CaptureRequest.SENSOR_SENSITIVITY, isoVal.coerceIn(it.lower, it.upper)) }
                ?: b.set(CaptureRequest.SENSOR_SENSITIVITY, isoVal)
            expRange?.let { b.set(CaptureRequest.SENSOR_EXPOSURE_TIME, expVal.coerceIn(it.lower, it.upper)) }
                ?: b.set(CaptureRequest.SENSOR_EXPOSURE_TIME, expVal)
        } else {
            b.set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
            b.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, evComp)
        }

        // White balance: preset AWB mode, manual Kelvin, or auto.
        when {
            kelvin != null -> {
                b.set(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_OFF)
                b.set(CaptureRequest.COLOR_CORRECTION_MODE, CameraMetadata.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX)
                b.set(CaptureRequest.COLOR_CORRECTION_GAINS, kelvinToGains(kelvin!!))
                b.set(
                    CaptureRequest.COLOR_CORRECTION_TRANSFORM,
                    ColorSpaceTransform(intArrayOf(1,1,0,1,0,1,0,1,0,1,1,1,0,1,0,1,0,1))
                )
            }
            awbMode != null && awbMode != CameraMetadata.CONTROL_AWB_MODE_AUTO -> {
                b.set(CaptureRequest.CONTROL_AWB_MODE, awbMode!!)
            }
            else -> b.set(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
        }

        // Manual focus distance (diopters) or continuous AF.
        val mf = manualFocus
        if (mf != null && mf > 0f) {
            b.set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_OFF)
            val minFocus = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
            b.set(CaptureRequest.LENS_FOCUS_DISTANCE, mf.coerceIn(0f, if (minFocus > 0f) minFocus else mf))
        } else {
            b.set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        }

        // Zoom: prefer CONTROL_ZOOM_RATIO (API 30+), else crop region.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && zoomRatio > 1f) {
            b.set(CaptureRequest.CONTROL_ZOOM_RATIO, zoomRatio)
        } else if (zoomRatio > 1f) {
            sensorActiveArray?.let { rect ->
                val cropW = (rect.width() / zoomRatio).toInt()
                val cropH = (rect.height() / zoomRatio).toInt()
                val left = (rect.width() - cropW) / 2
                val top = (rect.height() - cropH) / 2
                b.set(CaptureRequest.SCALER_CROP_REGION, android.graphics.Rect(left, top, left + cropW, top + cropH))
            }
        }
    }

    /** Rough Kelvin → RGGB gains mapping for manual white balance. */
    private fun kelvinToGains(k: Int): RggbChannelVector {
        val t = k.coerceIn(2000, 9000) / 100.0
        // Simple approximation of the planckian locus → RGB, then invert to gains.
        var r: Double; var g: Double; var bl: Double
        if (t <= 66) {
            r = 255.0
            g = 99.4708025861 * Math.log(t) - 161.1195681661
        } else {
            r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
            g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
        }
        bl = if (t >= 66) 255.0 else if (t <= 19) 0.0 else 138.5177312231 * Math.log(t - 10) - 305.0447927307
        r = r.coerceIn(1.0, 255.0); g = g.coerceIn(1.0, 255.0); bl = bl.coerceIn(1.0, 255.0)
        // Gains are inverse of the light colour, normalised so green ~= 1.
        val rg = (255.0 / r).toFloat()
        val gg = 1.0f
        val bg = (255.0 / bl).toFloat()
        return RggbChannelVector(rg, gg, gg, bg)
    }

    private fun capture(call: MethodCall, result: MethodChannel.Result) {
        val dev = device
        val s = session
        val reader = imageReader
        val path = call.argument<String>("path")
        if (dev == null || s == null || reader == null || path == null) {
            result.error("not_ready", "Camera not ready", null); return
        }
        try {
            reader.setOnImageAvailableListener({ r ->
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    FileOutputStream(path).use { it.write(bytes) }
                    Handler(context.mainLooper).post { result.success(path) }
                } catch (e: Exception) {
                    Handler(context.mainLooper).post { result.error("write_failed", e.message, null) }
                } finally {
                    image.close()
                }
            }, bgHandler)

            val b = dev.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            b.addTarget(reader.surface)
            applyControlsToBuilder(b)
            b.set(CaptureRequest.JPEG_ORIENTATION, sensorOrientation())
            s.capture(b.build(), object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureFailed(session: CameraCaptureSession, request: CaptureRequest, failure: android.hardware.camera2.CaptureFailure) {
                    Handler(context.mainLooper).post { result.error("capture_failed", "reason ${failure.reason}", null) }
                }
            }, bgHandler)
        } catch (e: Exception) {
            result.error("capture_exception", e.message, null)
        }
    }

    private fun sensorOrientation(): Int =
        chars?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

    fun close() {
        try { session?.close() } catch (_: Exception) {}
        try { device?.close() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { surfaceProducer?.release() } catch (_: Exception) {}
        session = null; device = null; imageReader = null
        previewSurface = null; surfaceProducer = null; requestBuilder = null
        stopBg()
        emit("closed")
    }

    companion object {
        const val NS = "com.gpscamera.gps_camera_pro/procam"
        const val TAG = "ProCamera2"
    }
}
