package club.apptester.client

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Reads the build catalogue from one instance.
 *
 * This client never writes a build. Those arrive through the `atc` command on
 * the machine that compiled them, which is the only place the signing material
 * exists.
 */

data class Build(
    val shareToken: String,
    val version: String,
    val buildNumber: String,
    val fileName: String,
    val fileSize: Long,
    val notes: String?,
    val userNote: String?,
    val platform: String,
    val createdAt: Long,
    val installDirectUrl: String,
) {
    val shortSize: String
        get() {
            val mb = fileSize / 1_048_576.0
            return if (mb < 1) "${fileSize / 1024} KB" else String.format(Locale.US, "%.1f MB", mb)
        }

    val relativeAge: String get() = ago(createdAt)

    /** Only an APK can be installed from an Android phone. */
    val installable: Boolean get() = platform == "android"
}

data class CatalogApp(
    val slug: String,
    val name: String,
    val platform: String,
    val packageName: String?,
    val iconUrl: String?,
    val builds: List<Build>,
) {
    val latest: Build? get() = builds.firstOrNull()

    val platformLabel: String get() = when (platform) {
        "android" -> "Android"
        "ios" -> "iOS"
        "macos" -> "macOS"
        else -> platform.replaceFirstChar { it.uppercase() }
    }
}

/**
 * "just now", then "2 minutes ago", "3 days ago".
 *
 * The first minute is special-cased: a relative formatter reading "in 0
 * seconds" for a build that just landed is both wrong in tense and useless.
 */
fun ago(millis: Long): String {
    val seconds = (System.currentTimeMillis() - millis) / 1000
    return when {
        seconds < 60 -> "just now"
        seconds < 3600 -> plural(seconds / 60, "minute")
        seconds < 86_400 -> plural(seconds / 3600, "hour")
        seconds < 2_592_000 -> plural(seconds / 86_400, "day")
        else -> plural(seconds / 2_592_000, "month")
    }
}

private fun plural(n: Long, unit: String) = "$n $unit${if (n == 1L) "" else "s"} ago"

/**
 * A string field, or null.
 *
 * org.json does not treat JSON null the way you would hope: optString on a null
 * value hands back the literal string "null", which then renders as
 * "Note: null" on screen. Every optional string goes through here instead.
 */
private fun JSONObject.stringOrNull(key: String): String? {
    if (isNull(key)) return null
    val value = optString(key)
    return value.ifEmpty { null }
}

sealed class ApiError(message: String) : Exception(message) {
    object Unauthorized : ApiError("That server rejected the token. Check it in Settings.")
    object Offline : ApiError("Could not reach the server.")
    class Status(code: Int) : ApiError("The server returned $code.")
}

class Api(private val server: Server) {

    fun apps(): List<CatalogApp> {
        val body = get("api/builds")
        val apps = JSONObject(body).getJSONArray("apps")
        return (0 until apps.length()).map { i ->
            val a = apps.getJSONObject(i)
            val builds = a.getJSONArray("builds")
            CatalogApp(
                slug = a.getString("slug"),
                name = a.getString("name"),
                platform = a.optString("platform", "unknown"),
                packageName = a.stringOrNull("bundleId"),
                iconUrl = a.stringOrNull("iconUrl"),
                builds = (0 until builds.length()).map { j ->
                    val b = builds.getJSONObject(j)
                    Build(
                        shareToken = b.getString("shareToken"),
                        version = b.getString("version"),
                        buildNumber = b.getString("buildNumber"),
                        fileName = b.stringOrNull("fileName") ?: "",
                        fileSize = b.optLong("fileSize"),
                        notes = b.stringOrNull("notes"),
                        userNote = b.stringOrNull("userNote"),
                        platform = a.optString("platform", "unknown"),
                        createdAt = iso(b.stringOrNull("createdAt") ?: ""),
                        installDirectUrl = b.stringOrNull("installDirectURL") ?: "",
                    )
                },
            )
        }
    }

    /** Adds or replaces the note on a build. The server appends, newest wins. */
    fun saveNote(text: String, build: Build) {
        val url = URL(server.url.trimEnd('/') + "/api/builds/${build.shareToken}/note")
        (url.openConnection() as HttpURLConnection).run {
            requestMethod = "POST"
            setRequestProperty("Authorization", "Bearer ${server.token}")
            setRequestProperty("Content-Type", "application/json")
            doOutput = true
            outputStream.use { it.write(JSONObject().put("text", text).toString().toByteArray()) }
            val code = responseCode
            disconnect()
            if (code == 401) throw ApiError.Unauthorized
            if (code !in 200..299) throw ApiError.Status(code)
        }
    }

    private fun get(path: String): String {
        val url = URL(server.url.trimEnd('/') + "/" + path)
        val conn = try {
            (url.openConnection() as HttpURLConnection).apply {
                setRequestProperty("Authorization", "Bearer ${server.token}")
                setRequestProperty("Accept", "application/json")
                connectTimeout = 15_000
                readTimeout = 20_000
            }
        } catch (e: Exception) { throw ApiError.Offline }

        try {
            val code = try { conn.responseCode } catch (e: Exception) { throw ApiError.Offline }
            if (code == 401) throw ApiError.Unauthorized
            if (code !in 200..299) throw ApiError.Status(code)
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private companion object {
        fun iso(text: String): Long {
            if (text.isEmpty()) return 0L
            // The API emits ISO-8601 in UTC. Fractional seconds are optional,
            // so both shapes are tried rather than assuming one.
            for (pattern in arrayOf("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'")) {
                try {
                    val f = SimpleDateFormat(pattern, Locale.US)
                    f.timeZone = TimeZone.getTimeZone("UTC")
                    return (f.parse(text) ?: Date(0)).time
                } catch (_: Exception) { }
            }
            return 0L
        }
    }
}
