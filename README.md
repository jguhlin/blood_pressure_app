# blood_pressure_app

Android app for plotting blood pressure results from Health Connect.

Highlights
- Trend, Average Day, and Compare views with distribution and smoothing options.
- Secondary axis for HR, Resting HR, HRV (SDNN/RMSSD), Steps, Sleep (min), Energy (kcal), Exercise Time (min).
- PDF export with embedded charts and concise summaries (day/night averages, dipping, morning surge + strict variants). Rows include body position/arm when added via the app.
- TSV export of current view.

Developer Notes
- See `docs/DEVELOPING.md` for architecture overview and helper locations.
- Run `flutter analyze` and `dart format .` before committing.
