// lib/step_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'step_service.dart';

class StepPage extends StatefulWidget {
  @override
  _StepPageState createState() => _StepPageState();
}

class _StepPageState extends State<StepPage> {
  final StepService _service = StepService();

  int todaySteps = 0;
  StreamSubscription<StepCount>? _subscription;

  @override
  void initState() {
    super.initState();
    loadTodaySteps();
    startPolling();
    startStepStream();
  }

  Future<void> loadTodaySteps() async {
    int steps = await _service.getTodaySteps();
    setState(() => todaySteps = steps);
  }

  // 每 10 秒讀一次 HealthKit / Google Fit 的正式步數
  void startPolling() {
    Timer.periodic(Duration(seconds: 10), (_) {
      loadTodaySteps();
    });
  }

  // 即時 pedometer stream（用來讓 UI 有即時感）
  void startStepStream() {
    _subscription = _service.getStepStream().listen((StepCount event) {
      setState(() {
        todaySteps = todaySteps + 1; // 表示 UI 有變動
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("今日步數")),
      body: Center(
        child: Text(
          "$todaySteps 步",
          style: TextStyle(fontSize: 40),
        ),
      ),
    );
  }
}
