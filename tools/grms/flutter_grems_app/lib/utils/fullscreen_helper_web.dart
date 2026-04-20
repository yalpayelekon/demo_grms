// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool isFullscreen() => html.document.fullscreenElement != null;

Future<void> toggle() async {
  if (isFullscreen()) {
    html.document.exitFullscreen();
  } else {
    html.document.documentElement?.requestFullscreen();
  }
}
