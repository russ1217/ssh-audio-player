import 'dart:async';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/ssh_config.dart';
import '../models/media_file.dart';

class SSHService {
  SSHClient? _client;
  SftpClient? _sftp; // 复用的 SFTP 连接
  SSHConfig? _currentConfig;
  Timer? _heartbeatTimer;
  
  // 心跳检测相关
  static const heartbeatIntervalNormal = Duration(seconds: 15); // ✅ 缩短间隔以快速检测VPN断开
  static const heartbeatIntervalDisconnected = Duration(seconds: 5); // ✅ 断开后更快重试
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  bool get isConnected => _client != null;

  int _reconnectAttempts = 0;
  // ✅ 移除最大重试次数限制，改为持续周期性检测

  /// 启动心跳检测
  void startHeartbeat() {
    stopHeartbeat();
    _reconnectAttempts = 0;
    _startHeartbeatTimer(heartbeatIntervalNormal);
  }

  void _startHeartbeatTimer(Duration interval) {
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      if (_client != null) {
        final isConnected = await checkConnection();
        if (!isConnected) {
          debugPrint('⚠️ 心跳检测：SSH 连接已断开');
          _connectionStatusController.add(false);

          // ✅ 关键修改：持续尝试重连，不限制次数
          if (_currentConfig != null) {
            _reconnectAttempts++;
            debugPrint('🔄 心跳检测：尝试自动重连 (第 $_reconnectAttempts 次)...');
            try {
              final reconnectSuccess = await reconnect().timeout(
                const Duration(seconds: 20),
                onTimeout: () {
                  throw TimeoutException('重连超时');
                },
              );
              _connectionStatusController.add(reconnectSuccess);
              if (reconnectSuccess) {
                debugPrint('✅ 心跳检测：自动重连成功（共尝试 $_reconnectAttempts 次）');
                _reconnectAttempts = 0; // 重置重试计数
                // 重连成功后，恢复正常心跳间隔
                _startHeartbeatTimer(heartbeatIntervalNormal);
              } else {
                debugPrint('❌ 心跳检测：自动重连失败，将在 ${heartbeatIntervalDisconnected.inSeconds} 秒后重试...');
                // 重连失败，使用快速心跳间隔继续重试
                _startHeartbeatTimer(heartbeatIntervalDisconnected);
              }
            } catch (e) {
              debugPrint('❌ 心跳检测：重连异常 - $e，将在 ${heartbeatIntervalDisconnected.inSeconds} 秒后重试...');
              _connectionStatusController.add(false);
              // 重连异常，使用快速心跳间隔继续重试
              _startHeartbeatTimer(heartbeatIntervalDisconnected);
            }
          } else {
            debugPrint('⚠️ 心跳检测：无 SSH 配置，无法重连');
            _connectionStatusController.add(false);
          }
        } else {
          _reconnectAttempts = 0; // 重置重试计数
          _connectionStatusController.add(true);
        }
      }
    });
    
    final intervalType = interval == heartbeatIntervalNormal ? '正常' : '快速';
    debugPrint('💓 SSH 心跳检测已启动（${intervalType}模式：${interval.inSeconds}秒，将持续重试直到成功）');
  }

  /// 停止心跳检测
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 检查连接是否真正有效
  Future<bool> checkConnection() async {
    if (_client == null) return false;
    try {
      await _client!.run('echo ok');
      return true;
    } catch (e) {
      debugPrint('⚠️ SSH 连接已断开: $e');
      _client = null;
      _sftp = null;
      return false;
    }
  }

  /// 重新连接（使用当前配置）
  Future<bool> reconnect() async {
    if (_currentConfig == null) return false;
    debugPrint('🔄 正在重新连接 SSH...');
    await disconnect();
    return connect(_currentConfig!);
  }

  /// ✅ 主动检查SSH连接并立即重连（供外部调用）
  Future<bool> checkAndReconnectIfNeeded() async {
    debugPrint('🔍 主动检查SSH连接状态...');
    
    final isConnected = await checkConnection();
    
    if (!isConnected && _currentConfig != null) {
      debugPrint('⚠️ SSH连接已断开，立即尝试重连...');
      return await reconnect();
    } else if (isConnected) {
      debugPrint('✅ SSH连接正常');
      return true;
    } else {
      debugPrint('⚠️ 无SSH配置，无法重连');
      return false;
    }
  }

  /// 连接到 SSH 服务器
  Future<bool> connect(SSHConfig config) async {
    try {
      await disconnect();

      // 添加连接超时处理（15秒）
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 15),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('SSH 连接超时');
        },
      );

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

      // 测试连接（带超时）
      await _client!.run('echo ok').timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('SSH 连接测试超时');
        },
      );

      // 初始化并复用 SFTP 连接
      _sftp = await _client!.sftp();
      debugPrint('🔗 SFTP 会话已建立（复用模式）');

      // 启动心跳检测
      startHeartbeat();

      return true;
    } catch (e) {
      debugPrint('❌ SSH 连接失败: $e');
      _client = null;
      _sftp = null;
      // 注意：不清空 _currentConfig，因为重连需要它
      rethrow;
    }
  }

  Future<void> disconnect() async {
    stopHeartbeat();
    _sftp?.close();
    _sftp = null;
    _client?.close();
    _client = null;
    _currentConfig = null;
  }

  Future<List<MediaFile>> listDirectory(String path) async {
    if (_sftp == null) {
      throw Exception('未连接到服务器');
    }

    try {
      final items = await _sftp!.listdir(path);

      final files = <MediaFile>[];
      for (final item in items) {
        if (item.filename == '.' || item.filename == '..') continue;

        final isDirectory = item.attr?.isDirectory ?? false;
        final size = item.attr?.size;
        final filePath = path.endsWith('/') ? '$path${item.filename}' : '$path/${item.filename}';

        files.add(isDirectory
            ? MediaFile.directory(filePath, item.filename)
            : MediaFile.file(filePath, item.filename, size: size));
      }

      return files;
    } catch (e) {
      debugPrint('❌ 列出目录失败: $e');
      throw Exception('列出目录失败: $e');
    }
  }

  Future<List<int>> readFile(String path) async {
    if (_sftp == null) {
      throw Exception('未连接到服务器');
    }

    SftpFile? file;
    try {
      debugPrint('📡 SFTP 读取文件: $path');
      file = await _sftp!.open(path);

      final content = await file.readBytes();

      debugPrint('📡 读取成功，大小: ${content.length ~/ 1024} KB');
      return content;
    } catch (e) {
      debugPrint('❌ SFTP 读取文件失败: $e');
      throw Exception('读取文件失败: $e');
    } finally {
      try {
        await file?.close();
      } catch (_) {}
    }
  }

  Future<int?> getFileSize(String path) async {
    if (_sftp == null) {
      throw Exception('未连接到服务器');
    }

    try {
      final attrs = await _sftp!.stat(path);
      return attrs?.size;
    } catch (e) {
      debugPrint('❌ 获取文件大小失败: $e');
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

  /// 创建新的 SSH 连接（用于流式服务）
  Future<SSHClient> createNewConnection() async {
    if (_currentConfig == null) {
      throw Exception('没有当前的 SSH 配置');
    }

    final socket = await SSHSocket.connect(_currentConfig!.host, _currentConfig!.port);

    SSHClient client;
    if (_currentConfig!.privateKey != null && _currentConfig!.privateKey!.isNotEmpty) {
      final keyPairs = SSHKeyPair.fromPem(
        _currentConfig!.privateKey!,
        _currentConfig!.passphrase,
      );
      client = SSHClient(
        socket,
        username: _currentConfig!.username,
        identities: keyPairs,
      );
    } else if (_currentConfig!.password != null && _currentConfig!.password!.isNotEmpty) {
      client = SSHClient(
        socket,
        username: _currentConfig!.username,
        onPasswordRequest: () => _currentConfig!.password!,
      );
    } else {
      throw Exception('需要提供密码或私钥');
    }

    // 测试连接
    await client.run('echo ok');
    debugPrint('🔗 新的 SSH 连接已建立（用于流式服务）');
    return client;
  }

  SSHConfig? get currentConfig => _currentConfig;

  /// 释放资源
  void dispose() {
    stopHeartbeat();
    _connectionStatusController.close();
  }
}
