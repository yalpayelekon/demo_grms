import 'fullscreen_helper_stub.dart'
    if (dart.library.html) 'fullscreen_helper_web.dart' as fullscreen_impl;

class FullscreenHelper {
  static bool isFullscreen() => fullscreen_impl.isFullscreen();

  static Future<void> toggle() => fullscreen_impl.toggle();
}
