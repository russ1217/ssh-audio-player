class SSHConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase;
  final String? initialPath;

  SSHConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.initialPath = '/',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'initialPath': initialPath,
    };
  }

  factory SSHConfig.fromMap(Map<String, dynamic> map) {
    return SSHConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      host: map['host'] as String,
      port: map['port'] as int? ?? 22,
      username: map['username'] as String,
      password: map['password'] as String?,
      privateKey: map['privateKey'] as String?,
      passphrase: map['passphrase'] as String?,
      initialPath: map['initialPath'] as String? ?? '/',
    );
  }

  SSHConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? passphrase,
    String? initialPath,
  }) {
    return SSHConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      initialPath: initialPath ?? this.initialPath,
    );
  }
}
