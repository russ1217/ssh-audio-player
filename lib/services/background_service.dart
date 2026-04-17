import 'package:flutter/services.dart';

class BackgroundService {
  static const MethodChannel _channel = MethodChannel('com.example.player/background_service');

  /// Starts the foreground service to keep SSH and Playback alive
  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startService');
    } on PlatformException catch (e) {
      print("Failed to start service: '${e.message}'.");
    }
  }

  /// Stops the foreground service
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print("Failed to stop service: '${e.message}'.");
    }
  }
}