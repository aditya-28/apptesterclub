package club.apptester.client

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * One AppTesterClub instance this app can talk to.
 *
 * Several at once is deliberate: a contractor needs their own server and a
 * client's side by side, and that is a day-one requirement rather than a later
 * refinement.
 */
data class Server(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String,
    val token: String,
) {
    /** The nickname if one was given, otherwise the host. */
    val displayName: String
        get() = name.ifEmpty { Uri.parse(url).host ?: url }

    val subtitle: String get() = Uri.parse(url).host ?: url
}

/**
 * Servers live in SharedPreferences rather than EncryptedSharedPreferences for
 * now. The token is a capability: it reads one catalogue and can push to one
 * instance. Worth protecting, and moving it is on the roadmap rather than
 * quietly left undone.
 */
class ServerStore(context: Context) {
    private val prefs = context.getSharedPreferences("servers", Context.MODE_PRIVATE)

    // Compose state, not plain fields. A server added by a pairing link arrives
    // outside any composition, and with a plain field nothing recomposes: the
    // server is stored and the screen goes on saying there is none.
    var servers: List<Server> by mutableStateOf(load())
        private set

    var selectedId: String? by mutableStateOf(prefs.getString("selected", null))
        private set

    val selected: Server?
        get() = servers.firstOrNull { it.id == selectedId } ?: servers.firstOrNull()

    fun add(server: Server) {
        val existing = servers.indexOfFirst { it.url.trimEnd('/') == server.url.trimEnd('/') }
        servers = if (existing >= 0) {
            // Re-pairing the same instance replaces it rather than stacking a
            // duplicate, and keeps a nickname the person chose.
            val kept = servers[existing]
            servers.toMutableList().also {
                it[existing] = server.copy(
                    id = kept.id,
                    name = if (kept.name.isNotEmpty()) kept.name else server.name,
                )
            }
        } else servers + server
        selectedId = servers.firstOrNull { it.url.trimEnd('/') == server.url.trimEnd('/') }?.id
        save()
    }

    fun rename(server: Server, name: String) {
        servers = servers.map { if (it.id == server.id) it.copy(name = name.trim()) else it }
        save()
    }

    fun remove(server: Server) {
        servers = servers.filterNot { it.id == server.id }
        if (selectedId == server.id) selectedId = servers.firstOrNull()?.id
        save()
    }

    fun select(server: Server) {
        selectedId = server.id
        save()
    }

    private fun load(): List<Server> {
        val raw = prefs.getString("list", null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Server(o.getString("id"), o.getString("name"), o.getString("url"), o.getString("token"))
            }
        } catch (e: Exception) { emptyList() }
    }

    private fun save() {
        val array = JSONArray()
        servers.forEach {
            array.put(JSONObject()
                .put("id", it.id).put("name", it.name)
                .put("url", it.url).put("token", it.token))
        }
        prefs.edit().putString("list", array.toString()).putString("selected", selectedId).apply()
    }
}

/**
 * Pairing link, as produced by an instance's `/pair` page.
 *
 *     apptesterclub://pair?url=https%3A%2F%2Fbuilds.example.com&token=abc123
 *
 * The same link the iOS client reads, so one QR code serves both phones.
 */
object PairingLink {
    fun parse(uri: Uri): Server? {
        if (uri.scheme != "apptesterclub" || uri.host != "pair") return null
        val url = uri.getQueryParameter("url") ?: return null
        val token = uri.getQueryParameter("token") ?: return null
        if (token.isEmpty()) return null
        // Anything but HTTPS is refused for the same reason iOS refuses it: a
        // build served over plain HTTP is a build anyone on the network can
        // replace.
        if (Uri.parse(url).scheme != "https") return null
        return Server(name = uri.getQueryParameter("name") ?: "", url = url, token = token)
    }
}
