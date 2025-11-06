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
  // Local mirror state so the sheet updates immediately without needing a parent rebuild
  late String _trendSmoothMethod;
  late bool _trendSmoothAuto;
  late int _trendSmoothDays;
  late bool _showBands;
  late bool _anchorToDose;
  TimeOfDay? _doseTimeLocal;
  late String _zoneScheme;
  late int _surgeMorningWindowHours;
  late int _surgeTroughWindowHours;
  late int _surgePrewakeHours;
  late int _surgeHrRiseBpm;
  late int _surgeSteps30Min;
  late int _surgeWakeEarliestHour;
  late int _surgeWakeLatestHour;
  late List<Event> _eventsLocal;

  @override
  void initState() {
    super.initState();
    _trendSmoothMethod = widget.trendSmoothMethod;
    _trendSmoothAuto = widget.trendSmoothAuto;
    _trendSmoothDays = widget.trendSmoothDays;
    _showBands = widget.showBands;
    _anchorToDose = widget.anchorToDose;
    _doseTimeLocal = widget.doseTime;
    _zoneScheme = widget.zoneScheme;
    _surgeMorningWindowHours = widget.surgeMorningWindowHours;
    _surgeTroughWindowHours = widget.surgeTroughWindowHours;
    _surgePrewakeHours = widget.surgePrewakeHours;
    _surgeHrRiseBpm = widget.surgeHrRiseBpm;
    _surgeSteps30Min = widget.surgeSteps30Min;
    _surgeWakeEarliestHour = widget.surgeWakeEarliestHour;
    _surgeWakeLatestHour = widget.surgeWakeLatestHour;
    _eventsLocal = List<Event>.from(widget.events);
  }

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
                groupValue: _trendSmoothMethod,
                onChanged: (v) {
                  if (v != null) {
                    _trendSmoothMethod = v;
                    widget.onTrendSmoothMethod(v);
                    setState(() {});
                  }
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
                    value: _trendSmoothAuto,
                    onChanged: (v) {
                      _trendSmoothAuto = v;
                      widget.onTrendSmoothAuto(v);
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  if (!_trendSmoothAuto)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Window: ${_trendSmoothDays}d',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Slider(
                            value: _trendSmoothDays.toDouble(),
                            min: 3,
                            max: 15,
                            divisions: 6,
                            label: '${_trendSmoothDays}d',
                            onChanged: (v) {
                              int d = v.round();
                              if (d % 2 == 0) d += 1;
                              _trendSmoothDays = d;
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
                groupValue: _zoneScheme,
                onChanged: (v) {
                  if (v != null) {
                    _zoneScheme = v;
                    widget.onZoneScheme(v);
                    setState(() {});
                  }
                },
                child: Wrap(
                  spacing: 8,
                  runSpacing: 0,
                  children: const [
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('US (ACC/AHA)'),
                        value: 'acc_aha',
                        secondary: Tooltip(
                          message:
                              'ACC/AHA 2017: Elevated 120–129/<80; Stage1 130–139/80–89; Stage2 ≥140/90. Ref: 2017 High Blood Pressure Guideline (AHA/ACC).',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('EU (ESC/ESH)'),
                        value: 'esc_esh',
                        secondary: Tooltip(
                          message:
                              'ESC/ESH 2018: Normal <130/<85; High-normal 130–139/85–89; Grade1 140–159/90–99; Grade2 160–179/100–109; Grade3 ≥180/≥110. Ref: ESC/ESH 2018 Guidelines.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('Australia (NHFA)'),
                        value: 'aus',
                        secondary: Tooltip(
                          message:
                              'Australia NHFA 2016: Office thresholds and grading align closely with ESC/ESH. Ref: National Heart Foundation 2016.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('New Zealand'),
                        value: 'nz',
                        secondary: Tooltip(
                          message:
                              'New Zealand: Primary care thresholds align with ESC/ESH-style office cutoffs. Ref: NZ guidance summaries.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('UK (NICE)'),
                        value: 'nice_uk',
                        secondary: Tooltip(
                          message:
                              'NICE (UK): Key office thresholds 140/90, 160/100, 180/120 for staging/urgency. Ref: NICE Hypertension guideline.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('ISH (International)'),
                        value: 'ish',
                        secondary: Tooltip(
                          message:
                              'ISH 2020: Grade 1 ≥140/90 to <160/100; Grade 2 ≥160/100. Ref: ISH 2020 guideline.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('Hypertension Canada'),
                        value: 'can',
                        secondary: Tooltip(
                          message:
                              'Hypertension Canada: Office staging similar to ESC; targets vary by comorbidity. Ref: Hypertension Canada guidelines.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: RadioListTile<String>(
                        title: Text('Japan (JSH)'),
                        value: 'jsh',
                        secondary: Tooltip(
                          message:
                              'JSH (Japan): Grade 1 140–159/90–99; Grade 2 160–179/100–109; Grade 3 ≥180/≥110. Ref: JSH 2019/2021.',
                          child: Icon(Icons.info_outline, size: 16),
                        ),
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
                      final t = titleCtl.text.trim();
                      await widget.onAddEvent(t, newEventDate);
                      _eventsLocal = [
                        Event(
                          id: 'evt_${DateTime.now().microsecondsSinceEpoch}',
                          title: t,
                          date: DateTime(
                            newEventDate.year,
                            newEventDate.month,
                            newEventDate.day,
                          ),
                        ),
                        ..._eventsLocal,
                      ];
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
                    final list = _eventsLocal
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
                                _eventsLocal = _eventsLocal
                                    .map(
                                      (ev) => ev.id == e.id
                                          ? ev.copyWith(title: t.trim())
                                          : ev,
                                    )
                                    .toList();
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            onPressed: () {
                              widget.onDeleteEvent(e.id);
                              _eventsLocal = _eventsLocal
                                  .where((ev) => ev.id != e.id)
                                  .toList();
                              setState(() {});
                            },
                            icon: const Icon(Icons.delete),
                          ),
                        ],
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _eventsLocal
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
                      value: _surgeMorningWindowHours,
                      onChanged: (v) {
                        _surgeMorningWindowHours = v;
                        widget.onSurgeChange(morning: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Trough window (h)',
                      value: _surgeTroughWindowHours,
                      onChanged: (v) {
                        _surgeTroughWindowHours = v;
                        widget.onSurgeChange(trough: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Prewaking (h)',
                      value: _surgePrewakeHours,
                      onChanged: (v) {
                        _surgePrewakeHours = v;
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
                      value: _surgeHrRiseBpm,
                      onChanged: (v) {
                        _surgeHrRiseBpm = v;
                        widget.onSurgeChange(hrRise: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Steps in 30 min',
                      value: _surgeSteps30Min,
                      onChanged: (v) {
                        _surgeSteps30Min = v;
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
                      value: _surgeWakeEarliestHour,
                      onChanged: (v) {
                        _surgeWakeEarliestHour = v;
                        widget.onSurgeChange(earliest: v);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _NumField(
                      label: 'Wake latest hr',
                      value: _surgeWakeLatestHour,
                      onChanged: (v) {
                        _surgeWakeLatestHour = v;
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
                    value: _showBands,
                    onChanged: (v) {
                      _showBands = v;
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
                    value: _anchorToDose,
                    onChanged: (v) {
                      _anchorToDose = v;
                      widget.onAnchorToDose(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: !_anchorToDose
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime:
                              _doseTimeLocal ??
                              const TimeOfDay(hour: 8, minute: 0),
                        );
                        if (picked != null) {
                          _doseTimeLocal = picked;
                          widget.onDoseTimeChanged(picked);
                          setState(() {});
                        }
                      },
                icon: const Icon(Icons.medication),
                label: Text(
                  _doseTimeLocal == null
                      ? 'Dose time'
                      : '${_doseTimeLocal!.hour.toString().padLeft(2, '0')}:${_doseTimeLocal!.minute.toString().padLeft(2, '0')}',
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
