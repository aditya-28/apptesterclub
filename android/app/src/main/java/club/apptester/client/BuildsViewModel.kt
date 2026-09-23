package club.apptester.client

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BuildsViewModel(app: Application) : AndroidViewModel(app) {

    val servers = ServerStore(app)
    val prefs = Preferences(app)
    val installer = Installer(app)

    var apps by mutableStateOf<List<CatalogApp>>(emptyList())
        private set
    var loading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var lastChecked by mutableStateOf(prefs.lastChecked)
        private set

    var platformFilter by mutableStateOf(prefs.platformFilter)
        private set

    /** The platforms this server actually has apps for, so the app never
     *  offers a filter that would empty the screen for no reason. */
    val availablePlatforms: List<String>
        get() = apps.map { it.platform }.distinct().sorted()

    fun choosePlatform(value: String) {
        platformFilter = value
        prefs.platformFilter = value
    }

    /** Bumped whenever a pin or archive changes, so the lists recompose. */
    var revision by mutableStateOf(0)
        private set

    fun refresh() {
        val server = servers.selected
        if (server == null) {
            apps = emptyList()
            error = "No server yet. Add one in Settings."
            return
        }
        if (loading) return
        loading = true
        viewModelScope.launch {
            try {
                val fetched = withContext(Dispatchers.IO) { Api(server).apps() }
                apps = fetched
                error = null
                lastChecked = System.currentTimeMillis()
                prefs.lastChecked = lastChecked
            } catch (e: Exception) {
                error = e.message ?: "Something went wrong."
            } finally {
                loading = false
            }
        }
    }

    fun saveNote(text: String, build: Build, done: (String?) -> Unit) {
        val server = servers.selected ?: return done("No server.")
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { Api(server).saveNote(text, build) }
                refresh()
                done(null)
            } catch (e: Exception) { done(e.message) }
        }
    }

    fun select(server: Server) {
        servers.select(server)
        apps = emptyList()
        refresh()
    }

    fun togglePin(slug: String) {
        prefs.togglePin(servers.selected?.id, slug); revision++
    }

    fun toggleArchive(slug: String) {
        prefs.toggleArchive(servers.selected?.id, slug); revision++
    }

    fun changed() { revision++ }

    fun pinned() = prefs.pinned(servers.selected?.id)
    fun archived() = prefs.archived(servers.selected?.id)
}
