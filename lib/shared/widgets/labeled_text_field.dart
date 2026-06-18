import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labeled text field with consistent styling for the diagnostic forms.
class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helperText,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.numericOnly = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helperText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool numericOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType:
          keyboardType ?? (numericOnly ? TextInputType.number : null),
      inputFormatters:
          numericOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
