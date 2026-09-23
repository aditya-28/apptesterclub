package club.apptester.client

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Switching instances without a trip through Settings. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServerPicker(model: BuildsViewModel, onDismiss: () -> Unit, onManage: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(bottom = 24.dp)) {
            Text("Servers", fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))

            model.servers.servers.forEach { server ->
                Row(
                    Modifier.fillMaxWidth()
                        .clickable { model.select(server); onDismiss() }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(server.displayName)
                        Text(server.subtitle, fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    if (model.servers.selected?.id == server.id) {
                        Icon(Icons.Default.Check, contentDescription = null, tint = Palette.accent)
                    }
                }
            }
            TextButton(onClick = onManage, modifier = Modifier.padding(horizontal = 12.dp)) {
                Text("Manage servers")
            }
        }
    }
}
