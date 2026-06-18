package com.example.artnet_app

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a small MethodChannel (`artnet_poc/multicast_lock`) that acquires and
 * releases a Wi-Fi multicast lock.
 *
 * Android frequently drops inbound broadcast/multicast packets to save power
 * unless this lock is held. Art-Net nodes broadcast their ArtPollReply, and
 * mDNS uses multicast, so without the lock discovery can silently receive
 * nothing on some devices. The Dart side (lib/core/network/multicast_lock.dart)
 * acquires the lock while scanning/monitoring and releases it afterwards.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "artnet_poc/multicast_lock"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val wifi = applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            multicastLock = wifi.createMulticastLock("artnet_poc")
                                .apply { setReferenceCounted(false) }
                        }
                        if (multicastLock?.isHeld == false) multicastLock?.acquire()
                        result.success(multicastLock?.isHeld ?: false)
                    }
                    "release" -> {
                        if (multicastLock?.isHeld == true) multicastLock?.release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
