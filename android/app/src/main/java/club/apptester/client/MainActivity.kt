package club.apptester.client

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.*
import androidx.lifecycle.compose.LifecycleResumeEffect

class MainActivity : ComponentActivity() {

    private val model: BuildsViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handlePairing(intent)

        setContent {
            AppTesterClubTheme {
                var route by remember { mutableStateOf<Route>(Route.Builds) }

                // Coming back from the system installer is the moment the
                // answer to "is this installed?" changes, and nothing tells the
                // app that happened except being resumed.
                LifecycleResumeEffect(Unit) {
                    model.changed()
                    onPauseOrDispose { }
                }

                LaunchedEffect(Unit) { model.refresh() }

                when (val r = route) {
                    Route.Builds -> BuildsScreen(
                        model = model,
                        onOpenApp = { route = Route.Detail(it.slug) },
                        onSettings = { route = Route.Settings },
                        onArchive = { route = Route.Archive },
                    )
                    Route.Settings -> SettingsScreen(model) { route = Route.Builds }
                    Route.Archive -> ArchiveScreen(model) { route = Route.Builds }
                    is Route.Detail -> {
                        // Looked up from the live catalogue rather than held as
                        // an object, so a refresh behind this screen shows.
                        val app = model.apps.firstOrNull { it.slug == r.slug }
                        if (app == null) route = Route.Builds
                        else AppDetailScreen(app, model) { route = Route.Builds }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePairing(intent)
    }

    /** A tapped `apptesterclub://pair` link adds the server it names. */
    private fun handlePairing(intent: Intent?) {
        val uri = intent?.data ?: return
        val server = PairingLink.parse(uri)
        if (server == null) {
            if (uri.scheme == "apptesterclub") {
                Toast.makeText(this,
                    "That is not a pairing code, or its address is not HTTPS.",
                    Toast.LENGTH_LONG).show()
            }
            return
        }
        model.servers.add(server)
        model.refresh()
        Toast.makeText(this, "Paired with ${server.displayName}.", Toast.LENGTH_SHORT).show()
    }
}

private sealed class Route {
    object Builds : Route()
    object Settings : Route()
    object Archive : Route()
    data class Detail(val slug: String) : Route()
}
