import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/page/home/widget/activity_info/activity_info_widget.dart';
import 'package:town_pass/page/home/widget/city_news/city_news_widget.dart';
import 'package:town_pass/page/home/widget/news/news_banner_widget.dart';
import 'package:town_pass/page/home/widget/subscription/subscription_widget.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/step_service.dart';   // ← 新增

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final StepService _stepService = StepService();

  int todaySteps = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSteps();

    // 每 10 秒更新一次步數
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadSteps();
    });
  }

  Future<void> _loadSteps() async {
    final steps = await _stepService.getTodaySteps();
    if (mounted) {
      setState(() => todaySteps = steps);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TPAppBar(
        showLogo: true,
        title: '首頁',
        leading: IconButton(
          icon: Semantics(
            label: '帳戶',
            child: Assets.svg.iconPerson.svg(),
          ),
          onPressed: () => Get.toNamed(TPRoute.account),
        ),
        backgroundColor: TPColors.white,
      ),
      body: CustomScrollView(
        slivers: [
          // 今日步數區塊（加在最上面）
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                "今日步數：$todaySteps",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const _SliverSizedBox(height: 20),
          const SliverToBoxAdapter(child: NewsBannerWidget()),
          const _SliverSizedBox(height: 20),
          const SliverToBoxAdapter(child: ActivityInfoWidget()),
          const _SliverSizedBox(height: 8),
          const SliverToBoxAdapter(child: CityNewsWidget()),
          const _SliverSizedBox(height: 16),
          const SliverToBoxAdapter(child: SubscriptionWidget()),
          const _SliverSizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SliverSizedBox extends StatelessWidget {
  const _SliverSizedBox({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(child: SizedBox(height: height));
  }
}
