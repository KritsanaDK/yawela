import 'package:flutter/material.dart';

import '../domain/domain.dart';
import 'app_theme.dart';
import 'formatters.dart';
import 'medication_instruction_field.dart';

class MedicationFormPage extends StatefulWidget {
  const MedicationFormPage({super.key, this.initialMedication});

  final Medication? initialMedication;

  @override
  State<MedicationFormPage> createState() => _MedicationFormPageState();
}

class _MedicationFormPageState extends State<MedicationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dosageController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _notesController;

  late List<ReminderTime> _times;
  late Set<int> _weekdays;
  late DateTime _startDate;
  late DateTime? _endDate;
  late int _colorValue;
  late bool _isActive;
  late MedicationInstructionOption _selectedInstruction;

  bool get _isEditing => widget.initialMedication != null;

  @override
  void initState() {
    super.initState();
    final medication = widget.initialMedication;
    _nameController = TextEditingController(text: medication?.name);
    _dosageController = TextEditingController(text: medication?.dosage);
    final String existingInstruction = medication?.instructions.trim() ?? '';
    _selectedInstruction = MedicationInstructionOption.fromStoredValue(
      existingInstruction,
    );
    _instructionsController = TextEditingController(
      text: _selectedInstruction.requiresCustomValue
          ? existingInstruction
          : null,
    );
    _notesController = TextEditingController(text: medication?.notes);
    _times = medication?.reminderTimes.toList() ?? [ReminderTime(8, 0)];
    _weekdays =
        medication?.weekdays.toSet() ??
        {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
          DateTime.sunday,
        };
    _startDate = medication?.startDate ?? DateTime.now();
    _endDate = medication?.endDate;
    _colorValue = medication?.colorValue ?? AppColors.primary.toARGB32();
    _isActive = medication?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickReminderTime({int? editingIndex}) async {
    final isEditing = editingIndex != null;
    final initial = editingIndex == null
        ? _times.isEmpty
              ? ReminderTime(8, 0)
              : _times.last
        : _times[editingIndex];
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: isEditing ? 'แก้ไขเวลาเตือน' : 'เลือกเวลาเตือน',
      cancelText: 'ยกเลิก',
      confirmText: isEditing ? 'บันทึก' : 'เพิ่มเวลา',
      builder: build24HourMediaQuery,
    );
    if (value == null || !mounted) return;

    final reminder = ReminderTime(value.hour, value.minute);
    final hasDuplicate = _times.asMap().entries.any(
      (entry) => entry.key != editingIndex && entry.value == reminder,
    );
    if (hasDuplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('มีเวลานี้อยู่แล้ว')));
      return;
    }

    setState(() {
      if (editingIndex != null) {
        _times[editingIndex] = reminder;
      } else {
        _times.add(reminder);
      }
      _times.sort();
    });
  }

  Future<void> _pickStartDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'เลือกวันที่เริ่มยา',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือก',
    );
    if (value == null) return;
    setState(() {
      _startDate = value;
      if (_endDate != null && _endDate!.isBefore(value)) _endDate = null;
    });
  }

  Future<void> _pickEndDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
      helpText: 'เลือกวันสิ้นสุด',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือก',
    );
    if (value == null) return;
    setState(() => _endDate = value);
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเพิ่มเวลาเตือนอย่างน้อย 1 เวลา')),
      );
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกวันที่ต้องทานยา')),
      );
      return;
    }

    final instructions = _selectedInstruction.toStoredValue(
      _instructionsController.text,
    );
    final original = widget.initialMedication;
    final medication = Medication(
      id: original?.id,
      name: _nameController.text,
      dosage: _dosageController.text,
      instructions: instructions,
      notes: _notesController.text,
      colorValue: _colorValue,
      reminderTimes: _times,
      weekdays: _weekdays,
      startDate: _startDate,
      endDate: _endDate,
      isActive: _isActive,
      archivedAt: original?.archivedAt,
      createdAt: original?.createdAt,
      updatedAt: DateTime.now(),
    );
    Navigator.of(context).pop(medication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'แก้ไขรายการยา' : 'เพิ่มรายการยา'),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _FormSection(
                            title: 'ข้อมูลยา',
                            child: Column(
                              children: [
                                TextFormField(
                                  key: const Key('medicationNameField'),
                                  controller: _nameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'ชื่อยา *',
                                    hintText: 'เช่น Metformin',
                                    prefixIcon: Icon(Icons.medication_outlined),
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'กรุณากรอกชื่อยา'
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const Key('medicationDosageField'),
                                  controller: _dosageController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'ขนาดที่ทาน *',
                                    hintText: 'เช่น 1 เม็ด • 500 มก.',
                                    prefixIcon: Icon(Icons.straighten_rounded),
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'กรุณากรอกขนาดที่ทาน'
                                      : null,
                                ),
                                const SizedBox(height: 14),
                                MedicationInstructionField(
                                  value: _selectedInstruction,
                                  customValueController:
                                      _instructionsController,
                                  onChanged: (option) => setState(
                                    () => _selectedInstruction = option,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _notesController,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'หมายเหตุ',
                                    hintText: 'ข้อมูลเพิ่มเติม (ถ้ามี)',
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FormSection(
                            title: 'สีประจำรายการ',
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: AppColors.medicinePalette.map((color) {
                                final value = color.toARGB32();
                                final selected = value == _colorValue;
                                return Semantics(
                                  button: true,
                                  selected: selected,
                                  label: 'เลือกสีรายการยา',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(99),
                                    onTap: () =>
                                        setState(() => _colorValue = value),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.ink
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FormSection(
                            title: 'เวลาเตือน',
                            subtitle: 'เพิ่มได้หลายเวลาในหนึ่งวัน',
                            trailing: TextButton.icon(
                              onPressed: _pickReminderTime,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('เพิ่มเวลา'),
                            ),
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < _times.length;
                                  index++
                                )
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == _times.length - 1
                                          ? 0
                                          : 10,
                                    ),
                                    child: _TimeRow(
                                      time: formatReminderTime(
                                        context,
                                        _times[index],
                                      ),
                                      onEdit: () => _pickReminderTime(
                                        editingIndex: index,
                                      ),
                                      onDelete: _times.length == 1
                                          ? null
                                          : () => setState(
                                              () => _times.removeAt(index),
                                            ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FormSection(
                            title: 'วันที่ทาน',
                            subtitle: 'เลือกวันที่ต้องการให้แจ้งเตือน',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: weekdayLongLabels.entries.map((entry) {
                                final selected = _weekdays.contains(entry.key);
                                return FilterChip(
                                  selected: selected,
                                  label: Text(entry.value),
                                  onSelected: (value) {
                                    setState(() {
                                      if (value) {
                                        _weekdays.add(entry.key);
                                      } else {
                                        _weekdays.remove(entry.key);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FormSection(
                            title: 'ช่วงเวลาที่ใช้ยา',
                            child: Column(
                              children: [
                                _DateRow(
                                  icon: Icons.calendar_today_outlined,
                                  title: 'วันที่เริ่ม',
                                  value: MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(_startDate),
                                  onTap: _pickStartDate,
                                ),
                                const Divider(height: 1),
                                _DateRow(
                                  icon: Icons.event_available_outlined,
                                  title: 'วันสิ้นสุด',
                                  value: _endDate == null
                                      ? 'ทานต่อเนื่อง'
                                      : MaterialLocalizations.of(
                                          context,
                                        ).formatMediumDate(_endDate!),
                                  onTap: _pickEndDate,
                                  trailing: _endDate == null
                                      ? null
                                      : IconButton(
                                          tooltip: 'ลบวันสิ้นสุด',
                                          onPressed: () =>
                                              setState(() => _endDate = null),
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          _FormSection(
                            title: 'สถานะ',
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _isActive,
                              onChanged: (value) =>
                                  setState(() => _isActive = value),
                              title: const Text(
                                'เปิดการแจ้งเตือน',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: const Text(
                                'ปิดชั่วคราวได้โดยไม่ลบประวัติ',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('saveMedicationButton'),
                            onPressed: _submit,
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              _isEditing ? 'บันทึกการแก้ไข' : 'เพิ่มรายการยา',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.time,
    required this.onEdit,
    required this.onDelete,
  });

  final String time;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              time,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'แก้ไขเวลา',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'ลบเวลา',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
