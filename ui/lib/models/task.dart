class Task {
  Task({
    required this.id,
    required this.url,
    required this.destPath,
    required this.status,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.createdAt,
    required this.updatedAt,
    this.error,
  });

  final String id;
  final String url;
  final String destPath;
  final String status;
  final int totalBytes;
  final int downloadedBytes;
  final int createdAt;
  final int updatedAt;
  final String? error;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return downloadedBytes / totalBytes;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      destPath: json['dest_path']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      totalBytes: _asInt(json['total_bytes']),
      downloadedBytes: _asInt(json['downloaded_bytes']),
      createdAt: _asInt(json['created_at']),
      updatedAt: _asInt(json['updated_at']),
      error: json['error']?.toString(),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
