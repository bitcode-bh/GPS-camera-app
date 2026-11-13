package com.gpscamera.gps_camera_next

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import androidx.media3.common.util.Size
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextureOverlay
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@UnstableApi
internal object VideoStamp {
    fun export(
        context: Context,
        source: File,
        startedAtMs: Long,
        samples: List<Pair<Long, String>>,
        clock24: Boolean,
        frames: List<Pair<Long, File>>,
        stampRect: List<Float>?,
        result: MethodChannel.Result,
    ) {
        var pendingOutput: File? = null
        try {
            val output = File.createTempFile("stamped_", ".mp4", context.cacheDir)
            pendingOutput = output
            check(output.delete())
            val format = SimpleDateFormat(
                if (clock24) "dd MMM yyyy HH:mm:ss" else "dd MMM yyyy hh:mm:ss a",
                Locale.getDefault(),
            )
            val settings = StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(-1f, -1f)
                .setBackgroundFrameAnchor(-0.94f, -0.94f)
                .build()
            val overlay = object : TextOverlay() {
                private var fontSize = 24
                private var lastSecond = Long.MIN_VALUE
                private var text = SpannableString("")

                override fun configure(videoSize: Size) {
                    super.configure(videoSize)
                    fontSize = (minOf(videoSize.width, videoSize.height) * 0.032f)
                        .toInt().coerceAtLeast(14)
                }

                override fun getOverlaySettings(presentationTimeUs: Long) = settings

                override fun getText(presentationTimeUs: Long): SpannableString {
                    val second = presentationTimeUs / 1_000_000
                    if (second == lastSecond) return text
                    lastSecond = second
                    val atMs = second * 1000
                    val index = samples.binarySearchBy(atMs) { it.first }
                    val location = samples.getOrNull(if (index >= 0) index else -index - 2)
                        ?.second.orEmpty()
                    val timestamp = format.format(Date(startedAtMs + atMs))
                    text = SpannableString(
                        if (location.isEmpty()) timestamp else "$timestamp\n$location"
                    ).apply {
                        setSpan(AbsoluteSizeSpan(fontSize), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        setSpan(ForegroundColorSpan(Color.WHITE), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        setSpan(object : CharacterStyle() {
                            override fun updateDrawState(paint: TextPaint) {
                                paint.setShadowLayer(3f, 0f, 1.5f, Color.BLACK)
                            }
                        }, 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                    return text
                }
            }
            // The same stamp as a photo: pictures of the on-screen stamp, placed
            // where it sits in the viewfinder. The text stamp is the fallback.
            val stamp: TextureOverlay =
                if (frames.isNotEmpty() && stampRect != null) {
                    pictureOverlay(frames, stampRect)
                } else {
                    overlay
                }
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(source)))
                .setEffects(Effects(emptyList(), listOf(OverlayEffect(listOf(stamp)))))
                .build()
            Transformer.Builder(context)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        result.success(output.absolutePath)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        output.delete()
                        result.error("video_stamp", "Could not render the video stamp", null)
                    }
                })
                .build()
                .start(item, output.absolutePath)
        } catch (error: Exception) {
            pendingOutput?.delete()
            result.error("video_stamp", "Could not start the video export", null)
        }
    }

    private fun pictureOverlay(frames: List<Pair<Long, File>>, rect: List<Float>): BitmapOverlay {
        val (left, bottom, width) = rect
        val settings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(-1f, -1f)
            .setBackgroundFrameAnchor(
                (-1f + 2f * left).coerceIn(-1f, 1f),
                (-1f + 2f * bottom).coerceIn(-1f, 1f),
            )
            .build()
        return object : BitmapOverlay() {
            private var targetWidth = 0
            private var shown = -1
            private var bitmap: Bitmap? = null

            override fun configure(videoSize: Size) {
                super.configure(videoSize)
                targetWidth = (videoSize.width * width).toInt().coerceAtLeast(1)
            }

            override fun getOverlaySettings(presentationTimeUs: Long) = settings

            override fun getBitmap(presentationTimeUs: Long): Bitmap {
                val atMs = presentationTimeUs / 1000
                val index = frames.indexOfLast { it.first <= atMs }.coerceAtLeast(0)
                val current = bitmap
                if (index == shown && current != null) return current
                val decoded = BitmapFactory.decodeFile(frames[index].second.absolutePath)
                    ?: return current ?: Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
                val height = (decoded.height * targetWidth.toFloat() / decoded.width)
                    .toInt().coerceAtLeast(1)
                val scaled = Bitmap.createScaledBitmap(decoded, targetWidth, height, true)
                if (scaled !== decoded) decoded.recycle()
                shown = index
                bitmap = scaled
                return scaled
            }
        }
    }
}
