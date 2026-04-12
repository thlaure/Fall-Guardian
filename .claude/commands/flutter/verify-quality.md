Run the narrowest relevant Flutter verification first, then broaden if needed.

Typical checks:
- `cd flutter_app && flutter analyze`
- `cd flutter_app && flutter test`
- `make check`
- platform-specific build or manual verification when native bridges are affected
