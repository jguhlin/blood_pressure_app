Development guide

Overview
- lib/main.dart contains the current app (single‑file) UI and data logic.
- Charts use `fl_chart`. Health data is read via the `health` package (Health Connect).
- PDF export uses `printing` + `pdf`.

Key areas
- Trend vs Average Day vs Compare modes are toggled via `_ViewMode`.
- Health fetch helpers: `_fetchData`, `_fetchSecondary`, `_fetchSecondarySeries`.
- Summaries and export: `_bpStatsForSeries`, `_exportPdf`.

Secondary metrics
- Supported: HR, Resting HR, HRV (SDNN/RMSSD), Steps, Sleep (min), Energy (kcal), Exercise Time (min).
- Trend shows a right axis; Average Day overlays a right‑axis label approximation.

Morning surge (strict)
- `_inferWakeTimesStrict` infers daily wake time using (in order): sleep segments, steps spikes, HR elevation.
- `_computeMorningSurgeStrict` computes STS (sleep‑trough surge) and prewaking surge per day and averages across days.

PDF
- Exports current view; by default includes both Trend and Average Day.
- Summary table includes day/night means, dipping, morning surge, and strict variants if available.
- HR/HRV/steps/sleep/energy/workout summaries appear only when the metric is present.

Style and linting
- Run `dart format .` and `flutter analyze` before committing.
- Prefer pure helpers at the bottom of the file and stateless widgets where possible.

Next refactors
- Extract chart widgets into `lib/widgets/` and data/metrics into `lib/services/`.
- Add small unit tests for quantiles, surge windows, and binning.

