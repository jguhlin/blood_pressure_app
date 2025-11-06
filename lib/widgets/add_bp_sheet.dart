import 'package:flutter/material.dart';

class AddBpSheet extends StatefulWidget {
  final String defaultPosition;
  final String defaultArm;
  final Future<bool> Function(int systolic, int diastolic, DateTime when, String position, String arm) onSave;
  const AddBpSheet({super.key, required this.defaultPosition, required this.defaultArm, required this.onSave});

  @override
  State<AddBpSheet> createState() => _AddBpSheetState();
}

class _AddBpSheetState extends State<AddBpSheet> {
  final sysCtl = TextEditingController();
  final diaCtl = TextEditingController();
  late DateTime when;
  late String pos;
  late String arm;

  @override
  void initState() {
    super.initState();
    when = DateTime.now();
    pos = widget.defaultPosition;
    arm = widget.defaultArm;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add Blood Pressure', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children:[
              Expanded(child: TextField(controller: sysCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Systolic', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: diaCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText:'Diastolic', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            Row(children:[
              OutlinedButton.icon(onPressed: _pickDateTime, icon: const Icon(Icons.access_time), label: Text('${when.month}/${when.day}/${when.year} ${when.hour.toString().padLeft(2,'0')}:${when.minute.toString().padLeft(2,'0')}')),
            ]),
            const SizedBox(height: 12),
            Row(children:[
              const Text('Position'), const SizedBox(width: 6),
              DropdownButton<String>(value: pos, items: const [
                DropdownMenuItem(value:'sitting', child: Text('Sitting')),
                DropdownMenuItem(value:'standing', child: Text('Standing')),
                DropdownMenuItem(value:'supine', child: Text('Supine')),
              ], onChanged: (v){ if(v!=null) setState(()=> pos=v); }),
              const SizedBox(width: 18),
              const Text('Arm'), const SizedBox(width: 6),
              DropdownButton<String>(value: arm, items: const [
                DropdownMenuItem(value:'left_upper_arm', child: Text('Left Upper Arm')),
                DropdownMenuItem(value:'right_upper_arm', child: Text('Right Upper Arm')),
                DropdownMenuItem(value:'wrist', child: Text('Wrist')),
              ], onChanged: (v){ if(v!=null) setState(()=> arm=v); }),
            ]),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save'))),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: when);
    if (d == null) return;
    if (!mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
    if (!mounted) return;
    setState(()=> when = DateTime(d.year,d.month,d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
  }

  Future<void> _save() async {
    final s = int.tryParse(sysCtl.text.trim()); final d = int.tryParse(diaCtl.text.trim());
    if (s==null || d==null) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid numbers'))); return; }
    final ok = await widget.onSave(s, d, when, pos, arm);
    if (!mounted) return;
    if (ok) { Navigator.of(context).pop(); } else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save BP'))); }
  }
}
