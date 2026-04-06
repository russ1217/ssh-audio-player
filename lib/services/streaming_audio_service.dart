import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';

/// 本地 HTTP 流式音频服务
/// 将 SFTP 远程文件通过 HTTP 流式传输给 just_audio
class StreamingAudioService {
  HttpServer? _server;
  SSHClient? _streamingSshClient; // 独立的 SSH 连接用于流式传输
  int? _port;

  /// 启动流式服务并返回播放 URL
  /// [sshClient] SSH 客户端连接
  /// [remotePath] 远程文件路径
  /// [fileSize] 文件大小（可选，会自动获取）
  /// [sshConfig] SSH 配置（用于创建独立的流式连接）
  Future<String> startStreaming({
    required SSHClient sshClient,
    required String remotePath,
    required Future<SSHClient> Function() createNewSshClient, // 工厂函数：创建新的 SSH 连接
    int? fileSize,
  }) async {
    // 停止之前的服务
    await stop();

    // 创建独立的 SSH 连接用于流式传输
    _streamingSshClient = await createNewSshClient();
    debugPrint('🔗 流式服务独立 SSH 连接已建立');

    // 在随机端口启动 HTTP 服务器
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('🌐 HTTP 流式服务启动在端口 $_port');

    final streamingClient = _streamingSshClient!;

    // 处理请求
    _server!.listen((request) async {
      await _handleHttpRequest(request, streamingClient, remotePath, fileSize);
    });

    final url = 'http://127.0.0.1:$_port/stream';
    debugPrint('🔗 流式播放 URL: $url');
    return url;
  }

  /// 停止流式服务
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      debugPrint('🛑 HTTP 流式服务已停止');
    }
    if (_streamingSshClient != null) {
      _streamingSshClient!.close();
      _streamingSshClient = null;
      debugPrint('🛑 流式 SSH 连接已关闭');
    }
  }

  Future<void> _handleHttpRequest(
    HttpRequest request,
    SSHClient sshClient,
    String remotePath,
    int? fileSize,
  ) async {
    // 解析 Range 请求头（支持 seek）
    int startByte = 0;
    int? endByte;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d+)(?:-(\d*))?').firstMatch(rangeHeader);
      if (match != null) {
        startByte = int.parse(match.group(1)!);
        final endStr = match.group(2);
        if (endStr != null && endStr.isNotEmpty) {
          endByte = int.parse(endStr);
        }
      }
    }

    debugPrint('📡 HTTP 请求: Range: bytes=$startByte-${endByte ?? ""}');

    // 获取文件大小
    final totalSize = fileSize ?? await _getFileSize(sshClient, remotePath);

    if (endByte == null) {
      endByte = totalSize - 1;
    }

    final contentLength = endByte! - startByte + 1;

    // 设置响应头（支持 Range 请求）
    if (rangeHeader != null) {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $startByte-$endByte/$totalSize',
      );
      request.response.headers.set(
        HttpHeaders.acceptRangesHeader,
        'bytes',
      );
    } else {
      request.response.headers.set(
        HttpHeaders.acceptRangesHeader,
        'bytes',
      );
    }

    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _getContentType(remotePath),
    );
    request.response.headers.set(
      HttpHeaders.contentLengthHeader,
      contentLength.toString(),
    );

    // 从 SFTP 读取并流式传输
    SftpClient? sftp;
    SftpFile? file;
    try {
      sftp = await sshClient.sftp();
      file = await sftp.open(remotePath);

      const bufferSize = 64 * 1024; // 64KB
      int position = startByte;
      int remaining = contentLength;

      while (remaining > 0) {
        final toRead = remaining < bufferSize ? remaining : bufferSize;
        final chunk = await file.readBytes(length: toRead, offset: position);

        if (chunk.isEmpty) break;

        request.response.add(chunk);
        await request.response.flush();

        position += chunk.length;
        remaining -= chunk.length;
      }
    } catch (e) {
      debugPrint('❌ SFTP 流式传输失败: $e');
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await file?.close();
        sftp?.close();
      } catch (_) {}
    }

    await request.response.close();
  }

  Future<int> _getFileSize(SSHClient sshClient, String remotePath) async {
    SftpClient? sftp;
    try {
      sftp = await sshClient.sftp();
      final attrs = await sftp.stat(remotePath);
      return attrs?.size ?? 0;
    } finally {
      try {
        sftp?.close();
      } catch (_) {}
    }
  }

  String _getContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
      case 'm4a':
        return 'audio/mp4';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'wma':
        return 'audio/x-ms-wma';
      default:
        return 'audio/mpeg';
    }
  }
}
