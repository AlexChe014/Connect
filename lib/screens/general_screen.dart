import 'package:flutter/material.dart';

import '../config/app_icons.dart';
import 'bookings_screen.dart';
import 'news_feed_screen.dart';

/// Общая страница с вкладками «Новости» и «Бронирование».
class GeneralScreen extends StatelessWidget {
  const GeneralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Общая'),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Новости', icon: AppIcon(AppIcons.news)),
              Tab(text: 'Бронирование', icon: AppIcon(AppIcons.bookings)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            NewsFeedScreen(showAppBar: false),
            BookingsScreen(showAppBar: false),
          ],
        ),
      ),
    );
  }
}
