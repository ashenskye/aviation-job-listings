// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'web_image_file_picker_stub.dart';

Future<WebImageFile?> pickWebImageFile() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();

  final changeCompleter = Completer<void>();
  void onChange(html.Event _) {
    if (!changeCompleter.isCompleted) {
      changeCompleter.complete();
    }
  }

  input.onChange.first.then(onChange).catchError((_) {
    if (!changeCompleter.isCompleted) {
      changeCompleter.complete();
    }
  });

  await changeCompleter.future;
  if (input.files == null || input.files!.isEmpty) {
    return null;
  }

  final file = input.files!.first;
  final reader = html.FileReader();
  final readCompleter = Completer<Uint8List?>();

  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is Uint8List) {
      readCompleter.complete(result);
      return;
    }
    if (result is ByteBuffer) {
      readCompleter.complete(Uint8List.view(result));
      return;
    }
    readCompleter.complete(null);
  });

  reader.onError.listen((_) {
    if (!readCompleter.isCompleted) {
      readCompleter.complete(null);
    }
  });

  reader.readAsArrayBuffer(file);
  final bytes = await readCompleter.future;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  final name = file.name;
  final dotIndex = name.lastIndexOf('.');
  final extension = dotIndex > -1 && dotIndex < name.length - 1
      ? name.substring(dotIndex + 1).toLowerCase()
      : 'png';

  return WebImageFile(name: name, bytes: bytes, extension: extension);
}
