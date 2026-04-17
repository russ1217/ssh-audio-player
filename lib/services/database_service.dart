import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/ssh_config.dart';

class DatabaseService {
  static const _sshConfigsKey = 'ssh_configs';
  static const _playlistsKey = 'playlists';
  static const _playHistoryKey = 'play_history';
  static const _currentPlaylistKey = 'current_playlist';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ========== SSH 配置 CRUD ==========

  Future<List<SSHConfig>> getSSHConfigs() async {
    final prefs = await this.prefs;
    final data = prefs.getStringList(_sshConfigsKey) ?? [];
    return data
        .map((e) => SSHConfig.fromMap(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> insertSSHConfig(SSHConfig config) async {
    final configs = await getSSHConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configs[index] = config;
    } else {
      configs.add(config);
    }
    await _saveSSHConfigs(configs);
  }

  Future<void> updateSSHConfig(SSHConfig config) async {
    final configs = await getSSHConfigs();
    final index = configs.indexWhere((c) => c.id == config.id);
    if (index >= 0) {
      configs[index] = config;
      await _saveSSHConfigs(configs);
    }
  }

  Future<void> deleteSSHConfig(String id) async {
    final configs = await getSSHConfigs();
    configs.removeWhere((c) => c.id == id);
    await _saveSSHConfigs(configs);
  }

  Future<void> _saveSSHConfigs(List<SSHConfig> configs) async {
    final prefs = await this.prefs;
    await prefs.setStringList(
      _sshConfigsKey,
      configs.map((c) => jsonEncode(c.toMap())).toList(),
    );
  }

  // ========== 播放列表 CRUD ==========

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await this.prefs;
    final data = prefs.getStringList(_playlistsKey) ?? [];
    return data
        .map((e) => Playlist.fromMap(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlists = await getPlaylists();
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      items: [],
    );
    playlists.add(playlist);
    await _savePlaylists(playlists);
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = await getPlaylists();
    playlists.removeWhere((p) => p.id == id);
    await _savePlaylists(playlists);
  }

  Future<void> updatePlaylistName(String id, String name) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == id);
    if (index >= 0) {
      playlists[index] = playlists[index].copyWith(name: name);
      await _savePlaylists(playlists);
    }
  }

  Future<void> _savePlaylists(List<Playlist> playlists) async {
    final prefs = await this.prefs;
    await prefs.setStringList(
      _playlistsKey,
      playlists.map((p) => jsonEncode(p.toMap())).toList(),
    );
  }

  // ========== 播放列表项 CRUD ==========

  Future<List<PlaylistItem>> getPlaylistItems(String playlistId) async {
    final playlists = await getPlaylists();
    final playlist = playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(
        id: '',
        name: '',
        createdAt: DateTime.now(),
        items: [],
      ),
    );
    return playlist.items;
  }

  Future<void> addPlaylistItem(String playlistId, PlaylistItem item) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      playlists[index] = playlists[index].copyWith(
        items: [...playlists[index].items, item],
      );
      await _savePlaylists(playlists);
    }
  }

  Future<void> addPlaylistItems(String playlistId, List<PlaylistItem> items) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      playlists[index] = playlists[index].copyWith(
        items: [...playlists[index].items, ...items],
      );
      await _savePlaylists(playlists);
    }
  }

  Future<void> removePlaylistItem(String playlistId, String itemId) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final updatedItems = playlists[index].items.where((i) => i.sshConfigId != itemId).toList();
      playlists[index] = playlists[index].copyWith(items: updatedItems);
      await _savePlaylists(playlists);
    }
  }

  Future<void> reorderPlaylistItem(String playlistId, int oldIndex, int newIndex) async {
    final playlists = await getPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      final items = List<PlaylistItem>.from(playlists[index].items);
      if (oldIndex < items.length && newIndex < items.length) {
        final item = items.removeAt(oldIndex);
        items.insert(newIndex, item);
        playlists[index] = playlists[index].copyWith(items: items);
        await _savePlaylists(playlists);
      }
    }
  }

  // ========== 当前播放列表（内存中） ==========

  Future<void> saveCurrentPlaylist(List<Map<String, dynamic>> playlist) async {
    final prefs = await this.prefs;
    await prefs.setString(_currentPlaylistKey, jsonEncode(playlist));
  }

  Future<List<Map<String, dynamic>>> getCurrentPlaylist() async {
    final prefs = await this.prefs;
    final data = prefs.getString(_currentPlaylistKey);
    if (data == null) return [];
    final list = jsonDecode(data) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  // ========== 播放历史 ==========

  Future<void> addPlayHistory({
    required String sshConfigId,
    required String filePath,
    required String fileName,
    int position = 0,
    int? duration,
  }) async {
    final prefs = await this.prefs;
    final history = prefs.getStringList(_playHistoryKey) ?? [];
    final entry = jsonEncode({
      'sshConfigId': sshConfigId,
      'filePath': filePath,
      'fileName': fileName,
      'playedAt': DateTime.now().toIso8601String(),
      'position': position,
      'duration': duration,
    });
    history.insert(0, entry);
    // 只保留最近 100 条
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }
    await prefs.setStringList(_playHistoryKey, history);
  }

  Future<List<Map<String, dynamic>>> getPlayHistory({int limit = 50}) async {
    final prefs = await this.prefs;
    final history = prefs.getStringList(_playHistoryKey) ?? [];
    return history
        .take(limit)
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
  }

  Future<void> clearPlayHistory() async {
    final prefs = await this.prefs;
    await prefs.remove(_playHistoryKey);
  }

  Future<void> close() async {
    // SharedPreferences 不需要关闭
  }
}
