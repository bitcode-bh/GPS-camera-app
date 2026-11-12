package io.flutter.plugins.camerax;

import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.ColorSpaceTransform;
import android.hardware.camera2.params.RggbChannelVector;
import android.os.Build;

import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2CameraControl;
import androidx.camera.camera2.interop.CaptureRequestOptions;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.CameraControl;
import androidx.core.content.ContextCompat;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public final class WhiteBalance {
    private WhiteBalance() {}

    @OptIn(markerClass = ExperimentalCamera2Interop.class)
    public static void apply(
            FlutterEngine engine, long controlId, Integer kelvin, boolean nativeCct, MethodChannel.Result result) {
        var plugin = (CameraAndroidCameraxPlugin) engine.getPlugins().get(CameraAndroidCameraxPlugin.class);
        if (plugin == null || plugin.proxyApiRegistrar == null) {
            result.error("CAMERA_CLOSED", "CameraX session is unavailable", null);
            return;
        }

        // Resolve the plugin's active control so preview, photo and video use the same request.
        CameraControl control = plugin.proxyApiRegistrar.getInstanceManager().getInstance(controlId);
        if (control == null) {
            result.error("CAMERA_CLOSED", "CameraX control is unavailable", null);
            return;
        }

        var camera2 = Camera2CameraControl.from(control);
        var request = CaptureRequestOptions.Builder.from(camera2.getCaptureRequestOptions());
        request.setCaptureRequestOption(CaptureRequest.CONTROL_AWB_MODE,
                kelvin == null ? CaptureRequest.CONTROL_AWB_MODE_AUTO : CaptureRequest.CONTROL_AWB_MODE_OFF);
        if (kelvin == null) {
            request.clearCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_MODE)
                    .clearCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_GAINS)
                    .clearCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_TRANSFORM);
            if (Build.VERSION.SDK_INT >= 36) {
                request.clearCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_COLOR_TEMPERATURE);
            }
        } else if (nativeCct && Build.VERSION.SDK_INT >= 36) {
            request.setCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_MODE, CaptureRequest.COLOR_CORRECTION_MODE_CCT)
                    .setCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_COLOR_TEMPERATURE, kelvin);
        } else {
            request.setCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_MODE, CaptureRequest.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX)
                    .setCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_GAINS, gainsFor(kelvin))
                    .setCaptureRequestOption(CaptureRequest.COLOR_CORRECTION_TRANSFORM,
                            new ColorSpaceTransform(new int[]{1,1, 0,1, 0,1, 0,1, 1,1, 0,1, 0,1, 0,1, 1,1}));
        }
        var update = camera2.setCaptureRequestOptions(request.build());
        update.addListener(() -> {
            try {
                update.get();
                result.success(null);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                result.error("WHITE_BALANCE_FAILED", error.getMessage(), null);
            } catch (Exception error) {
                result.error("WHITE_BALANCE_FAILED", error.getMessage(), null);
            }
        }, ContextCompat.getMainExecutor(plugin.proxyApiRegistrar.getContext()));
    }

    // Approximate the illuminant's red and blue components and invert them.
    private static RggbChannelVector gainsFor(int kelvin) {
        double t = kelvin / 100.0;
        double red = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
        double blue = t >= 66 ? 255 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        float redGain = (float) (255 / Math.max(63.75, Math.min(255, red)));
        float blueGain = (float) (255 / Math.max(63.75, Math.min(255, blue)));
        return new RggbChannelVector(redGain, 1f, 1f, blueGain);
    }
}
