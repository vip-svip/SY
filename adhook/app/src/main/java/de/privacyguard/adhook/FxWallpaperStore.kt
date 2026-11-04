package de.privacyguard.adhook

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Private, bounded wallpaper storage compatible with the original YouLong 10.0.2
 * preference contract: native_wallpaper_prefs / wallpaper_path.
 *
 * The selected document is copied into app-private storage, so FX does not keep
 * a long-lived external URI grant and never writes user images to shared storage.
 */
object FxWallpaperStore {
    private const val PREFS = "native_wallpaper_prefs"
    private const val KEY_PATH = "wallpaper_path"
    private const val MAX_EDGE = 1920
    private const val MAX_SOURCE_PIXELS = 150_000_000L
    private const val JPEG_QUALITY = 85

    @JvmStatic
    fun currentPath(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PATH, null)?.takeIf { it.isNotBlank() } ?: return null
        val file = managedFile(context, raw)
        if (file == null || !file.isFile || file.length() <= 0L) {
            prefs.edit().remove(KEY_PATH).commit()
            return null
        }
        return file.absolutePath
    }

    /**
     * Decode the selected provider URI, scale it to at most 1920 px on the long
     * edge, and atomically publish a JPEG in the app-private files directory.
     */
    @JvmStatic
    @Throws(IOException::class)
    fun saveFromUri(context: Context, uri: Uri): String {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, bounds)
        } ?: throw IOException("无法打开所选图片")

        val sourceWidth = bounds.outWidth
        val sourceHeight = bounds.outHeight
        if (sourceWidth <= 0 || sourceHeight <= 0) throw IOException("所选文件不是有效图片")
        if (sourceWidth.toLong() * sourceHeight.toLong() > MAX_SOURCE_PIXELS) {
            throw IOException("图片分辨率过大，请选择不超过 1.5 亿像素的图片")
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(sourceWidth, sourceHeight, MAX_EDGE)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var decoded = resolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, options)
        } ?: throw IOException("图片解码失败")
        if (decoded.width <= 0 || decoded.height <= 0) {
            decoded.recycle()
            throw IOException("图片尺寸无效")
        }

        val outputSize = scaledDimensions(decoded.width, decoded.height, MAX_EDGE)
        val scaled = if (decoded.width == outputSize.first && decoded.height == outputSize.second) {
            decoded
        } else {
            Bitmap.createScaledBitmap(decoded, outputSize.first, outputSize.second, true).also {
                if (it !== decoded) decoded.recycle()
            }
        }

        val oldPath = currentPath(context)
        val name = "native_wallpaper_${System.currentTimeMillis()}.jpg"
        val target = File(context.filesDir, name)
        val temp = File(context.filesDir, "$name.tmp")
        try {
            FileOutputStream(temp).use { output ->
                if (!scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)) {
                    throw IOException("壁纸 JPEG 编码失败")
                }
                output.flush()
                output.fd.sync()
            }
            if (!temp.renameTo(target)) throw IOException("无法原子保存壁纸文件")
            val saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_PATH, target.absolutePath).commit()
            if (!saved) {
                target.delete()
                throw IOException("壁纸设置写入失败")
            }
            deleteManaged(context, oldPath)
            return target.absolutePath
        } catch (error: Exception) {
            temp.delete()
            if (error is IOException) throw error
            throw IOException("壁纸保存失败", error)
        } finally {
            if (!scaled.isRecycled) scaled.recycle()
        }
    }

    @JvmStatic
    fun clear(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val oldPath = prefs.getString(KEY_PATH, null)
        if (!prefs.edit().remove(KEY_PATH).commit()) return false
        deleteManaged(context, oldPath)
        return true
    }

    /** Load a memory-bounded bitmap for the common six-tab wallpaper layer. */
    @JvmStatic
    fun loadForDisplay(context: Context): Bitmap? {
        val path = currentPath(context) ?: return null
        val file = managedFile(context, path) ?: return null
        return decodeBounded(file, MAX_EDGE)
    }

    /** Small preview for the Settings → Wallpaper dialog. */
    @JvmStatic
    fun loadPreview(context: Context): Bitmap? {
        val path = currentPath(context) ?: return null
        val file = managedFile(context, path) ?: return null
        return decodeBounded(file, 560)
    }

    internal fun scaledDimensions(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
        require(width > 0 && height > 0 && maxEdge > 0)
        val longest = max(width, height)
        if (longest <= maxEdge) return width to height
        val ratio = maxEdge.toDouble() / longest.toDouble()
        return max(1, (width * ratio).roundToInt()) to
            max(1, (height * ratio).roundToInt())
    }

    internal fun sampleSizeFor(width: Int, height: Int, maxEdge: Int): Int {
        require(width > 0 && height > 0 && maxEdge > 0)
        var sample = 1
        val longest = max(width, height)
        while (longest / (sample * 2) >= maxEdge) sample *= 2
        return sample
    }

    private fun decodeBounded(file: File, maxEdge: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight, maxEdge)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath, options) ?: return null
        val size = scaledDimensions(bitmap.width, bitmap.height, maxEdge)
        if (size.first == bitmap.width && size.second == bitmap.height) return bitmap
        return Bitmap.createScaledBitmap(bitmap, size.first, size.second, true).also {
            if (it !== bitmap) bitmap.recycle()
        }
    }

    private fun managedFile(context: Context, path: String?): File? {
        if (path.isNullOrBlank()) return null
        return try {
            val root = context.filesDir.canonicalFile
            val file = File(path).canonicalFile
            if (file.parentFile == root && file.name.startsWith("native_wallpaper_")
                && (file.name.endsWith(".jpg") || file.name.endsWith(".jpeg") || file.name.endsWith(".jpg.tmp") || file.name.endsWith(".jpeg.tmp"))) file
            else null
        } catch (_: IOException) {
            null
        }
    }

    private fun deleteManaged(context: Context, path: String?) {
        managedFile(context, path)?.delete()
    }
}
