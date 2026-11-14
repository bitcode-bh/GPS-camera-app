package com.gpscamera.gps_camera_next

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground location with the platform LocationManager: permission, fixes
 * every few seconds, and the device location switch. No Play services needed.
 */
class LocationChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val context: Context = activity.applicationContext
    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val prefs = context.getSharedPreferences("location_permission", Context.MODE_PRIVATE)
    private var pendingRequest: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "com.gpscamera.gps_camera_next/location").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "request" -> request(result)
                "openAppSettings" -> result.success(
                    start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                )
                "openLocationSettings" -> result.success(start(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)))
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "com.gpscamera.gps_camera_next/positions").setStreamHandler(Positions())
        EventChannel(messenger, "com.gpscamera.gps_camera_next/location_switch").setStreamHandler(Switch())
    }

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun serviceEnabled() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        manager.isLocationEnabled
    } else {
        manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    /** "granted", "denied" (may ask) or "deniedForever" (only Settings helps). */
    private fun permission(): String {
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine || coarse) return "granted"
        // Android only says "don't ask again" indirectly: asked before, and no
        // rationale is offered any more.
        val askedBefore = prefs.getBoolean("asked", false)
        val rationale = activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)
        return if (askedBefore && !rationale) "deniedForever" else "denied"
    }

    private fun status() = mapOf(
        "service" to serviceEnabled(),
        "permission" to permission(),
        "approximate" to (granted(Manifest.permission.ACCESS_COARSE_LOCATION) &&
            !granted(Manifest.permission.ACCESS_FINE_LOCATION)),
    )

    private fun request(result: MethodChannel.Result) {
        if (permission() == "granted") return result.success(status())
        if (pendingRequest != null) return result.error("busy", "A request is already open", null)
        pendingRequest = result
        prefs.edit().putBoolean("asked", true).apply()
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            REQUEST_LOCATION,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_LOCATION) return false
        pendingRequest?.success(status())
        pendingRequest = null
        return true
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        false
    }

    /** Fixes every ~5 s while Dart listens. */
    private inner class Positions : EventChannel.StreamHandler, LocationListener {
        private var sink: EventChannel.EventSink? = null

        @SuppressLint("MissingPermission")
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
            if (permission() != "granted") return events.error("permission", "Location permission missing", null)
            val providers = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                manager.allProviders.contains(LocationManager.FUSED_PROVIDER)
            ) {
                listOf(LocationManager.FUSED_PROVIDER)
            } else {
                listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
                    .filter { manager.allProviders.contains(it) }
            }
            if (providers.isEmpty()) return events.error("unavailable", "No location provider", null)
            try {
                for (provider in providers) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // Without an explicit request the fused provider runs
                        // at "balanced" (Wi-Fi/cell) accuracy; a stamp needs GPS.
                        val request = LocationRequest.Builder(INTERVAL_MS)
                            .setQuality(LocationRequest.QUALITY_HIGH_ACCURACY)
                            .setMinUpdateIntervalMillis(1000)
                            .build()
                        manager.requestLocationUpdates(provider, request, context.mainExecutor, this)
                    } else {
                        manager.requestLocationUpdates(provider, INTERVAL_MS, 0f, this, Looper.getMainLooper())
                    }
                }
            } catch (error: SecurityException) {
                events.error("permission", "Location permission missing", null)
            } catch (error: Exception) {
                events.error("unavailable", error.javaClass.simpleName, null)
            }
        }

        override fun onCancel(arguments: Any?) {
            manager.removeUpdates(this)
            sink = null
        }

        override fun onLocationChanged(location: Location) {
            sink?.success(
                mapOf(
                    "lat" to location.latitude,
                    "lon" to location.longitude,
                    "altitude" to (if (location.hasAltitude()) location.altitude else 0.0),
                    "accuracy" to (if (location.hasAccuracy()) location.accuracy.toDouble() else Double.NaN),
                    "heading" to (if (location.hasBearing()) location.bearing.toDouble() else -1.0),
                    "speed" to (if (location.hasSpeed()) location.speed.toDouble() else -1.0),
                    "time" to location.time,
                )
            )
        }

        override fun onProviderDisabled(provider: String) {
            if (!serviceEnabled()) sink?.error("disabled", "Location is off", null)
        }

        override fun onProviderEnabled(provider: String) = Unit

        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    }

    /** The device location switch, while Dart listens. */
    private inner class Switch : EventChannel.StreamHandler {
        private var receiver: BroadcastReceiver? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val listener = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) = events.success(serviceEnabled())
            }
            receiver = listener
            val filter = IntentFilter(LocationManager.PROVIDERS_CHANGED_ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(listener, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(listener, filter)
            }
        }

        override fun onCancel(arguments: Any?) {
            receiver?.let { context.unregisterReceiver(it) }
            receiver = null
        }
    }

    companion object {
        const val REQUEST_LOCATION = 4703
        const val INTERVAL_MS = 5000L
    }
}
