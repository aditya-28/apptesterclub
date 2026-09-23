package club.apptester.client

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BuildsScreen(
    model: BuildsViewModel,
    onOpenApp: (CatalogApp) -> Unit,
    onSettings: () -> Unit,
    onArchive: () -> Unit,
) {
    var pickingServer by remember { mutableStateOf(false) }
    val revision = model.revision

    val pinned = remember(model.apps, revision) { model.pinned() }
    val archived = remember(model.apps, revision) { model.archived() }

    val filter = model.platformFilter
    val visible = remember(model.apps, revision, filter) {
        model.apps
            .filterNot { archived.contains(it.slug) }
            .filter { filter == "all" || it.platform == filter }
    }
    val pinnedApps = remember(visible, revision) { visible.filter { pinned.contains(it.slug) } }
    val rest = remember(visible, revision) { visible.filterNot { pinned.contains(it.slug) } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Builds", fontWeight = FontWeight.SemiBold) },
                actions = {
                    // The server this list belongs to, named, and a way to
                    // switch without going through Settings first.
                    TextButton(onClick = { pickingServer = true }) {
                        Text(model.servers.selected?.displayName ?: "No server", maxLines = 1)
                        Icon(Icons.Default.ArrowDropDown, contentDescription = "Choose server")
                    }
                    IconButton(onClick = onSettings) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {

            // Kept at the top: the answer to "is this list current?" should be
            // readable without scrolling to the bottom of it.
            CheckRow(model)

            PlatformFilter(model)

            if (model.error != null && model.apps.isEmpty()) {
                Message(model.error!!)
            } else if (model.apps.isEmpty() && !model.loading) {
                Message("No builds yet. Push one with the atc command and it appears here.")
            } else if (visible.isEmpty() && !model.loading) {
                // Distinguishes "nothing here" from "nothing matches", which
                // otherwise reads as an empty server and sends people hunting
                // for a problem that is a filter.
                Message(
                    if (filter == "android") "No Android builds on this server yet. " +
                        "Its iOS builds are hidden by the filter above."
                    else "Nothing matches that filter."
                )
            }

            LazyColumn(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (pinnedApps.isNotEmpty()) {
                    item { SectionHeader("Pinned") }
                    items(pinnedApps, key = { it.slug }) {
                        AppRow(it, model, onOpenApp)
                    }
                    item { SectionHeader("Everything else") }
                }
                items(rest, key = { it.slug }) {
                    AppRow(it, model, onOpenApp)
                }
                if (archived.isNotEmpty()) {
                    item {
                        TextButton(onClick = onArchive, modifier = Modifier.padding(top = 8.dp)) {
                            Icon(Icons.Default.Archive, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text("Archive (${archived.size})")
                        }
                    }
                }
            }
        }
    }

    if (pickingServer) {
        ServerPicker(model, onDismiss = { pickingServer = false }, onManage = {
            pickingServer = false; onSettings()
        })
    }
}

@Composable
private fun CheckRow(model: BuildsViewModel) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            if (model.loading) "Checking…"
            else if (model.lastChecked == 0L) "Not checked yet"
            else "Last checked ${ago(model.lastChecked)}",
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        )
        Spacer(Modifier.weight(1f))
        TextButton(onClick = { model.refresh() }, enabled = !model.loading) {
            Text("Check now")
        }
    }
    if (model.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
}

/**
 * Android, iOS, everything.
 *
 * Only offered when the server actually has more than one platform: a filter
 * with a single option is furniture.
 */
@Composable
private fun PlatformFilter(model: BuildsViewModel) {
    val available = model.availablePlatforms
    if (available.size < 2) return

    val options = available + "all"
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { option ->
            val selected = model.platformFilter == option
            FilterChip(
                selected = selected,
                onClick = { model.choosePlatform(option) },
                label = {
                    Text(
                        when (option) {
                            "android" -> "Android"
                            "ios" -> "iOS"
                            "macos" -> "macOS"
                            "all" -> "All"
                            else -> option.replaceFirstChar { it.uppercase() }
                        },
                        fontSize = 13.sp,
                    )
                },
            )
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
        modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
    )
}

@Composable
private fun Message(text: String) {
    Text(
        text,
        fontSize = 13.sp,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
        modifier = Modifier.padding(16.dp),
    )
}

@Composable
private fun AppRow(app: CatalogApp, model: BuildsViewModel, onOpen: (CatalogApp) -> Unit) {
    val build = app.latest
    val state = remember(app, model.revision) { model.installer.state(app, build) }

    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth().clickable { onOpen(app) },
    ) {
        Row(
            Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    when (app.platform) {
                        "android" -> Icons.Default.Android
                        "ios" -> Icons.Default.PhoneIphone
                        else -> Icons.Default.Apps
                    },
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(app.name, fontWeight = FontWeight.Medium, fontSize = 15.sp)
                    if (state is InstallState.UpdateAvailable) {
                        Spacer(Modifier.width(6.dp))
                        Box(Modifier.size(8.dp).clip(CircleShape).background(Palette.danger))
                    }
                }
                Text(
                    if (build == null) app.platformLabel
                    else "${app.platformLabel} · ${build.version} (${build.buildNumber}) · ${build.relativeAge}",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
            StateBadge(state)
        }
    }
}

@Composable
private fun StateBadge(state: InstallState) {
    val (text, colour) = when (state) {
        is InstallState.UpdateAvailable -> "Update" to Palette.danger
        InstallState.UpToDate -> "Installed" to Palette.success
        InstallState.NotInstalled -> "Install" to Palette.accent
        is InstallState.Newer -> "Older" to Palette.warning
        InstallState.NotForThisPhone -> "" to Palette.accent
    }
    if (text.isEmpty()) return
    Text(
        text,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        color = colour,
        modifier = Modifier.padding(start = 8.dp),
    )
}
