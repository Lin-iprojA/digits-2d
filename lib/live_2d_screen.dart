import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'stock_model.dart';

class Live2DScreen extends StatefulWidget {
  const Live2DScreen({super.key});

  @override
  State<Live2DScreen> createState() => _Live2DScreenState();
}

class _Live2DScreenState extends State<Live2DScreen> {
  Timer? _timer;
  StockModel? _stockData;
  bool _isLoadingLive = true;
  String _errorMessage = '';

  Map<String, dynamic> _drawData = {'winning_number': null, 'status': 'Waiting for draw'};
  final TextEditingController _winningController = TextEditingController();
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _fetchLiveUpdate();
    _fetchBackendDraw();

    // Poll every 5 seconds for live market data
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchLiveUpdate();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _winningController.dispose();
    super.dispose();
  }

  bool _shouldAutoPublish() {
    final nowUtc = DateTime.now().toUtc();
    final mmTime = nowUtc.add(const Duration(hours: 6, minutes: 30));
    final session = _drawData['session'] ?? '';
    final isMorning = session.contains('Morning');

    if (isMorning) {
      // Morning Draw Target: 12:01 PM MMT
      if (mmTime.hour > 12 || (mmTime.hour == 12 && mmTime.minute >= 1)) {
        return true;
      }
    } else {
      // Evening Draw Target: 04:30 PM (16:30) MMT
      if (mmTime.hour > 16 || (mmTime.hour == 16 && mmTime.minute >= 30)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _fetchLiveUpdate() async {
    try {
      final data = await ThaiStockApiService.fetchLiveStock();
      if (mounted) {
        setState(() {
          _stockData = data;
          _isLoadingLive = false;
          _errorMessage = '';
        });

        // Automatically publish live 2D as final winning number ONLY when target draw time is reached
        final live2d = _stockData?.derived2D;
        if (live2d != null && live2d != '--' && _drawData['winning_number'] == null && !_isPublishing) {
          if (_shouldAutoPublish()) {
            _autoPublishDraw(live2d);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLive = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _fetchBackendDraw() async {
    try {
      final data = await ApiService.getDraw();
      if (mounted) {
        setState(() {
          _drawData = data;
        });

        final live2d = _stockData?.derived2D;
        if (live2d != null && live2d != '--' && _drawData['winning_number'] == null && !_isPublishing) {
          if (_shouldAutoPublish()) {
            _autoPublishDraw(live2d);
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching draw: $e');
    }
  }

  Future<void> _autoPublishDraw(String winningNum) async {
    _isPublishing = true;
    try {
      final result = await ApiService.setDraw(winningNum);
      if (mounted) {
        setState(() {
          _drawData = result['draw'];
          _isPublishing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Automatic Draw Published: Winning 2D ($winningNum)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  Future<void> _manualTriggerDraw() async {
    final winningNum = _winningController.text.trim();
    if (winningNum.length != 2 || !RegExp(r'^\d+$').hasMatch(winningNum)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter exactly a 2-digit winning number (00-99)')),
      );
      return;
    }

    setState(() => _isPublishing = true);
    try {
      final result = await ApiService.setDraw(winningNum);
      if (mounted) {
        setState(() {
          _drawData = result['draw'];
          _isPublishing = false;
          _winningController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Manual Winning Number ($winningNum) Published!'),
            backgroundColor: Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ThaiStock 2D', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A), // Dark Navy Blue
        foregroundColor: Colors.white,
        centerTitle: false,
        actions: const [
          Icon(Icons.info_outline, color: Colors.white),
          SizedBox(width: 12),
          Icon(Icons.calendar_month, color: Colors.white),
          SizedBox(width: 12),
          Icon(Icons.access_time, color: Colors.white),
          SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Thai Stock Market Card & Session Slots
                _buildLiveStockCard(),
                
                const SizedBox(height: 20),

                // Admin Control & Auto-Publish Status Card
                _buildAdminCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveStockCard() {
    final winningNum = _drawData['winning_number'];
    final backendSession = _drawData['session'] ?? '';
    final isMorning = backendSession.contains('Morning');

    // Official API session 2D numbers
    final morningApi2D = _stockData?.morningResult?.twoD;
    final eveningApi2D = _stockData?.eveningResult?.twoD;

    String display2D = '--';
    if (winningNum != null) {
      display2D = winningNum.toString();
    } else if (isMorning && morningApi2D != null && morningApi2D != '--') {
      display2D = morningApi2D;
    } else if (!isMorning && eveningApi2D != null && eveningApi2D != '--') {
      display2D = eveningApi2D;
    } else {
      display2D = _stockData?.derived2D ?? '--';
    }

    final todayStr = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD
    
    // Freeze the timestamp at exact cutoff time if drawn, else format clean time
    String updatedTimeStr = '';
    if (winningNum != null) {
      if (isMorning) {
        updatedTimeStr = '$todayStr 12:01:00';
      } else {
        updatedTimeStr = '$todayStr 16:30:00';
      }
    } else {
      String rawTime = _stockData?.time ?? '12:01:00';
      if (rawTime.contains(todayStr)) {
        updatedTimeStr = rawTime;
      } else {
        updatedTimeStr = '$todayStr $rawTime';
      }
    }

    return Column(
      children: [
        // Giant 2D Number Display
        Text(
          display2D,
          style: const TextStyle(
            fontSize: 110,
            fontWeight: FontWeight.bold,
            height: 1.0,
            letterSpacing: -2,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),

        // Updated Status Badge with Green Checkmark
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check, color: Colors.green, size: 20),
            const SizedBox(width: 6),
            Text(
              'Updated: $updatedTimeStr',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 4 Session Cards (11:00 AM, 12:01 PM, 03:00 PM, 04:30 PM)
        _buildSessionCardsList(display2D, isMorning, winningNum != null),
      ],
    );
  }

  Widget _buildSessionCardsList(String current2D, bool isMorning, bool isDrawn) {
    final results = _stockData?.results ?? [];

    SessionResult? res11 = results.length > 0 ? results[0] : null;
    SessionResult? res12 = results.length > 1 ? results[1] : null;
    SessionResult? res15 = results.length > 2 ? results[2] : null;
    SessionResult? res16 = results.length > 3 ? results[3] : null;

    return Column(
      children: [
        _buildSessionCard(
          res11?.title ?? '11:00 AM',
          res11?.setIndex ?? '--',
          res11?.setValue ?? '--',
          res11?.twoD ?? '--',
        ),
        _buildSessionCard(
          res12?.title ?? '12:01 PM',
          res12?.setIndex ?? (isMorning ? (_stockData?.setIndex ?? '--') : '--'),
          res12?.setValue ?? (isMorning ? (_stockData?.setValue ?? '--') : '--'),
          res12?.twoD != null && res12!.twoD != '--'
              ? res12.twoD
              : (isMorning ? current2D : '--'),
        ),
        _buildSessionCard(
          res15?.title ?? '03:00 PM',
          res15?.setIndex ?? '--',
          res15?.setValue ?? '--',
          res15?.twoD ?? '--',
        ),
        _buildSessionCard(
          res16?.title ?? '04:30 PM',
          res16?.setIndex ?? (!isMorning ? (_stockData?.setIndex ?? '--') : '--'),
          res16?.setValue ?? (!isMorning ? (_stockData?.setValue ?? '--') : '--'),
          res16?.twoD != null && res16!.twoD != '--'
              ? res16.twoD
              : (!isMorning ? current2D : '--'),
        ),
      ],
    );
  }

  Widget _buildSessionCard(String title, String setVal, String valueVal, String twodVal) {
    return Card(
      color: const Color(0xFF3B82F6), // ThaiStock 2D Accent Blue
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Divider(color: Colors.white30, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Set', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(setVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Value', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(valueVal, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                Column(
                  children: [
                    const Text('2D', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      twodVal,
                      style: const TextStyle(
                        color: Color(0xFFFFD700), // Highlighted Yellow 2D
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminCard() {
    final winningNum = _drawData['winning_number'];
    final status = _drawData['status'];
    final backendSession = _drawData['session'] ?? 'Active Session';
    final liveDerived2D = _stockData?.derived2D ?? '--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      'Automated Live Draw Control',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Chip(
                  label: Text(
                    winningNum != null ? 'Result: $winningNum' : status,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  backgroundColor: winningNum != null ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Schedule & Auto-Publish Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: winningNum != null ? Colors.green.withOpacity(0.08) : Colors.teal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: winningNum != null ? Colors.green.withOpacity(0.3) : Colors.teal.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        winningNum != null ? Icons.check_circle : Icons.autorenew,
                        color: winningNum != null ? Colors.green : Colors.teal,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          winningNum != null
                              ? 'Session Complete ($winningNum)'
                              : 'Auto-Publish Active ($liveDerived2D)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: winningNum != null ? Colors.green[800] : Colors.teal[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Active Target: $backendSession\n'
                    'မနက်ပိုင်း ၁၂:၀၁:၀၀ နာရီ နှင့် ညနေပိုင်း ၀၄:၃၀:၀၀ နာရီ အချိန်များတွင် Derived 2D Number ကို အလိုအလျောက် ထုတ်ပြန်ပေးပါမည်။',
                    style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Optional Manual Override', style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 8),

            // Manual Input Row (Optional Override)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _winningController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'Manual 2D Number',
                      counterText: '',
                      prefixIcon: Icon(Icons.casino),
                    ),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isPublishing ? null : _manualTriggerDraw,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  ),
                  child: const Text('Force Manual'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
