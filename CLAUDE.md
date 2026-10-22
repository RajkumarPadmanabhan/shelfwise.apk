# Shelfwise: notes for Claude

Shelfwise is a Flutter Android app: a cozy bookshelf, PDF/EPUB reader and reading to-do list. It's a port of the "Readers" HTML mockup (`../readers.html` in the original workspace), with Explore replaced by To-do and everything stored on the phone.

Repo: https://github.com/RajkumarPadmanabhan/update-shelf (moved from `RajkumarPadmanabhan/shelfwise.apk`). Website: https://rajkumarpadmanabhan.github.io/update-shelf/. The repo slug and site URL live in `lib/version.dart` (`repo`, `siteUrl`); the updater and the Settings links read them from there.

## Workflow rules (always follow)

- **Branches:** do all work on `dev`. Build it, install it on the test phone and check it there first. Only then fast-forward `main` to `dev` and push both.
- **No Claude attribution:** never add `Co-Authored-By: Claude` or "Generated with Claude" lines to commits, PRs, tags or release notes.
- **Every change ships:** bump `version:` in `pubspec.yaml` *and* `appVersion` in `lib/version.dart`, add `.github/release-notes/vX.Y.Z.md`, then push the tag `vX.Y.Z` from `main`. The **Release APK** action builds the signed APK and publishes the GitHub release with `shelfwise.apk` attached. The asset name matters: the website and the in-app updater link to `releases/latest/download/shelfwise.apk`.
- **Keep the website current:** `docs/` is GitHub Pages (served from `main:/docs`). Update `docs/index.html` (feature cards, FAQ, `APP_VERSION`) and the screenshots in `docs/screens/` whenever features change.
- **Never commit book files or signing material:** no `*.pdf`, `*.apk`, `*.jks` or `key.properties`. The only book file allowed in the repo is the public-domain `test/fixtures/alice.epub`.

## Commands

```bash
flutter pub get
flutter analyze            # must be clean
flutter test               # backups, EPUB parsing, ISBN + version checks
flutter build apk --release --target-platform android-arm,android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

- **Local signing:** release builds read `android/key.properties`, which is git-ignored and points at the upload keystore kept outside the repo. Without it, the build falls back to the debug key, and that APK will *not* install over released versions.
- **CI signing:** CI signs with repo secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD` and `KEY_ALIAS`, the same key as local builds.

## Code map

- `lib/main.dart`: startup, splash (`screens/splash.dart`), then onboarding → tour → `Shell`.
- `lib/data/store.dart`: `AppStore` (the singleton `store`) holds all state in one JSON file. Call `store.changed()` after any mutation; it notifies listeners and saves shortly after. Also holds shelf rules (10 items per row, plus a sub shelf), stats, rewards, reading log/goal, and backups (JSON, or a zip that carries book files).
- `lib/data/models.dart`: `Item` (a book or a decoration), `Collection`, `Todo`, `Mark`, `Profile`, `Settings`.
- `lib/theme.dart` + `lib/look.dart`: colours live in `C.*` getters backed by the current `Pal`. `Look.apply()` switches light/dark, background family (`palFor`), accent, font and text size, then rebuilds the app. Use `C.*` and `nu()`. Don't hard-code light-only colours: everything must work in dark mode and in every background family.
- `lib/art.dart` is generated from the mockup's SVGs (except `owlSvg`, which was redrawn by hand). Don't edit the generated parts by hand.
- `lib/widgets/`:
  - `shelf.dart`: shelf row, with long-press drag where the other items reflow around the gap.
  - `fx.dart`: tear/smash, decoration animations, confetti.
  - `dialogs.dart`: `openDialog`/`AppDialog`/`Btn`. A `Btn.onTap` that returns `false` keeps the dialog open.
  - `common.dart`: toast, `Pressable`, `PopChip`, `AppInput`.
- `lib/screens/`: one file per page. The reader is `reader_screen.dart` (paper curl, zoom, bookmarks/notes, reading time) on top of `lib/reader/source.dart` (`PdfSource`) and `lib/reader/epub.dart` (EPUB parse in an isolate + pagination).
- `lib/services/`: synthesised sound effects, notifications, update checks (GitHub API), ISBN lookup (Open Library, then Google Books), share/save images.

## Gotchas learned the hard way

- Overlay layers (toast, effects) sit outside any `Material`. Wrap new ones in `Material`/`DefaultTextStyle`, or text gets Flutter's yellow double underline.
- `ListView`/`GridView` inside dialogs need `padding: EdgeInsets.zero`, otherwise they inherit the status-bar inset.
- The reader `Scaffold` uses `resizeToAvoidBottomInset: false`. Otherwise the keyboard (notes) shrinks the page and re-flows the whole EPUB.
- EPUB positions are character offsets (`Item.pos`, `Mark.pos`); images count as one character. Prefer the saved page index while the layout is unchanged.
- Decorations stand *behind* the shelf glass like books (drawn taller via `shelfGadgetFactor`), never in front.
- Check on the phone at full resolution: alignment of pill text, dark mode, and that header buttons scroll with the page instead of floating over content.
- The test phone may be in use. Look at a screenshot before tapping. Its OS blocks `pm clear`, so wipe data by uninstalling. Don't save or import test data over the owner's real library.
