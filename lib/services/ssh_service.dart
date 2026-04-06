import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/ssh_config.dart';
import '../models/media_file.dart';

class SSHService {
  SSHClient? _client;
  SSHConfig? _currentConfig;

  bool get isConnected => _client != null;

  Future<bool> connect(SSHConfig config) async {
    try {
      await disconnect();

      final socket = await SSHSocket.connect(config.host, config.port);

      _currentConfig = config;

      if (config.privateKey != null && config.privateKey!.isNotEmpty) {
        final keyPairs = SSHKeyPair.fromPem(
          config.privateKey!,
          config.passphrase,
        );
        _client = SSHClient(
          socket,
          username: config.username,
          identities: keyPairs,
        );
      } else if (config.password != null && config.password!.isNotEmpty) {
        _client = SSHClient(
          socket,
          username: config.username,
          onPasswordRequest: () => config.password!,
        );
      } else {
        throw Exception('需要提供密码或私钥');
      }

      // 测试连接
      await _client!.run('echo ok');
      return true;
    } catch (e) {
      _client = null;
      _currentConfig = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _currentConfig = null;
  }

  Future<List<MediaFile>> listDirectory(String path) async {
    if (_client == null) {
      throw Exception('未连接到服务器');
    }

    try {
      final sftp = await _client!.sftp();
      final items = await sftp.listdir(path);
      
      final files = <MediaFile>[];
      for (final item in items) {
        // 跳过 . 和 ..
        if (item.filename == '.' || item.filename == '..') continue;
        
        final isDirectory = item.attr?.isDirectory ?? false;
        final size = item.attr?.size;
        final filePath = path.endsWith('/') ? '$path${item.filename}' : '$path/${item.filename}';
        
        files.add(isDirectory
            ? MediaFile.directory(filePath, item.filename)
            : MediaFile.file(filePath, item.filename, size: size));
      }
      
      sftp.close();
      return files;
    } catch (e) {
      throw Exception('列出目录失败: $e');
    }
  }

  Future<List<int>> readFile(String path) async {
    if (_client == null) {
      throw Exception('未连接到服务器');
    }

    try {
      final sftp = await _client!.sftp();
      debugPrint('📡 SFTP 读取文件: $path');
      final file = await sftp.open(path);

      // 读取整个文件内容
      final content = await file.readBytes();

      file.close();
      sftp.close();
      
      debugPrint('📡 读取成功，大小: ${content.length ~/ 1024} KB');
      return content;
    } catch (e) {
      debugPrint('❌ SFTP 读取文件失败: $e');
      throw Exception('读取文件失败: $e');
    }
  }

  Future<int?> getFileSize(String path) async {
    if (_client == null) {
      throw Exception('未连接到服务器');
    }

    try {
      final sftp = await _client!.sftp();
      final attrs = await sftp.stat(path);
      sftp.close();
      return attrs?.size;
    } catch (e) {
      return null;
    }
  }

  SSHConfig? get currentConfig => _currentConfig;
}
