import 'package:flutter/material.dart';

class NumericKeypad extends StatefulWidget {
  final String title;
  final String initialValue;
  final Function(double) onConfirm;

  const NumericKeypad({
    super.key,
    required this.title,
    this.initialValue = '',
    required this.onConfirm,
  });

  @override
  State<NumericKeypad> createState() => _NumericKeypadState();
}

class _NumericKeypadState extends State<NumericKeypad> {
  late String _currentValue;
  bool _isFirstKey = true;

  @override
  void initState() {
    super.initState();
    // Start with empty if it's the default zero, so first key replaces it
    _currentValue = (widget.initialValue == '0.0' || widget.initialValue == '0.000' || widget.initialValue == '0') ? '' : widget.initialValue;
  }

  void _onKeyPress(String value) {
    setState(() {
      if (value == '⌫') {
        if (_currentValue.isNotEmpty) {
          _currentValue = _currentValue.substring(0, _currentValue.length - 1);
        }
      } else if (value == '.') {
        if (!_currentValue.contains('.')) {
          if (_currentValue.isEmpty) {
            _currentValue = '0.';
          } else {
            _currentValue += value;
          }
        }
      } else {
        // If it's the first key and we have a default/initial value, replace it
        if (_isFirstKey && _currentValue.isNotEmpty && widget.initialValue != '') {
           _currentValue = value;
        } else {
          _currentValue += value;
        }
      }
      _isFirstKey = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 15)),
          Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200, width: 2),
            ),
            child: Text(
              _currentValue.isEmpty ? '0.000' : _currentValue,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 2,
                color: _currentValue.isEmpty ? Colors.grey[400] : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ...['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'].map((key) {
                return _buildKey(key);
              }),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(_currentValue);
              if (val != null) {
                widget.onConfirm(val);
                Navigator.pop(context);
              } else if (_currentValue.isEmpty) {
                widget.onConfirm(0.0);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[800],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Icon(Icons.check, size: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String key) {
    final isAction = key == '⌫' || key == '.';
    return Material(
      color: isAction ? Colors.blueGrey[50] : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _onKeyPress(key),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Center(
            child: Text(
              key,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: key == '⌫' ? Colors.red : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
