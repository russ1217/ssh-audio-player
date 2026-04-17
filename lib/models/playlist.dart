class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<PlaylistItem> items;
  final DateTime? lastPlayed;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
    this.lastPlayed,
  });

  Playlist copyWith({
    String? name,
    List<PlaylistItem>? items,
    DateTime? lastPlayed,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      items: items ?? this.items,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'lastPlayed': lastPlayed?.toIso8601String(),
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['createdAt']),
      items: (map['items'] as List<dynamic>)
          .map((item) => PlaylistItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      lastPlayed: map['lastPlayed'] != null ? DateTime.parse(map['lastPlayed']) : null,
    );
  }
}

class PlaylistItem {
  final String sshConfigId;
  final String filePath;
  final String fileName;
  final DateTime addedAt;

  PlaylistItem({
    required this.sshConfigId,
    required this.filePath,
    required this.fileName,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sshConfigId': sshConfigId,
      'filePath': filePath,
      'fileName': fileName,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory PlaylistItem.fromMap(Map<String, dynamic> map) {
    return PlaylistItem(
      sshConfigId: map['sshConfigId'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      addedAt: DateTime.parse(map['addedAt']),
    );
  }
}
