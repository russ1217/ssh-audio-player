class MediaFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final Duration? duration;

  MediaFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
    this.duration,
  });

  bool get isAudio {
    if (isDirectory) return false;
    final ext = _getExtension();
    return ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus', 'aiff'].contains(ext);
  }

  bool get isVideo {
    if (isDirectory) return false;
    final ext = _getExtension();
    return ['mp4', 'flv', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'm4v'].contains(ext);
  }

  bool get isMedia => isAudio || isVideo;

  String _getExtension() {
    return name.split('.').last.toLowerCase();
  }

  factory MediaFile.directory(String path, String name) {
    return MediaFile(
      path: path,
      name: name,
      isDirectory: true,
    );
  }

  factory MediaFile.file(String path, String name, {int? size, DateTime? modified}) {
    return MediaFile(
      path: path,
      name: name,
      isDirectory: false,
      size: size,
      modified: modified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'name': name,
      'isDirectory': isDirectory,
      'size': size,
      'modified': modified?.toIso8601String(),
      'duration': duration?.inMilliseconds,
    };
  }

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
      path: map['path'] as String,
      name: map['name'] as String,
      isDirectory: map['isDirectory'] as bool,
      size: map['size'] as int?,
      modified: map['modified'] != null ? DateTime.parse(map['modified']) : null,
      duration: map['duration'] != null ? Duration(milliseconds: map['duration']) : null,
    );
  }
}
