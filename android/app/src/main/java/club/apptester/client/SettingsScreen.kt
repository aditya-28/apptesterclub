package club.apptester.client

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(model: BuildsViewModel, onBack: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var renaming by remember { mutableStateOf<Server?>(null) }
    var revision by remember { mutableStateOf(0) }

    val servers = remember(revision) { model.servers.servers }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { Header("Servers") }

            if (servers.isEmpty()) {
                item {
                    Text(
                        "No servers yet. Scan the pairing code on your AppTesterClub instance, " +
                            "or enter the details below.",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    )
                }
            }

            items(servers, key = { it.id }) { server ->
                Row(
                    Modifier.fillMaxWidth()
                        .clickable { model.select(server); revision++ }
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(server.displayName, fontWeight = FontWeight.Medium)
                        Text(server.subtitle, fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    if (model.servers.selected?.id == server.id) {
                        Icon(Icons.Default.Check, contentDescription = "Selected",
                            tint = Palette.accent)
                    }
                    IconButton(onClick = { renaming = server }) {
                        Icon(Icons.Default.Edit, contentDescription = "Rename")
                    }
                    IconButton(onClick = { model.servers.remove(server); revision++; model.refresh() }) {
                        Icon(Icons.Default.Delete, contentDescription = "Remove",
                            tint = Palette.danger)
                    }
                }
                HorizontalDivider()
            }

            item {
                Text(
                    "Several at once is supported: your own instance and a client's, " +
                        "each with its own builds.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }

            item { Header("Add a server") }
            item {
                OutlinedTextField(name, { name = it }, label = { Text("Name (optional)") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true)
            }
            item {
                OutlinedTextField(url, { url = it },
                    label = { Text("https://builds.example.com") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None))
            }
            item {
                OutlinedTextField(token, { token = it }, label = { Text("Access token") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None))
            }
            item {
                Button(
                    onClick = {
                        model.servers.add(Server(name = name.trim(), url = url.trim(), token = token.trim()))
                        name = ""; url = ""; token = ""; revision++
                        model.refresh()
                    },
                    enabled = url.trim().startsWith("https://") && token.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Add server") }
            }
            item {
                Text(
                    "A pairing link from your instance's /pair page also works: open it on this " +
                        "phone and it fills all of this in.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }

            item { Header("About") }
            item {
                Text(
                    "AppTesterClub ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    fontSize = 13.sp,
                )
                Text(
                    "Open source. You built and signed this copy yourself, and it talks only to " +
                        "the servers listed above.",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )
            }
        }
    }

    renaming?.let { server ->
        var text by remember(server.id) { mutableStateOf(server.name) }
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text("Name this server") },
            text = {
                OutlinedTextField(text, { text = it }, singleLine = true,
                    placeholder = { Text(server.subtitle) })
            },
            confirmButton = {
                TextButton(onClick = {
                    model.servers.rename(server, text); renaming = null; revision++
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun Header(text: String) {
    Text(
        text.uppercase(),
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
        modifier = Modifier.padding(top = 14.dp),
    )
}
