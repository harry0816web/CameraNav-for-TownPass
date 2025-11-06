// lib/step_service.dart
import 'dart:async';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';

class StepService {
  final Health _health = Health();

  // 取得今天 00:00 到現在的步數
  Future<int> getTodaySteps() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);

    final types = [HealthDataType.STEPS];

    bool granted = await _health.requestAuthorization(types);
    if (!granted) return 0;

    final data = await _health.getHealthDataFromTypes(
      startTime: start,
      endTime: now,
      types: types,
    );

    int totalSteps = 0;
    for (var item in data) {
      totalSteps += (item.value as num).toInt();
    }

    return totalSteps;
  }

  // 即時步數 Stream （pedometer）
  Stream<StepCount> getStepStream() {
    return Pedometer.stepCountStream;
  }
}
