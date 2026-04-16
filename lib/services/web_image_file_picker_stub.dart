import 'dart:typed_data';

class WebImageFile {
  const WebImageFile({
    required this.name,
    required this.bytes,
    required this.extension,
  });

  final String name;
  final Uint8List bytes;
  final String extension;
}

Future<WebImageFile?> pickWebImageFile() async {
  return null;
}
