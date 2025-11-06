import 'package:flutter/material.dart';
import '../models/event.dart';

class AdvancedSettingsSheet extends StatefulWidget {
  final String trendSmoothMethod;
  final bool trendSmoothAuto;
  final int trendSmoothDays;
  final void Function(String) onTrendSmoothMethod;
  final void Function(bool) onTrendSmoothAuto;
  final void Function(int) onTrendSmoothDays;

  final bool showBands;
  final void Function(bool) onShowBands;

  final bool anchorToDose;
  final TimeOfDay? doseTime;
  final void Function(bool) onAnchorToDose;
  final void Function(TimeOfDay) onDoseTimeChanged;
  // Zone scheme
  final String zoneScheme; // 'acc_aha' or 'esc_esh'
  final void Function(String) onZoneScheme;

  final List<Event> events;
  final Future<void> Function(String title, DateTime date) onAddEvent;
  final Future<void> Function(String id, String title) onRenameEvent;
  final Future<void> Function(String id) onDeleteEvent;
  final Future<void> Function(Event e)? onSetRange;
  final Future<void> Function(Event e)? onSetA;
  final Future<void> Function(Event e)? onSetB;

  // Surge
  final int surgeMorningWindowHours;
  final int surgeTroughWindowHours;
  final int surgePrewakeHours;
  final int surgeHrRiseBpm;
  final int surgeSteps30Min;
  final int surgeWakeEarliestHour;
  final int surgeWakeLatestHour;
  final void Function({
    int? morning,
    int? trough,
    int? prewake,
    int? hrRise,
    int? steps30,
    int? earliest,
    int? latest,
  })
  onSurgeChange;

  const AdvancedSettingsSheet({
    super.key,
    required this.trendSmoothMethod,
    required this.trendSmoothAuto,
    required this.trendSmoothDays,
    required this.onTrendSmoothMethod,
    required this.onTrendSmoothAuto,
    required this.onTrendSmoothDays,
    required this.showBands,
    required this.onShowBands,
    required this.anchorToDose,
    required this.doseTime,
    required this.onAnchorToDose,
    required this.onDoseTimeChanged,
    required this.zoneScheme,
    required this.onZoneScheme,
    required this.events,
    required this.onAddEvent,
    required this.onRenameEvent,
    required this.onDeleteEvent,
    this.onSetRange,
    this.onSetA,
    this.onSetB,
    required this.surgeMorningWindowHours,
    required this.surgeTroughWindowHours,
    required this.surgePrewakeHours,
    required this.surgeHrRiseBpm,
    required this.surgeSteps30Min,
    required this.surgeWakeEarliestHour,
    required this.surgeWakeLatestHour,
    required this.onSurgeChange,
  });

  @override
  State<AdvancedSettingsSheet> createState() => _AdvancedSettingsSheetState();
}

