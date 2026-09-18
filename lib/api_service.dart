import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'stock_model.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.contains('vercel.app') || host.contains('onrender.com') || host.contains('github.io')) {
        return 'https://digits-2d-backend.onrender.com';
      }
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return 'http://$host:8000';
      }
      return 'http://localhost:8000';
    }
    return 'https://digits-2d-backend.onrender.com';
  }

  static Future<Map<String, dynamic>> submitBet({
    required String customerName,
    required String betType,
    required String inputValue,
    required double amount,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/bets'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'customer_name': customerName,
        'bet_type': betType,
        'input_value': inputValue,
        'amount': amount,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to submit bet');
    }
  }

  static Future<List<dynamic>> getBets({bool includeArchived = false}) async {
    final response = await http.get(Uri.parse('$baseUrl/api/bets?include_archived=$includeArchived'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['bets'];
    } else {
      throw Exception('Failed to load bets');
    }
  }

  static Future<List<dynamic>> getArchives() async {
    final response = await http.get(Uri.parse('$baseUrl/api/archives'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['archives'];
    } else {
      throw Exception('Failed to load archives');
    }
  }

  static Future<Map<String, dynamic>> getDraw() async {
    final response = await http.get(Uri.parse('$baseUrl/api/draw'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load draw data');
    }
  }

  static Future<Map<String, dynamic>> setDraw(String winningNumber) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/draw'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'winning_number': winningNumber}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(jsonDecode(response.body)['detail'] ?? 'Failed to set draw');
    }
  }
}

class ThaiStockApiService {
  static const String _baseUrl = 'https://api.thaistock2d.com/live';

  static Future<StockModel> fetchLiveStock() async {
    try {
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return StockModel.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch live data: $e');
    }
  }
}
