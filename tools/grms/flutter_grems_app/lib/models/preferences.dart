class Preferences {
  const Preferences({
    required this.dateFormat,
    required this.timeFormat,
    required this.city,
  });

  final String dateFormat;
  final String timeFormat;
  final String city;

  static const defaults = Preferences(dateFormat: 'MMM DD, YYYY', timeFormat: '12h', city: 'Antalya');

  Preferences copyWith({String? dateFormat, String? timeFormat, String? city}) => Preferences(
        dateFormat: dateFormat ?? this.dateFormat,
        timeFormat: timeFormat ?? this.timeFormat,
        city: city ?? this.city,
      );

  Map<String, dynamic> toJson() => {
        'dateFormat': dateFormat,
        'timeFormat': timeFormat,
        'city': city,
      };

  factory Preferences.fromJson(Map<String, dynamic> json) => Preferences(
        dateFormat: json['dateFormat'] as String? ?? defaults.dateFormat,
        timeFormat: json['timeFormat'] as String? ?? defaults.timeFormat,
        city: json['city'] as String? ?? defaults.city,
      );
}
