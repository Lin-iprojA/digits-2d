class SessionResult {
  final String title;
  final String setIndex;
  final String setValue;
  final String twoD;

  SessionResult({
    required this.title,
    required this.setIndex,
    required this.setValue,
    required this.twoD,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    return SessionResult(
      title: json['open_time']?.toString() ?? json['time']?.toString() ?? json['title']?.toString() ?? '--',
      setIndex: json['set']?.toString() ?? '--',
      setValue: json['value']?.toString() ?? '--',
      twoD: json['twod']?.toString() ?? json['2d']?.toString() ?? '--',
    );
  }
}

class StockModel {
  final String setIndex;
  final String setValue;
  final String time;
  final String date;
  final List<SessionResult> results;

  StockModel({
    required this.setIndex,
    required this.setValue,
    required this.time,
    required this.date,
    required this.results,
  });

  factory StockModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> data = json.containsKey('live') ? json['live'] : json;
    
    List<SessionResult> parsedResults = [];
    if (json.containsKey('result') && json['result'] is List) {
      parsedResults = (json['result'] as List)
          .map((item) => SessionResult.fromJson(item))
          .toList();
    }

    return StockModel(
      setIndex: data['set']?.toString() ?? '--',
      setValue: data['value']?.toString() ?? '--',
      time: data['time']?.toString() ?? '--',
      date: data['date']?.toString() ?? data['time']?.toString() ?? '--',
      results: parsedResults,
    );
  }

  // Derive 2D Number:
  // First digit: Last digit of SET Index decimal
  // Second digit: Last digit of Value integer part (before decimal)
  String get derived2D {
    if (setIndex == '--' || setValue == '--' || setIndex.isEmpty || setValue.isEmpty) {
      return '--';
    }
    try {
      String cleanIdx = setIndex.trim().replaceAll(',', '');
      String cleanVal = setValue.trim().replaceAll(',', '');
      
      String firstDigit = cleanIdx.substring(cleanIdx.length - 1);
      
      String secondDigit = '';
      if (cleanVal.contains('.')) {
        List<String> parts = cleanVal.split('.');
        String integerPart = parts[0];
        secondDigit = integerPart.substring(integerPart.length - 1);
      } else {
        secondDigit = cleanVal.substring(cleanVal.length - 1);
      }
      
      if (int.tryParse(firstDigit) != null && int.tryParse(secondDigit) != null) {
        return '$firstDigit$secondDigit';
      }
      return '--';
    } catch (e) {
      return '--';
    }
  }
}
