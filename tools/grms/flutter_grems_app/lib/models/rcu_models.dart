class RcuMenuOption {
  final int id;
  final String label;

  RcuMenuOption({required this.id, required this.label});

  factory RcuMenuOption.fromJson(Map<String, dynamic> json) {
    return RcuMenuOption(
      id: json['id'] as int,
      label: json['label'] as String? ?? '',
    );
  }
}

class RcuMenuResponse {
  final String menuText;
  final List<RcuMenuOption> menuOptions;
  final String outputText;
  final dynamic inputSchema;

  RcuMenuResponse({
    required this.menuText,
    required this.menuOptions,
    required this.outputText,
    this.inputSchema,
  });

  factory RcuMenuResponse.fromJson(Map<String, dynamic> json) {
    return RcuMenuResponse(
      menuText: json['menuText'] as String? ?? '',
      menuOptions:
          (json['menuOptions'] as List<dynamic>?)
              ?.map((e) => RcuMenuOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      outputText: json['outputText'] as String? ?? '',
      inputSchema: json['inputSchema'],
    );
  }
}

class RcuMenuRequest {
  final String roomNumber;
  final int? choice;
  final Map<String, dynamic>? parameters;

  RcuMenuRequest({required this.roomNumber, this.choice, this.parameters});

  Map<String, dynamic> toJson() => {
    'choice': choice,
    if (parameters != null) 'parameters': parameters,
  };
}

class LightingSceneTriggerResponse {
  final int scene;
  final int? group;
  final bool triggered;
  final String source;

  LightingSceneTriggerResponse({
    required this.scene,
    required this.triggered,
    this.group,
    this.source = 'unknown',
  });

  factory LightingSceneTriggerResponse.fromJson(Map<String, dynamic> json) {
    return LightingSceneTriggerResponse(
      scene: (json['scene'] as num?)?.toInt() ?? 0,
      group: (json['group'] as num?)?.toInt(),
      triggered: json['triggered'] as bool? ?? false,
      source: (json['source'] as String?)?.trim().isNotEmpty == true
          ? (json['source'] as String).trim()
          : 'unknown',
    );
  }
}
