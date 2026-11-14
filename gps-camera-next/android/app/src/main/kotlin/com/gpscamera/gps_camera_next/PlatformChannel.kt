package com.gpscamera.gps_camera_next

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Address
import android.location.Geocoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Small platform services the app needs, without a plugin per service:
 * app folders, version, opening the gallery, reverse geocoding, and the
 * compass and gravity sensors.
 */
class PlatformChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val context: Context = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    init {
        MethodChannel(messenger, "com.gpscamera.gps_camera_next/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                // The same folders path_provider used, so existing data stays put.
                "dirs" -> result.success(
                    mapOf(
                        "support" to context.filesDir.absolutePath,
                        "documents" to context.getDir("flutter", Context.MODE_PRIVATE).absolutePath,
                    )
                )
                "appVersion" -> result.success(appVersion())
                "openGallery" -> result.success(openGallery())
                "geocode" -> {
                    val lat = call.argument<Double>("lat")
                    val lon = call.argument<Double>("lon")
                    if (lat == null || lon == null) result.success(null) else geocode(lat, lon, result)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "com.gpscamera.gps_camera_next/heading")
            .setStreamHandler(SensorStream(Sensor.TYPE_ROTATION_VECTOR, SensorManager.SENSOR_DELAY_UI) { event ->
                val rotation = FloatArray(9)
                val orientation = FloatArray(3)
                SensorManager.getRotationMatrixFromVector(rotation, event.values)
                SensorManager.getOrientation(rotation, orientation)
                Math.toDegrees(orientation[0].toDouble())
            })
        EventChannel(messenger, "com.gpscamera.gps_camera_next/gravity")
            .setStreamHandler(SensorStream(Sensor.TYPE_ACCELEROMETER, SensorManager.SENSOR_DELAY_NORMAL) { event ->
                listOf(event.values[0].toDouble(), event.values[1].toDouble(), event.values[2].toDouble())
            })
    }

    private fun appVersion(): Map<String, Any> {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf("name" to (info.versionName ?: ""), "code" to code)
    }

    private fun openGallery(): Boolean {
        val gallery = Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_GALLERY)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val photos = Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        for (intent in listOf(gallery, photos)) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    /** The device's own geocoder. Returns null when the phone has none. */
    private fun geocode(lat: Double, lon: Double, result: MethodChannel.Result) {
        if (!Geocoder.isPresent()) return result.success(null)
        val geocoder = Geocoder(context, Locale.getDefault())
        val reply = { address: Address? -> main.post { result.success(address?.let(::toMap)) } }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                geocoder.getFromLocation(lat, lon, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<Address>) = reply(addresses.firstOrNull())
                    override fun onError(errorMessage: String?) = reply(null)
                })
            } else {
                worker.execute {
                    val address = try {
                        @Suppress("DEPRECATION")
                        geocoder.getFromLocation(lat, lon, 1)?.firstOrNull()
                    } catch (_: Exception) {
                        null
                    }
                    reply(address)
                }
            }
        } catch (_: Exception) {
            reply(null)
        }
    }

    private fun toMap(a: Address) = mapOf(
        "name" to a.featureName,
        "thoroughfare" to a.thoroughfare,
        "subLocality" to a.subLocality,
        "locality" to a.locality,
        "administrativeArea" to a.adminArea,
        "postalCode" to a.postalCode,
        "country" to a.countryName,
        "isoCountryCode" to a.countryCode,
    )

    /** A sensor that runs only while Dart listens. */
    private inner class SensorStream(
        private val type: Int,
        private val delay: Int,
        private val read: (SensorEvent) -> Any,
    ) : EventChannel.StreamHandler, SensorEventListener {
        private var sink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val sensor = sensors.getDefaultSensor(type) ?: return events.endOfStream()
            sink = events
            sensors.registerListener(this, sensor, delay)
        }

        override fun onCancel(arguments: Any?) {
            sensors.unregisterListener(this)
            sink = null
        }

        override fun onSensorChanged(event: SensorEvent) {
            sink?.success(read(event))
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    fun dispose() {
        worker.shutdown()
    }
}
