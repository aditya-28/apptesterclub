package club.apptester.client

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArchiveScreen(model: BuildsViewModel, onBack: () -> Unit) {
    // Filtered on every recomposition from the live catalogue rather than from
    // a list captured when the screen opened: restoring something should empty
    // this screen immediately, not on the next visit.
    val archived = model.archived()
    val apps = model.apps.filter { archived.contains(it.slug) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Archive", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        if (apps.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Nothing archived.",
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
            return@Scaffold
        }
        LazyColumn(Modifier.padding(padding), contentPadding = PaddingValues(16.dp)) {
            items(apps, key = { it.slug }) { app ->
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(app.name, fontWeight = FontWeight.Medium)
                        Text(app.latest?.let { "${it.version} (${it.buildNumber})" } ?: app.platformLabel,
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    // A visible button, not a swipe: a screen you visit rarely
                    // is the worst place to hide the only way out of it.
                    OutlinedButton(onClick = { model.toggleArchive(app.slug) }) { Text("Restore") }
                }
                HorizontalDivider()
            }
        }
    }
}
