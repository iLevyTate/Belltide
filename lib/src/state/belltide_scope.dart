import 'package:flutter/widgets.dart';

import 'belltide_controller.dart';

/// Makes the [BelltideController] available to the widget tree and rebuilds
/// dependents when it changes.
class BelltideScope extends InheritedNotifier<BelltideController> {
  const BelltideScope({super.key, required BelltideController controller, required super.child})
    : super(notifier: controller);

  static BelltideController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BelltideScope>();
    assert(scope != null, 'No BelltideScope above this context');
    return scope!.notifier!;
  }

  /// Reads the controller without rebuilding when it changes.
  static BelltideController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BelltideScope>();
    assert(scope != null, 'No BelltideScope above this context');
    return scope!.notifier!;
  }
}
