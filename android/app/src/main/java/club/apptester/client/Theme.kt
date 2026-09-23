package club.apptester.client

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Accent = Color(0xFF3B82F6)
private val Success = Color(0xFF22C55E)
private val Warning = Color(0xFFF59E0B)
private val Danger = Color(0xFFEF4444)

private val dark = darkColorScheme(
    primary = Accent,
    background = Color(0xFF0B0B0F),
    surface = Color(0xFF15151C),
    surfaceVariant = Color(0xFF1E1E27),
    error = Danger,
)

private val light = lightColorScheme(
    primary = Accent,
    background = Color(0xFFF7F7FA),
    surface = Color(0xFFFFFFFF),
    error = Danger,
)

object Palette {
    val success = Success
    val warning = Warning
    val danger = Danger
    val accent = Accent
}

@Composable
fun AppTesterClubTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) dark else light, content = content)
}
