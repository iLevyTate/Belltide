import 'package:material_ui/material_ui.dart';

import 'state/belltide_controller.dart';
import 'state/belltide_scope.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

class BelltideApp extends StatelessWidget {
  const BelltideApp({super.key, required this.controller});

  final BelltideController controller;

  @override
  Widget build(BuildContext context) {
    return BelltideScope(
      controller: controller,
      child: MaterialApp(
        title: 'Belltide',
        debugShowCheckedModeBanner: false,
        theme: belltideTheme(Brightness.light),
        darkTheme: belltideTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
