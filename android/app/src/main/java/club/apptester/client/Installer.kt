package club.apptester.client

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build as OsBuild
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Downloading a build and handing it to the system installer.
 *
 * This is where Android and iOS genuinely differ. iOS needs a signed manifest
 * and an `itms-services://` URL because the OS fetches the binary itself.
 * Android does the opposite: the app downloads the APK and passes it to the
 * package installer, which means the download is ours to report on, and the
 * "is this already installed?" question has an exact answer rather than the
 * URL-scheme guess iOS is stuck with.
 */

/** What the button should say, worked out from what is actually on the phone. */
sealed class InstallState {
    object NotInstalled : InstallState()
    object UpToDate : InstallState()
    data class UpdateAvailable(val installed: String) : InstallState()
    /** Installed, but the server's build is older than what is on the phone. */
    data class Newer(val installed: String) : InstallState()
    object NotForThisPhone : InstallState()
}

class Installer(private val context: Context) {

    /**
     * Compares the catalogue against the package manager.
     *
     * versionCode is the number Android orders builds by, and it is what the
     * server records as the build number. Comparing names instead would call
     * 1.10 older than 1.9.
     */
    fun state(app: CatalogApp, build: Build?): InstallState {
        if (build == null || !build.installable) return InstallState.NotForThisPhone
        val pkg = app.packageName ?: return InstallState.NotInstalled
        val info = try {
            context.packageManager.getPackageInfo(pkg, 0)
        } catch (e: PackageManager.NameNotFoundException) {
            return InstallState.NotInstalled
        }

        val installed = if (OsBuild.VERSION.SDK_INT >= OsBuild.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
        val offered = build.buildNumber.toLongOrNull()
        val label = info.versionName ?: installed.toString()

        return when {
            offered == null -> InstallState.UpToDate
            offered > installed -> InstallState.UpdateAvailable(label)
            offered < installed -> InstallState.Newer(label)
            else -> InstallState.UpToDate
        }
    }

    /** Whether the package is on this phone at all, whatever its version. */
    fun isInstalled(app: CatalogApp): Boolean {
        val pkg = app.packageName ?: return false
        return try {
            context.packageManager.getPackageInfo(pkg, 0); true
        } catch (e: PackageManager.NameNotFoundException) { false }
    }

    /**
     * Removing a build.
     *
     * Android shows its own confirmation and does the work; this only asks.
     * Worth having next to Install: reinstalling a build that refuses to go
     * over the top, usually because the phone has a newer one, otherwise means
     * a trip to the system settings to find the app and remove it there.
     */
    fun uninstallIntent(app: CatalogApp): Intent? =
        app.packageName?.let {
            Intent(Intent.ACTION_DELETE, Uri.parse("package:$it"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** The launch intent, if the installed app has one. Some have none. */
    fun openIntent(app: CatalogApp): Intent? =
        app.packageName?.let { context.packageManager.getLaunchIntentForPackage(it) }

    /**
     * Android will not let an app install packages until the user has granted
     * it that right in Settings, and the grant is per-app and revocable.
     */
    fun canInstall(): Boolean = context.packageManager.canRequestPackageInstalls()

    fun installPermissionIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"))

    /**
     * Downloads the APK, reporting progress, then hands it to the installer.
     *
     * The file goes to the app's own cache: it is cleaned up with the app, it
     * needs no storage permission, and a half-finished download cannot be
     * mistaken for a real one because it is written to a temporary name and
     * only renamed once complete.
     */
    fun download(build: Build, onProgress: (Float) -> Unit): File {
        val dir = File(context.cacheDir, "builds").apply { mkdirs() }
        val target = File(dir, "${build.shareToken}.apk")
        if (target.exists() && target.length() == build.fileSize && build.fileSize > 0) {
            onProgress(1f)
            return target
        }

        val partial = File(dir, "${build.shareToken}.part")
        val conn = (URL(build.installDirectUrl).openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            connectTimeout = 15_000
            readTimeout = 30_000
        }
        try {
            val code = conn.responseCode
            if (code !in 200..299) throw ApiError.Status(code)
            val total = build.fileSize.takeIf { it > 0 } ?: conn.contentLengthLong

            conn.inputStream.use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var written = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        written += read
                        if (total > 0) onProgress((written.toDouble() / total).toFloat())
                    }
                }
            }
        } finally {
            conn.disconnect()
        }

        if (target.exists()) target.delete()
        if (!partial.renameTo(target)) throw IllegalStateException("could not finish the download")
        onProgress(1f)
        return target
    }

    /**
     * Hands the file to the system installer.
     *
     * A file:// URI is rejected outright on modern Android, so this goes
     * through a FileProvider and grants the installer read access for the life
     * of the intent.
     */
    fun install(file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
