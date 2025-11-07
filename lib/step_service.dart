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

  final permissions = types.map((e) => HealthDataAccess.READ).toList();

  bool granted = await _health.requestAuthorization(types, permissions: permissions);
  if (!granted) return 0;

  final data = await _health.getHealthDataFromTypes(
    startTime: start,
    endTime: now,
    types: types,
  );

  int totalSteps = 0;

  for (var item in data) {
    final value = item.value;
    if (value is NumericHealthValue) {
      totalSteps += value.numericValue?.toInt() ?? 0;
    }
  }

  return totalSteps;
}


  // 即時步數 Stream （pedometer）
  Stream<StepCount> getStepStream() {
    return Pedometer.stepCountStream;
  }
}