class _AdvancedSettingsSheetState extends State<AdvancedSettingsSheet> {
  final titleCtl = TextEditingController();
  DateTime newEventDate = DateTime.now();
  String q = '';
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Advanced Settings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('Trend Smoother'),
              RadioGroup<String>(
                groupValue: widget.trendSmoothMethod,
                onChanged: (v) {
                  if (v != null) widget.onTrendSmoothMethod(v);
                  setState(() {});
                },
                child: Row(
                  children: const [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('Moving Average'),
                        value: 'ma',
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('EMA'),
                        value: 'ema',
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Text('Auto window'),
                  const SizedBox(width: 6),
                  Switch(
                    value: widget.trendSmoothAuto,
                    onChanged: (v) {
                      widget.onTrendSmoothAuto(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  if (!widget.trendSmoothAuto)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Window: ${widget.trendSmoothDays}d',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Slider(
                            value: widget.trendSmoothDays.toDouble(),
                            min: 3,
                            max: 15,
                            divisions: 6,
                            label: '${widget.trendSmoothDays}d',
                            onChanged: (v) {
                              int d = v.round();
                              if (d % 2 == 0) d += 1;
                              widget.onTrendSmoothDays(d);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              const Text('BP Zone Guidelines (Trend background)'),
              RadioGroup<String>(
                groupValue: widget.zoneScheme,
                onChanged: (v) {
                  if (v != null) widget.onZoneScheme(v);
                  setState(() {});
                },
                child: Row(
                  children: const [
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('US (ACC/AHA)'),
                        value: 'acc_aha',
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text('EU (ESC/ESH)'),
                        value: 'esc_esh',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              const Text('Events (Bookmarks)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: titleCtl,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      '${newEventDate.month}/${newEventDate.day}/${newEventDate.year}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (titleCtl.text.trim().isEmpty) return;
                      await widget.onAddEvent(
                        titleCtl.text.trim(),
                        newEventDate,
                      );
                      titleCtl.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Filter events',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  setState(() => q = v.trim().toLowerCase());
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  itemBuilder: (_, i) {
                    final list = widget.events
                        .where(
                          (e) => q.isEmpty || e.title.toLowerCase().contains(q),
                        )
                        .toList();
                    if (i >= list.length) return const SizedBox.shrink();
                    final e = list[i];
                    return ListTile(
                      title: Text(
                        '${e.title} — ${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              widget.onSetRange?.call(e);
                            },
                            child: const Text('Set Range'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              widget.onSetA?.call(e);
                            },
                            child: const Text('Set A'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              widget.onSetB?.call(e);
                            },
                            child: const Text('Set B'),
                          ),
                          IconButton(
                            onPressed: () async {
                              final t = await _promptText(
                                context,
                                'Rename Event',
                                e.title,
                              );
                              if (t != null && t.trim().isNotEmpty) {
                                await widget.onRenameEvent(e.id, t.trim());
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            onPressed: () {
                              widget.onDeleteEvent(e.id);
                              setState(() {});
                            },
                            icon: const Icon(Icons.delete),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: widget.events
                      .where(
                        (e) => q.isEmpty || e.title.toLowerCase().contains(q),
                      )
                      .length,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Strict Morning Surge'),
              const SizedBox(height: 6),
              Wrap(
                runSpacing: 6,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Morning window (h)',
                      value: widget.surgeMorningWindowHours,
                      onChanged: (v) {
                        widget.onSurgeChange(morning: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Trough window (h)',
                      value: widget.surgeTroughWindowHours,
                      onChanged: (v) {
                        widget.onSurgeChange(trough: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Prewaking (h)',
                      value: widget.surgePrewakeHours,
                      onChanged: (v) {
                        widget.onSurgeChange(prewake: v);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                runSpacing: 6,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'HR rise threshold (bpm)',
                      value: widget.surgeHrRiseBpm,
                      onChanged: (v) {
                        widget.onSurgeChange(hrRise: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Steps in 30 min',
                      value: widget.surgeSteps30Min,
                      onChanged: (v) {
                        widget.onSurgeChange(steps30: v);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                runSpacing: 6,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Wake earliest hr',
                      value: widget.surgeWakeEarliestHour,
                      onChanged: (v) {
                        widget.onSurgeChange(earliest: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Wake latest hr',
                      value: widget.surgeWakeLatestHour,
                      onChanged: (v) {
                        widget.onSurgeChange(latest: v);
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Bands'),
                  const SizedBox(width: 6),
                  Switch(
                    value: widget.showBands,
                    onChanged: (v) {
                      widget.onShowBands(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Anchor to dose'),
                  const SizedBox(width: 6),
                  Switch(
                    value: widget.anchorToDose,
                    onChanged: (v) {
                      widget.onAnchorToDose(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: !widget.anchorToDose
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              widget.doseTime ??
                              const TimeOfDay(hour: 8, minute: 0),
                        );
                        if (picked != null) {
                          widget.onDoseTimeChanged(picked);
                          setState(() {});
                        }
                      },
                icon: const Icon(Icons.medication),
                label: Text(
                  widget.doseTime == null
                      ? 'Dose time'
                      : '${widget.doseTime!.hour.toString().padLeft(2, '0')}:${widget.doseTime!.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: newEventDate,
    );
    if (picked != null) setState(() => newEventDate = picked);
  }

  Future<String?> _promptText(
    BuildContext context,
    String title,
    String initial,
  ) async {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(controller: ctl),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _NumField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final ctl = TextEditingController(text: value.toString());
    return TextField(
      controller: ctl,
      keyboardType: const TextInputType.numberWithOptions(
        signed: false,
        decimal: false,
      ),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (s) {
        final v = int.tryParse(s.trim());
        if (v != null) onChanged(v);
      },
    );
  }
}
