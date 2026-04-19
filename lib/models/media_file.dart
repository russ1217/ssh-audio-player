// ✅ 新增：文件来源类型枚举
enum FileSourceType {
  local,  // 本地文件
  ssh,    // SSH远程文件
}

class MediaFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final Duration? duration;
  
  // ✅ 新增：标识文件来源类型
  final FileSourceType sourceType;

  MediaFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modified,
    this.duration,
    this.sourceType = FileSourceType.local, // 默认为本地文件
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
  
  // ✅ 新增：便捷判断是否为SSH远程文件
  bool get isSSHFile => sourceType == FileSourceType.ssh;
  
  // ✅ 新增：便捷判断是否为本地文件
  bool get isLocalFile => sourceType == FileSourceType.local;

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

  factory MediaFile.file(String path, String name, {int? size, DateTime? modified, FileSourceType sourceType = FileSourceType.local}) {
    return MediaFile(
      path: path,
      name: name,
      isDirectory: false,
      size: size,
      modified: modified,
      sourceType: sourceType, // ✅ 新增：支持设置来源类型
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
      'sourceType': sourceType.name, // ✅ 新增：序列化来源类型
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
      sourceType: map['sourceType'] != null 
          ? FileSourceType.values.firstWhere(
              (e) => e.name == map['sourceType'],
              orElse: () => FileSourceType.local, // 兼容旧数据，默认为本地
            )
          : FileSourceType.local, // ✅ 新增：反序列化来源类型
    );
  }
}
