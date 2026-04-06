import 'dart:io';
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

  /// 流式下载文件到本地（支持边下边播）
  /// [progressCallback] 回调函数，参数为已下载的字节数和总字节数
  Future<void> downloadFileStreaming({
    required String remotePath,
    required String localPath,
    Function(int downloaded, int total)? progressCallback,
  }) async {
    if (_client == null) {
      throw Exception('未连接到服务器');
    }

    SftpFile? file;
    SftpClient? sftp;

    try {
      debugPrint('📡 开始流式下载: $remotePath');
      sftp = await _client!.sftp();
      file = await sftp.open(remotePath);

      // 获取文件总大小
      final attrs = await file.stat();
      final totalSize = attrs.size ?? 0;
      debugPrint('📁 文件总大小: ${(totalSize ~/ 1024 ~/ 1024)} MB');

      // 打开本地文件
      final localFile = File(localPath);
      final sink = localFile.openWrite(mode: FileMode.write);

      // 分块读取（每块 64KB）
      const chunkSize = 64 * 1024;
      int downloaded = 0;
      int position = 0;

      while (downloaded < totalSize) {
        final remaining = totalSize - downloaded;
        final toRead = remaining < chunkSize ? remaining : chunkSize;
        
        // 读取一块数据
        final chunk = await file.readBytes(length: toRead.toInt(), offset: position);

        if (chunk.isEmpty) {
          break; // 文件读取完成
        }

        // 写入本地文件并立即刷新到磁盘
        sink.add(chunk);
        await sink.flush(); // 关键：确保数据写入磁盘，播放器可以读取
        position += chunk.length;
        downloaded += chunk.length;

        // 回调进度
        progressCallback?.call(downloaded, totalSize);
      }

      // 关闭写入器
      await sink.close();
      await file.close();
      sftp.close();

      debugPrint('✅ 流式下载完成: $localPath');
    } catch (e) {
      debugPrint('❌ 流式下载失败: $e');
      // 确保资源被释放
      try {
        await file?.close();
        sftp?.close();
      } catch (_) {}
      rethrow;
    }
  }

  /// 获取 SSH 客户端（用于流式服务）
  SSHClient? getClient() => _client;

  SSHConfig? get currentConfig => _currentConfig;
}
