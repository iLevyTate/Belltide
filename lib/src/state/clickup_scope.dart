import 'package:flutter/widgets.dart';

import '../clickup/clickup_controller.dart';

class ClickUpScope extends InheritedNotifier<ClickUpController> {
  const ClickUpScope({super.key, required ClickUpController controller, required super.child})
    : super(notifier: controller);

  static ClickUpController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ClickUpScope>();
    assert(scope != null, 'No ClickUpScope above this context');
    return scope!.notifier!;
  }

  static ClickUpController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ClickUpScope>();
    assert(scope != null, 'No ClickUpScope above this context');
    return scope!.notifier!;
  }
}
