Fix the Flutter/Dart bug at the owning layer, not with a widget-local workaround.

Steps:
- reproduce or understand the failing path
- trace ownership across coordinator, repositories, and platform bridges if relevant
- implement the smallest durable fix
- add a regression test when practical
- verify the narrowest relevant Flutter checks, then broader checks if needed
