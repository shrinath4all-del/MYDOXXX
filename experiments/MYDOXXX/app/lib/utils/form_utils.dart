import 'package:flutter/material.dart';

/// Form helpers.
class FormUtils {
  FormUtils._();

  /// Validates the form and, if a field has an error, scrolls to the first
  /// one so the user can see what to fix (a plain `validate()` leaves a field
  /// that is off-screen unseen).
  static bool validate(GlobalKey<FormState> key) {
    final form = key.currentState;
    if (form == null) return true;
    final ok = form.validate();
    if (ok) return true;

    Element? first;
    void visit(Element e) {
      if (first != null) return;
      if (e is StatefulElement) {
        final s = e.state;
        if (s is FormFieldState && s.hasError) {
          first = e;
          return;
        }
      }
      e.visitChildren(visit);
    }

    key.currentContext?.visitChildElements(visit);
    final target = first;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    return false;
  }
}
