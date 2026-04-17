{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    useLocalCanvasKit: true,
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
