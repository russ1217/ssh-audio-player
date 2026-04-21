# SSH Audio Player

A Flutter-based Android audio player application that supports playing audio files from remote servers via SSH.

## Features

### ✅ Implemented Features

1. **SSH Remote Access**
   - Password authentication support
   - Private key authentication support
   - Multiple server configuration management
   - Browse remote server file directories

2. **Audio Playback**
   - Support for mainstream audio formats: MP3, WAV, FLAC, AAC, OGG, M4A, WMA, OPUS, AIFF
   - Support for extracting and playing audio from video files: MP4, FLV, MKV, AVI, MOV, WMV, WEBM, M4V
   - Background playback support (continues playing when app is in background)

3. **Playback Controls**
   - Play/Pause
   - Stop
   - Fast forward (10 seconds)
   - Rewind (10 seconds)
   - Progress bar seeking
   - Previous/Next track

4. **Playlist Management**
   - Add single files to playlist
   - Add entire directories to playlist
   - Sequential playback of directory files
   - Save playlists to local database
   - Persistent playlist storage

5. **Sleep Timer**
   - Time-based timer (15min, 30min, 1hr, 2hr, 3hr, 6hr)
   - File count-based timer
   - Cancel timer at any time

6. **UI Features**
   - Material Design 3 style
   - Light/Dark theme support (follows system)
   - Bottom playback control bar
   - File browser interface
   - Playlist management interface
   - SSH configuration management interface

7. **Advanced Features**
   - Media notification with playback controls
   - Network monitoring and auto-reconnection
   - Smart pre-download optimization
   - Cache management
   - Battery optimization handling
   - Playback position restoration

## Tech Stack

- **Flutter** - Cross-platform UI framework
- **Dart** - Programming language
- **dartssh2** - SSH client library
- **just_audio** - Audio playback
- **audio_service** - Background audio service
- **sqflite** - Local SQLite database
- **provider** - State management
- **path_provider** - System path access
- **uuid** - Unique ID generation

## Project Structure

```
lib/
├── main.dart                    # Application entry point
├── models/                      # Data models
│   ├── ssh_config.dart         # SSH configuration model
│   ├── media_file.dart         # Media file model
│   └── playlist.dart           # Playlist model
├── services/                    # Service layer
│   ├── ssh_service.dart        # SSH connection service
│   ├── audio_player_service.dart  # Audio playback service
│   ├── database_service.dart   # Database service
│   └── timer_service.dart      # Timer service
├── providers/                   # State management
│   └── app_provider.dart       # Global state management
├── screens/                     # Screens
│   ├── home_screen.dart        # Home and file browser
│   ├── playlist_screen.dart    # Playlist screen
│   └── ssh_config_screen.dart  # SSH configuration screen
└── widgets/                     # UI components
    ├── file_list_item.dart     # File list item
    └── bottom_player_bar.dart  # Bottom playback control bar
```

## Requirements

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- Android SDK (Minimum API 21, Target API 34)
- JDK 11+

## Installation & Build

### 1. Install Flutter

Refer to the official documentation: https://flutter.dev/docs/get-started/install

### 2. Get Dependencies

```bash
flutter pub get
```

### 3. Run the App

```bash
flutter run
```

### 4. Build APK

```bash
flutter build apk --release
```

The APK will be generated at: `build/app/outputs/flutter-apk/app-release.apk`

## Usage Guide

### Configure SSH Server

1. Open the app and navigate to SSH Configuration
2. Click "Add Server"
3. Enter server details:
   - **Name**: A friendly name for the server
   - **Host**: Server IP address or domain
   - **Port**: SSH port (default: 22)
   - **Username**: SSH username
   - **Authentication Method**: Password or Private Key
   - **Password/Key**: Enter password or paste private key content
4. Save the configuration
5. Test the connection

### Browse and Play Files

1. Select a configured server from the home screen
2. Browse through directories to find audio files
3. Tap on a file to start playback
4. Use the bottom control bar to control playback

### Manage Playlist

1. Long press on a file or directory to add to playlist
2. Navigate to the Playlist tab to view saved playlists
3. Create new playlists or manage existing ones
4. Play files in sequence from the playlist

### Set Sleep Timer

1. Tap the timer icon in the playback controls
2. Choose time duration or file count
3. The app will automatically stop playback when timer expires

## Advanced Documentation

For detailed technical documentation, see:

- [Background Playback](BACKGROUND_PLAYBACK.md) - Background playback implementation
- [Media Control Notification](MEDIA_CONTROL_NOTIFICATION.md) - Notification controls
- [Network Monitor](NETWORK_MONITOR.md) - Network monitoring and reconnection
- [Playlist Enhancement](PLAYLIST_ENHANCEMENT.md) - Playlist features
- [Local File Playback](LOCAL_FILE_PLAYBACK.md) - Local file support
- [Development Guide](DEVELOPMENT.md) - Development notes

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Verify SSH credentials are correct
   - Check network connectivity
   - Ensure SSH service is running on the server
   - Verify firewall allows SSH connections

2. **No Sound**
   - Check device volume settings
   - Ensure audio focus is not taken by another app
   - Try restarting the app

3. **Playback Stuttering**
   - Check network stability
   - Reduce predownload limit in settings
   - Try lower quality audio files

4. **App Crashes**
   - Clear app cache and data
   - Reinstall the app
   - Check Android version compatibility

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is open source. See LICENSE file for details.

## Author

- **Russ Rao** - russ.rao@outlook.com
- GitHub: [@russ1217](https://github.com/russ1217)

## Acknowledgments

Thanks to the following open source projects:

- [Flutter](https://flutter.dev/)
- [just_audio](https://pub.dev/packages/just_audio)
- [audio_service](https://pub.dev/packages/audio_service)
- [dartssh2](https://pub.dev/packages/dartssh2)
