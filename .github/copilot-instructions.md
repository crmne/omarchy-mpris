# Copilot instructions

Read `README.md` and `manifest.json` in full before reviewing or changing this
repository. Keep this a small native Omarchy Quattro plugin. Preserve current
behavior unless the task explicitly changes it, and do not broaden a focused
fix into a shell redesign or media-player abstraction.

## Ownership and architecture

- This repository owns the `crmne.mpris` plugin: the persistent MPRIS service
  in `Service.qml`, the per-bar presentation in `BarWidget.qml`, the IPC
  surface, plugin metadata, settings, documentation, and preview image.
- `basecamp/omarchy` owns the Quattro host, plugin loader, bar layout and
  settings APIs, and shared `qs.Commons` and `qs.Ui` components. Do not patch or
  replace packaged Omarchy files from this plugin. A host-shell defect should
  be fixed or reported there.
- Quickshell owns `Quickshell.Services.Mpris` and its D-Bus wrappers. The media
  player owns the metadata and capability flags it publishes over MPRIS. Do not
  claim a plugin bug solely because a player reports incomplete or transient
  state; establish which layer is wrong first.
- `omacom/omarchy-plugin-marketplace` owns marketplace publication. Do not
  rewrite a published tag or change marketplace state from this repository.

`Service.qml` is kept loaded once by the manifest and is the source of truth
for player selection and transport actions. `BarWidget.qml` can be instantiated
on several monitors and should only present that shared service plus
per-instance layout and settings. Do not add a player watcher, timer, or copy of
selection state to every widget instance.

## Review priorities

- Preserve direct Quickshell MPRIS integration. Do not add `playerctl` polling,
  cover-art downloads to temporary files, helper daemons, a browser engine, or
  another runtime dependency without an explicit product decision.
- Player selection intentionally ignores stopped or trackless entries, prefers
  the remembered playing player, then a playing non-`playerctld` source, and
  treats the `playerctld` proxy as a fallback. Changes must behave sensibly with
  several players, paused players, disappearing D-Bus objects, metadata gaps,
  and duplicate proxy entries.
- Gate every action on the player's advertised `canPlay`, `canPause`,
  `canTogglePlaying`, `canGoPrevious`, `canGoNext`, or `canRaise` capability.
  Keep `playPause`, `previous`, `next`, and `raise` truthful: return `false`
  without an action and remember the player only after handling one.
- Keep the `crmne.mpris` IPC contract backward compatible. `status` returns
  valid JSON with stable field types, and action methods return `ok` or
  `unhandled`. Do not expose raw QML objects or allow a delayed response to
  describe a player that is no longer selected.
- Treat all MPRIS metadata and artwork URLs as untrusted player input. Render
  title, artist, and album as `Text.PlainText`; never interpret metadata as QML,
  HTML, commands, or file paths. Keep image loading asynchronous and do not log
  private metadata or local artwork paths.
- Adaptive layout is computed independently for each bar window. Preserve the
  actual slot/window measurements and the degradation order: shorten the label,
  then remove previous/next, play/pause, artwork, and finally the label as space
  disappears. A widget must give width back before left, center, and right bar
  groups overlap. Keep vertical-bar behavior explicit.
- Settings have three representations that must agree: `barWidget.defaults`,
  the manifest schema including types and ranges, and the fallback and clamp in
  QML. Preview settings locally, then persist them through
  `updateEntryInline`. Existing saved settings must remain readable.
- Keep UI work nonblocking. Use QML bindings, short timers, and asynchronous
  image loading; never make synchronous network, D-Bus, or subprocess calls on
  the shell UI thread. Avoid periodic polling when a Quickshell property or
  signal can express the state.
- Preserve pointer behavior: left click raises, middle click goes to the
  previous track, right click opens appearance settings, and scrolling changes
  tracks. Disabled transport controls must not invoke unsupported actions.
- User-visible layout, animation, or interaction changes need before-and-after
  evidence for horizontal and vertical bars, narrow and roomy widths, multiple
  monitors, light and dark themes, and both complete and missing metadata.
- Keep `manifest.json` ID, kinds, entry points, version, settings, and README in
  sync. Do not bump the version, create a tag, or modify release metadata unless
  the task is explicitly a release.

## Validation

Run these checks for every change:

```bash
qmllint Service.qml BarWidget.qml
omarchy plugin validate .
jq empty manifest.json
git diff --check
```

Add focused deterministic tests when introducing JavaScript decision logic or
a state machine. Such logic should be kept free of QML and real time where
possible so Node tests can control ordering. Report actual validation and do
not treat unresolved host imports as proof that runtime behavior works.

## Review communication

Lead with concrete defects caused by the change. Separate confirmed plugin
bugs from player, Quickshell, or Omarchy ownership questions. Avoid speculative
redesigns, adjacent cleanup, implementation diaries, and claims about tests or
platforms that were not actually exercised.
