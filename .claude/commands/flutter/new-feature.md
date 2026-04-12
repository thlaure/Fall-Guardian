Implement a Flutter/Dart feature in the smallest clean slice.

Steps:
- scan the relevant architecture first
- place workflow in coordinators/services, persistence in repositories, UI in widgets
- check Android/iOS bridge impact if channels, notifications, or watch sync are touched
- add or update Flutter tests
- update docs if runtime behavior changed
- verify the relevant Flutter and cross-platform checks before finishing
