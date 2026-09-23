package club.apptester.client

import android.content.Context

/**
 * Pins and archives, per server.
 *
 * Keyed by server so the same app slug on two instances does not share a pin,
 * which would be surprising the first time a client's build vanished from the
 * main list because of something you did on your own.
 */
class Preferences(context: Context) {
    private val prefs = context.getSharedPreferences("prefs", Context.MODE_PRIVATE)

    private fun key(serverId: String?, kind: String) = "${serverId ?: "none"}.$kind"

    fun pinned(serverId: String?): Set<String> =
        prefs.getStringSet(key(serverId, "pinned"), emptySet()) ?: emptySet()

    fun archived(serverId: String?): Set<String> =
        prefs.getStringSet(key(serverId, "archived"), emptySet()) ?: emptySet()

    fun togglePin(serverId: String?, slug: String) = toggle(key(serverId, "pinned"), slug)

    fun toggleArchive(serverId: String?, slug: String) = toggle(key(serverId, "archived"), slug)

    private fun toggle(k: String, slug: String) {
        val current = (prefs.getStringSet(k, emptySet()) ?: emptySet()).toMutableSet()
        if (!current.add(slug)) current.remove(slug)
        // A new set instance is required: SharedPreferences does not copy the
        // set it is handed, so mutating the returned one and putting it back
        // can silently write nothing.
        prefs.edit().putStringSet(k, HashSet(current)).apply()
    }

    /**
     * Which platform's apps to show.
     *
     * Defaults to Android, because this is the Android client and an iOS build
     * is something it can list but never install. Showing everything by default
     * would fill the first screen with rows whose only honest button is "you
     * cannot install this here".
     */
    var platformFilter: String
        get() = prefs.getString("platformFilter", "android") ?: "android"
        set(value) = prefs.edit().putString("platformFilter", value).apply()

    var lastChecked: Long
        get() = prefs.getLong("lastChecked", 0L)
        set(value) = prefs.edit().putLong("lastChecked", value).apply()
}
