# Lab Portfolio

A multi-screen Flutter app that serves as a master compilation hub for
laboratory activities — a Home Dashboard menu, five empty Activity slots
ready for your own projects, and a Settings screen with global (app-wide)
state.

## Updating an existing local project

If you already ran `flutter create` on an earlier version of this project,
you don't need to redo that step. Just copy `lib/`, `test/`, and
`pubspec.yaml` from this zip into your project folder, overwriting the old
ones. Your generated `android/`, `ios/`, `web/`, etc. folders are untouched
and don't need to change.

## Getting it running from scratch

```bash
# 1. Unzip / copy this project somewhere, then from inside the folder:
flutter create --project-name lab_portfolio .

# 2. Get dependencies
flutter pub get

# 3. Run on your device/emulator/browser of choice
flutter run
```

To run the included tests:

```bash
flutter test
```

## Project structure

```
lib/
  main.dart                          # App root, Provider setup, routes, theme
  providers/
    app_state_provider.dart          # Global state: theme mode, user name, per-activity completion
  screens/
    home_screen.dart                 # Dashboard / menu (StatelessWidget) + kActivities list
    settings_screen.dart             # Global settings editor (StatefulWidget)
    activity_placeholder_screen.dart # Shared empty activity screen (StatelessWidget) used for all 5 slots
  widgets/
    dashboard_card.dart              # Reusable presentational card (StatelessWidget)
    primary_button.dart              # Reusable presentational button (StatelessWidget), ready for your activity content
test/
  widget_test.dart                   # Sanity + state-management tests
```

## Adding your project into an activity

Open `lib/screens/activity_placeholder_screen.dart`. Everything in its
`build()` method is scaffolding — the icon, the "This activity is empty"
message, and the "Mark complete" button. Delete what you don't need and
put your own widgets in its place.

Since all 5 activities currently share one file, you have two options:

- **Quick and simple:** keep sharing `ActivityPlaceholderScreen`, but add an
  `if (activityNumber == 1) return YourActivity1Widget();` branch (and so
  on) at the top of `build()` before the placeholder UI.
- **Cleaner long-term:** once an activity has real content, give it its
  own file (e.g. `lib/screens/activity_1_screen.dart`) and point its route
  in `main.dart` at that new widget instead of
  `ActivityPlaceholderScreen`. Convert it to a `StatefulWidget` if it needs
  local state (the way `SettingsScreen` does).

Either way, the routes (`/activity-1` through `/activity-5`) and the
`kActivities` list in `home_screen.dart` are the two things that tie a
Home Dashboard card to a screen — update `kActivities` if you want to
change a title, icon, or color.

## How each requirement is satisfied

**Multi-screen navigation** — `main.dart` registers named routes for
seven screens: `/` (Home), `/settings`, and `/activity-1` through
`/activity-5`. The Home Dashboard's cards and app bar icon navigate to
them with `Navigator.pushNamed`.

**Widget architecture** — `DashboardCard` and `PrimaryButton` are
`StatelessWidget`s: pure functions of their constructor parameters, reused
across every screen. `SettingsScreen` is a `StatefulWidget` because it
owns a `TextEditingController` — state meaningful only to that screen.
`HomeScreen` and `ActivityPlaceholderScreen` are `StatelessWidget`s: they
have no internal state of their own, they only read and write the shared
`AppStateProvider`. When you add real content to an activity that needs
its own local state (a form, a timer, a counter), convert that screen to
a `StatefulWidget` — the README section above shows where.

**Responsive layout** — Every screen uses `Column`/`Row`/`Expanded`/
`Wrap`/`LayoutBuilder` rather than fixed sizes, so nothing overflows on
small phones or wide tablets. `HomeScreen` uses `LayoutBuilder` + `Wrap`
to lay out however many activity cards exist (currently 5) in one column
on phones and two columns above a 640px width breakpoint — no manual math
required if you add a 6th activity later.

**Global state management (Provider)** — `AppStateProvider` (a
`ChangeNotifier`) is created once in `main.dart` via
`ChangeNotifierProvider` and is available to the whole widget tree. It
holds:
- `themeMode` — toggled from the Switch on `SettingsScreen`, consumed by
  `MaterialApp` (via a `Consumer`) *and* reflected on `SettingsScreen`
  itself, so flipping it instantly re-themes the entire app.
- `userName` — edited on `SettingsScreen`, reflected immediately in the
  Home Dashboard's welcome header and avatar.
- `completedActivities` — a set of activity numbers marked complete from
  any `ActivityPlaceholderScreen`. The Home Dashboard's progress banner
  ("Activities completed: X of 5") and each card's green checkmark badge
  update instantly, demonstrating state flowing from a child screen back
  up to the shared dashboard.

Widgets that need to react to state changes call `context.watch<...>()`;
one-off actions (like calling `toggleTheme()`) use `context.read<...>()`
so they don't force unnecessary rebuilds.
