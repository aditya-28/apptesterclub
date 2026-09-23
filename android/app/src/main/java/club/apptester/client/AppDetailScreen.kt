package club.apptester.client

import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppDetailScreen(app: CatalogApp, model: BuildsViewModel, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busyToken by remember { mutableStateOf<String?>(null) }
    var progress by remember { mutableStateOf(0f) }
    var noteFor by remember { mutableStateOf<Build?>(null) }

    val pinned = model.pinned().contains(app.slug)
    val archived = model.archived().contains(app.slug)
    val state = remember(app, model.revision) { model.installer.state(app, app.latest) }
    val installed = remember(app, model.revision) { model.installer.isInstalled(app) }

    fun install(build: Build) {
        if (!model.installer.canInstall()) {
            // Android refuses the install outright without this grant, and it
            // does so with a dialog that does not explain itself, so we send
            // the person straight to the right settings page.
            Toast.makeText(context, "Allow AppTesterClub to install apps, then tap Install again.", Toast.LENGTH_LONG).show()
            context.startActivity(model.installer.installPermissionIntent())
            return
        }
        busyToken = build.shareToken
        progress = 0f
        scope.launch {
            try {
                val file = withContext(Dispatchers.IO) {
                    model.installer.download(build) { p -> progress = p }
                }
                model.installer.install(file)
            } catch (e: Exception) {
                Toast.makeText(context, e.message ?: "Download failed.", Toast.LENGTH_LONG).show()
            } finally {
                busyToken = null
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(app.name, fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { model.togglePin(app.slug) }) {
                        Icon(
                            if (pinned) Icons.Default.PushPin else Icons.Default.PushPin,
                            contentDescription = if (pinned) "Unpin" else "Pin",
                            tint = if (pinned) Palette.accent
                            else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        )
                    }
                    IconButton(onClick = { model.toggleArchive(app.slug); onBack() }) {
                        Icon(
                            if (archived) Icons.Default.Unarchive else Icons.Default.Archive,
                            contentDescription = if (archived) "Restore" else "Archive",
                        )
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Column {
                    Text(
                        app.packageName ?: app.platformLabel,
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    )
                    if (state is InstallState.UpdateAvailable) {
                        Spacer(Modifier.height(4.dp))
                        Text("Version ${state.installed} is on this phone.",
                            fontSize = 12.sp, color = Palette.warning)
                    }
                    if (state is InstallState.Newer) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "This phone has ${state.installed}, which is newer than anything here. " +
                                "Android will refuse to install an older build over it — uninstall first.",
                            fontSize = 12.sp, color = Palette.warning,
                        )
                    }
                    if (app.platform != "android") {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "This is a ${app.platformLabel} app. It is listed so you can see its builds, " +
                                "but it cannot be installed on this phone.",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        )
                    }
                }
            }

            items(app.builds, key = { it.shareToken }) { build ->
                BuildCard(
                    build = build,
                    isLatest = build.shareToken == app.latest?.shareToken,
                    busy = busyToken == build.shareToken,
                    progress = progress,
                    // Open and Uninstall are about the app on the phone, not
                    // about this particular row, so they appear wherever the
                    // package is installed rather than only on the matching
                    // version.
                    installed = installed,
                    isUpdate = state is InstallState.UpdateAvailable &&
                        build.shareToken == app.latest?.shareToken,
                    onInstall = { install(build) },
                    onOpen = {
                        val intent = model.installer.openIntent(app)
                        if (intent != null) context.startActivity(intent)
                        else Toast.makeText(context, "That app has no screen to open.", Toast.LENGTH_SHORT).show()
                    },
                    onUninstall = {
                        model.installer.uninstallIntent(app)?.let { context.startActivity(it) }
                    },
                    onNote = { noteFor = build },
                )
            }
        }
    }

    noteFor?.let { build ->
        NoteSheet(build, model) { noteFor = null }
    }
}

@Composable
private fun BuildCard(
    build: Build,
    isLatest: Boolean,
    busy: Boolean,
    progress: Float,
    installed: Boolean,
    isUpdate: Boolean,
    onInstall: () -> Unit,
    onOpen: () -> Unit,
    onUninstall: () -> Unit,
    onNote: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.surface, shape = RoundedCornerShape(14.dp)) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${build.version} (${build.buildNumber})",
                            fontWeight = FontWeight.Medium, fontSize = 15.sp)
                        if (isLatest) {
                            Spacer(Modifier.width(6.dp))
                            Text("LATEST", fontSize = 10.sp, fontWeight = FontWeight.Bold,
                                color = Palette.accent)
                        }
                    }
                    Text("${build.relativeAge} · ${build.shortSize}",
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                }
            }

            if (!build.notes.isNullOrEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(build.notes, fontSize = 13.sp)
            }
            if (!build.userNote.isNullOrEmpty()) {
                Spacer(Modifier.height(6.dp))
                Text("Note: ${build.userNote}", fontSize = 12.sp, color = Palette.accent)
            }

            Spacer(Modifier.height(12.dp))

            if (busy) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(6.dp))
                Text("Downloading ${(progress * 100).toInt()}%", fontSize = 12.sp)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (build.installable) {
                        // A full-width target: this is the button the whole
                        // screen exists for, and it should be hard to miss.
                        Button(onClick = onInstall, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Default.Download, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text(
                                if (isUpdate) "Update to this version"
                                else if (installed) "Reinstall this version"
                                else "Install this version"
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (installed) {
                            OutlinedButton(onClick = onOpen, modifier = Modifier.weight(1f)) {
                                Icon(Icons.Default.Launch, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Open")
                            }
                            OutlinedButton(onClick = onUninstall) {
                                Icon(Icons.Default.DeleteOutline, contentDescription = "Uninstall",
                                    tint = Palette.danger)
                            }
                        }
                        OutlinedButton(onClick = onNote) {
                            Icon(Icons.Default.EditNote, contentDescription = "Add a note")
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NoteSheet(build: Build, model: BuildsViewModel, onDismiss: () -> Unit) {
    val context: Context = LocalContext.current
    var text by remember { mutableStateOf(build.userNote ?: "") }
    var saving by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(20.dp)) {
            Text("Note on ${build.version} (${build.buildNumber})",
                fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("What should someone know about this build?") },
                minLines = 3,
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = {
                    saving = true
                    model.saveNote(text, build) { error ->
                        saving = false
                        if (error != null) {
                            Toast.makeText(context, error, Toast.LENGTH_LONG).show()
                        } else onDismiss()
                    }
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth(),
            ) { Text(if (saving) "Saving…" else "Save note") }
            Spacer(Modifier.height(20.dp))
        }
    }
}
