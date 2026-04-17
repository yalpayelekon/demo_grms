import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> exportCsv(String fileName, String contents) async {
  final bytes = utf8.encode(contents);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'));
  final url = web.URL.createObjectURL(blob);
  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}
