class ChartBp {
  final DateTime? t;
  final double? sbp;
  final double? dbp;
  const ChartBp({required this.t, required this.sbp, required this.dbp});
}

class ChartSecPoint {
  final DateTime date;
  final double value;
  const ChartSecPoint({required this.date, required this.value});
}

class ChartSecSample {
  final DateTime t;
  final double v;
  final DateTime? start;
  final DateTime? end;
  final double? durMin;
  const ChartSecSample({
    required this.t,
    required this.v,
    this.start,
    this.end,
    this.durMin,
  });
}
