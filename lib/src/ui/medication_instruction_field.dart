import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Preset choices shown in the medication form.
enum MedicationInstructionOption {
  unspecified('ไม่ระบุ'),
  beforeMeal('ก่อนอาหาร'),
  withMeal('พร้อมอาหาร'),
  afterMeal('หลังอาหาร'),
  bedtime('ก่อนนอน'),
  asDirected('ตามแพทย์สั่ง'),
  custom('อื่น ๆ');

  const MedicationInstructionOption(this.label);

  final String label;

  bool get requiresCustomValue => this == custom;

  String toStoredValue(String customValue) => switch (this) {
    unspecified => '',
    custom => customValue.trim(),
    _ => label,
  };

  static MedicationInstructionOption fromStoredValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return unspecified;

    for (final option in values) {
      if (!option.requiresCustomValue && option.label == normalized) {
        return option;
      }
    }
    return custom;
  }
}

class MedicationInstructionField extends StatelessWidget {
  const MedicationInstructionField({
    super.key,
    required this.value,
    required this.customValueController,
    required this.onChanged,
  });

  final MedicationInstructionOption value;
  final TextEditingController customValueController;
  final ValueChanged<MedicationInstructionOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'วิธีทาน',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MedicationInstructionOption.values
              .map((option) {
                return ChoiceChip(
                  key: ValueKey<String>('instruction-${option.name}'),
                  label: Text(option.label),
                  selected: value == option,
                  onSelected: (_) => onChanged(option),
                );
              })
              .toList(growable: false),
        ),
        if (value.requiresCustomValue) ...[
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('customMedicationInstructionField'),
            controller: customValueController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'ระบุวิธีทาน',
              hintText: 'เช่น หลังอาหารทันที',
              prefixIcon: Icon(Icons.restaurant_outlined),
            ),
            validator: (customValue) =>
                customValue == null || customValue.trim().isEmpty
                ? 'กรุณาระบุวิธีทาน'
                : null,
          ),
        ],
      ],
    );
  }
}
