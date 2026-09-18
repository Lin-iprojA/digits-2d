
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'live_2d_screen.dart';

void main() {
  runApp(const TwoDLotteryApp());
}

class TwoDLotteryApp extends StatelessWidget {
  const TwoDLotteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Lottery Simulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.teal, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const MainHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const BettingScreen(),
    const BetsHistoryScreen(),
    const Live2DScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calculate),
            label: 'Keypad & Bet',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Bets & Payouts',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            label: 'Live Draw & Admin',
          ),
        ],
      ),
    );
  }
}

// 1. Betting Screen with Custom Keypad & Burmese Terminology
class BettingScreen extends StatefulWidget {
  const BettingScreen({super.key});

  @override
  State<BettingScreen> createState() => _BettingScreenState();
}

class _BettingScreenState extends State<BettingScreen> {
  final TextEditingController _customerController = TextEditingController(text: 'Mg Mg');
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _amountController = TextEditingController(text: '1000');

  String _selectedBetType = 'Straight (ဒဲ့)';

  final List<Map<String, String>> _betTypes = [
    {'label': 'Straight (ဒဲ့)', 'desc': 'Exact 2-digit match'},
    {'label': 'R (Return)', 'desc': 'Reverses digits (e.g. 12, 21)'},
    {'label': 'Poo (ပူး)', 'desc': 'Specific doubles (e.g. 1 -> 11, 12 -> 11, 22). Leave empty for all (00-99)'},
    {'label': 'Pat Thee (ပတ်သီး)', 'desc': '19 combinations for single digit'},
    {'label': 'Kway Poo (ခွေပူး)', 'desc': 'Permutations of digits including doubles (e.g. 1, 2, 3 -> 9 nums)'},
    {'label': 'Kway (ခွေ)', 'desc': 'Permutations of digits excluding doubles (e.g. 1, 2, 3 -> 6 nums)'},
    {'label': 'Break (ဘရိတ်)', 'desc': 'Digit sum equals target'},
  ];

  Future<void> _submitBet() async {
    final customer = _customerController.text.trim();
    final inputVal = _inputController.text.trim();
    final amountStr = _amountController.text.trim();

    if (customer.isEmpty || inputVal.isEmpty || amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and enter digits/terms')),
      );
      return;
    }

    final amount = double.tryParse(amountStr) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid bet amount')),
      );
      return;
    }

    try {
      final result = await ApiService.submitBet(
        customerName: customer,
        betType: _selectedBetType,
        inputValue: inputVal,
        amount: amount,
      );

      final betData = result['bet'];
      final expanded = (betData['expanded_numbers'] as List).join(', ');

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bet Submitted Successfully!'),
          content: Text(
            'Session: ${betData['session']}\nTime Placed: ${betData['created_at']}\nType: $_selectedBetType\nInput: $inputVal\nExpanded (${(betData['expanded_numbers'] as List).length} nums): $expanded\nAmount per number: $amount MMK\nTotal Amount: ${betData['total_amount']} MMK',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _inputController.clear();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('2D Lottery Betting'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Customer & Amount Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('1. Customer Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customerController,
                                decoration: const InputDecoration(
                                  labelText: 'Customer Name',
                                  prefixIcon: Icon(Icons.person),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Bet Amount (MMK)',
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Bet Type Selector Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('2. Select 2D Bet Type (Terminology)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _betTypes.map((type) {
                            final isSelected = _selectedBetType == type['label'];
                            return ChoiceChip(
                              label: Text(type['label']!),
                              selected: isSelected,
                              showCheckmark: false,
                              selectedColor: Colors.teal.withOpacity(0.2),
                              onSelected: (selected) {
                                setState(() {
                                  _selectedBetType = type['label']!;
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _betTypes.firstWhere((t) => t['label'] == _selectedBetType)['desc']!,
                                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey[800]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Display Input Field (Standard GBoard Number Keyboard)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('3. Enter Keypad Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _inputController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: _selectedBetType.contains('Kway') || _selectedBetType.contains('Poo') ? 10 : (_selectedBetType.contains('Pat Thee') ? 1 : 2),
                          decoration: InputDecoration(
                            labelText: 'Input Numbers Here',
                            counterText: '', // Hide the length counter if you want, or remove this line to show it
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _inputController.clear();
                              },
                            ),
                          ),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Submit Button
                ElevatedButton.icon(
                  onPressed: _submitBet,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit Bet to Admin (Bookmaker)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 2. Bets History & Payouts Screen
class BetsHistoryScreen extends StatefulWidget {
  const BetsHistoryScreen({super.key});

  @override
  State<BetsHistoryScreen> createState() => _BetsHistoryScreenState();
}

class _BetsHistoryScreenState extends State<BetsHistoryScreen> {
  List<dynamic> _bets = [];
  bool _isLoading = false;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _fetchBets();
  }

  Future<void> _fetchBets() async {
    setState(() => _isLoading = true);
    try {
      final bets = await ApiService.getBets(includeArchived: _showArchived);
      setState(() {
        _bets = bets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading bets: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submitted Bets & Automated Payouts'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBets,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Active Round Bets'),
                selected: !_showArchived,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _showArchived = false);
                    _fetchBets();
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('All History (Archived)'),
                selected: _showArchived,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _showArchived = true);
                    _fetchBets();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bets.isEmpty
                    ? const Center(
                        child: Text(
                          'No bets for this filter.\nGo to Keypad tab to place bets!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchBets,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: ListView.builder(
                              itemCount: _bets.length,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              itemBuilder: (context, index) {
                                final bet = _bets[index];
                                final isWin = bet['win_status'] == 'Win';
                                final isLose = bet['win_status'] == 'Lose';

                                Color statusColor = Colors.orange;
                                if (isWin) statusColor = Colors.green;
                                if (isLose) statusColor = Colors.red;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '#${bet['id']} - ${bet['customer_name']}',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                Text(
                                                  'Session: ${bet['session'] ?? 'Active'}',
                                                  style: TextStyle(color: Colors.teal[800], fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            Chip(
                                              label: Text(
                                                bet['win_status'],
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                              backgroundColor: statusColor,
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 20),
                                        Text('Time Placed: ${bet['created_at'] ?? 'N/A'}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                                        const SizedBox(height: 4),
                                        Text('Bet Type: ${bet['bet_type']}', style: TextStyle(color: Colors.grey[800])),
                                        const SizedBox(height: 4),
                                        Text('Input: ${bet['input_value']}', style: TextStyle(color: Colors.grey[800])),
                                        const SizedBox(height: 4),
                                        Text('Expanded Numbers: ${(bet['expanded_numbers'] as List).join(', ')}', style: TextStyle(color: Colors.grey[800])),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isWin ? Colors.green.withOpacity(0.1) : (isLose ? Colors.red.withOpacity(0.05) : Colors.grey.withOpacity(0.1)),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Total Bet: ${bet['total_amount']} MMK', style: const TextStyle(fontWeight: FontWeight.w500)),
                                              Text(
                                                'Payout: ${bet['payout']} MMK ${isWin ? "(Win x80)" : ""}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: isWin ? Colors.green[700] : Colors.black87,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}


