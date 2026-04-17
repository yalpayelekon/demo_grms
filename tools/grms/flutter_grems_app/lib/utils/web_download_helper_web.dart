// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class WebDownloadHelper {
  static void downloadFile(String name, List<int> bytes) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", name)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void printHTML(String htmlContent) {
    final win = html.window.open('', '_blank');
    final dynamic doc = (win as dynamic).document;
    doc.write(htmlContent);
    doc.close();
    (win as dynamic).print();
  }
}
