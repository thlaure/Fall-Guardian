Fix the bug at the correct layer, not with a local workaround.

Steps:
- reproduce or understand the failing path
- trace ownership across Flutter/native/backend if cross-platform
- implement the smallest durable fix
- add a regression test when practical
- verify the narrowest relevant checks, then broader checks if needed
