class SessionResult {
  final String title;
  final String openTime;
  final String setIndex;
  final String setValue;
  final String twoD;

  SessionResult({
    required this.title,
    required this.openTime,
    required this.setIndex,
    required this.setValue,
    required this.twoD,
  });

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    String rawTime = json['open_time']?.toString() ?? json['time']?.toString() ?? '--';
    
    // Map open_time to friendly 12-hour title
    String displayTitle = rawTime;
    if (rawTime.startsWith('11:00')) {
      displayTitle = '11:00 AM';
    } else if (rawTime.startsWith('12:01')) {
      displayTitle = '12:01 PM';
    } else if (rawTime.startsWith('15:00') || rawTime.startsWith('03:00')) {
      displayTitle = '03:00 PM';
    } else if (rawTime.startsWith('16:30') || rawTime.startsWith('04:30')) {
      displayTitle = '04:30 PM';
    }

    return SessionResult(
      title: displayTitle,
      openTime: rawTime,
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
  final String live2D;
  final List<SessionResult> results;

  StockModel({
    required this.setIndex,
    required this.setValue,
    required this.time,
    required this.date,
    required this.live2D,
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
      live2D: data['twod']?.toString() ?? '--',
      results: parsedResults,
    );
  }

  // Derived 2D Number calculation or official live2D
  String get derived2D {
    if (live2D != '--' && live2D.isNotEmpty && int.tryParse(live2D) != null) {
      return live2D;
    }
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

  // Get official Morning Result (12:01 PM)
  SessionResult? get morningResult {
    try {
      return results.firstWhere((r) => r.openTime.startsWith('12:01'));
    } catch (_) {
      return null;
    }
  }

  // Get official Evening Result (16:30 PM)
  SessionResult? get eveningResult {
    try {
      return results.firstWhere((r) => r.openTime.startsWith('16:30'));
    } catch (_) {
      return null;
    }
  }
}
