package isKey.app.tursaf

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.onesignal.OneSignal
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // FLAG_SECURE bayrağını kaldır - ekran görüntüsü almaya izin ver
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            val mainChannel = NotificationChannel(
                "de874a32-5881-4403-8cdb-bd5a7ce62ea0",
                "chat_messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Sohbet mesaj bildirimleri"
                enableLights(true)
                lightColor = Color.BLUE
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                
                setAllowBubbles(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(mainChannel)

            val defaultChannel = NotificationChannel(
                "OS_DEFAULT_CHANNEL",
                "Varsayılan Bildirimler",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Genel bildirimler"
                enableLights(true)
                lightColor = Color.BLUE
                enableVibration(true)
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(defaultChannel)
        }

        OneSignal.initWithContext(this)
    }
} 