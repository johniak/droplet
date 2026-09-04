import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/input/gamepad.dart';
import '../../app/tokens.dart';
import '../../app/widgets/circle_icon_button.dart';
import '../../app/widgets/glass_panel.dart';
import '../../app/widgets/pill.dart';
import '../../app/widgets/primary_button.dart';
import '../../app/widgets/pulse_box.dart';
import '../../app/widgets/section_label.dart';
import '../../core/api/models.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/downloads/local_state.dart';
import '../../core/downloads/selection.dart';
import '../../core/downloads/space.dart';
import '../../core/downloads/storage_settings.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/launch/emulator_catalog.dart';
import '../../core/launch/emulator_settings.dart';
import '../../core/launch/launch_plan.dart';
import '../../core/launch/launch_request.dart';
import '../../core/platform/launcher_port.dart';
import '../../core/session/providers.dart';
import '../downloads/providers.dart';
import '../library/providers.dart';
import '../library/widgets/cover_image.dart';
import 'delete_dialog.dart';
import 'providers.dart';

const roleLabels = {
  FileRole.base: 'Game',
  FileRole.update: 'Update',
  FileRole.dlc: 'DLC',
  FileRole.disc: 'Disc',
  FileRole.support: 'Other',
  FileRole.mod: 'Mod',
  FileRole.other: 'Other',
};

String labelFor(GameFileModel file) => file.role == FileRole.disc
    ? '${roleLabels[FileRole.disc]} ${file.discNumber ?? ''}'.trim()
    : roleLabels[file.role]!;

/// What really comes off the network: selected files not already on disk.
int bytesToFetch(GameDetail game, Set<int> selected, LocalGameState local) {
  final present = {for (final p in local.presentPaths) p.split('/').last};
  return game.files
      .where((f) => selected.contains(f.id) && !present.contains(f.name))
      .fold(0, (sum, f) => sum + f.size);
}

const _heroHeight = 260.0;

/// Will the bottom bar hand the focus to something? Play (or "Set up
/// emulator") and Delete on an installed game, the transfer controls while a
/// download runs, and otherwise the Download button — that one only when it
/// is enabled. Pure, so the screen can ask before the bar is built.
bool bottomBarTakesFocus(
  GameDetail game,
  LocalGameState local, {
  required bool offline,
  required bool transferring,
}) {
  if (local.status == InstallStatus.installed || transferring) return true;
  return !offline &&
      bytesToFetch(game, defaultSelection(game.files), local) > 0;
}

class GameDetailScreen extends ConsumerStatefulWidget {
  const GameDetailScreen({super.key, required this.gameId});

  final int gameId;

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen> {
  final _backNode = FocusNode();

  @override
  void dispose() {
    _backNode.dispose();
    super.dispose();
  }

  /// Requested after the frame rather than through `autofocus`: autofocus
  /// only counts the moment a node is registered, and whether the bottom bar
  /// has anything to offer is answered a few frames later.
  void _focusBackIfIdle() {
    if (mounted && FocusScope.of(context).focusedChild == null) {
      _backNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(gameDetailProvider(widget.gameId));
    final local = ref.watch(localStateProvider(widget.gameId)).value;
    final transferring = ref
        .watch(activeDownloadsProvider)
        .any(
          (p) =>
              p.gameId == widget.gameId &&
              p.status != GameProgressStatus.complete,
        );
    // Offline, or nothing left to fetch: the bottom bar's only button is
    // disabled and takes no focus, so Back becomes the landing spot.
    if (detail.value case final game? when local != null) {
      if (!bottomBarTakesFocus(
        game,
        local,
        offline: ref.watch(isOfflineProvider),
        transferring: transferring,
      )) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _focusBackIfIdle(),
        );
      }
    }
    // Back sits above all three branches — the screen has no AppBar, and the
    // skeleton and error states used to offer no way out but the system
    // gesture (with three-button navigation: none at all).
    return Stack(
      fit: StackFit.expand,
      children: [
        detail.when(
          loading: () => const Scaffold(body: _DetailSkeleton()),
          error: (error, _) => Scaffold(
            body: _Error(
              message: humanizeError(error),
              onRetry: () =>
                  ref.invalidate(gameDetailProvider(widget.gameId)),
            ),
          ),
          data: (game) => _Detail(game: game),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          child: CircleIconButton(
            key: const Key('back-button'),
            focusNode: _backNode,
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => context.pop(),
          ),
        ),
      ],
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.game});

  final GameDetail game;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  late final Set<int> _selected = defaultSelection(widget.game.files);

  /// The Play control, when the game is installed — Start goes through it.
  final _playKey = GlobalKey<_PlayControlState>();

  GameDetail get game => widget.game;

  /// Start: Play when the game is installed, otherwise the download the
  /// bottom bar is offering (nothing when there is none).
  void _primaryAction() {
    if (isTyping()) return;
    if (_playKey.currentState case final play?) {
      play.playNow();
      return;
    }
    final state = ref.read(localStateProvider(game.id)).value;
    if (state == null ||
        ref.read(isOfflineProvider) ||
        bytesToFetch(game, _selected, state) == 0) {
      return;
    }
    _download(state);
  }

  void _toggle(GameFileModel file, bool? on) => setState(() {
        if (on ?? false) {
          _selected.add(file.id);
        } else {
          _selected.remove(file.id);
        }
      });

  Future<void> _download(LocalGameState local) async {
    final session = (await ref.read(sessionProvider.future))!;
    final settings = await ref.read(storageSettingsProvider.future);
    try {
      await ref.read(downloadManagerProvider).downloadGame(
            game: game,
            selectedIds: _selected,
            local: local,
            serverUrl: session.serverUrl,
            authHeaders: {'Authorization': 'Token ${session.token}'},
            settings: settings,
          );
    } on PermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Downloads need file access — '
            'grant the permission in settings',
          ),
        ),
      );
    } on InsufficientSpaceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localStateProvider(game.id));
    final grouped = <String, List<GameFileModel>>{};
    for (final file in game.files) {
      grouped.putIfAbsent(labelFor(file), () => []).add(file);
    }
    return Actions(
      actions: {
        PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(
          onInvoke: (_) {
            _primaryAction();
            return null;
          },
        ),
      },
      child: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Hero(game: game)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            sliver: SliverList.list(
              children: [
                Text(
                  game.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(game.systemName),
                    Pill(formatBytes(game.totalSize)),
                    if (local.value case final state?)
                      if (_statePill(state) case final text?)
                        Pill(text, accent: true),
                  ],
                ),
                const SizedBox(height: 8),
                for (final entry in grouped.entries) ...[
                  SectionLabel(
                    entry.key,
                    trailing: entry.key == roleLabels[FileRole.update]
                        ? 'newest by default'
                        : null,
                  ),
                  for (final file in entry.value)
                    _FileRow(
                      file: file,
                      selected: _selected.contains(file.id),
                      onChanged: (on) => _toggle(file, on),
                    ),
                  if (entry.key == roleLabels[FileRole.mod]) _ModsHint(game: game),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: local.when(
        loading: () => const _BottomBar(
          child: PrimaryButton(label: 'Checking files...', onPressed: null),
        ),
        error: (e, _) => _BottomBar(
          child: Text(
            humanizeError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextDim),
          ),
        ),
        data: (state) => _BottomBar(
          child: _Actions(
            game: game,
            state: state,
            playKey: _playKey,
            toFetch: bytesToFetch(game, _selected, state),
            offline: ref.watch(isOfflineProvider),
            onDownload: () => _download(state),
            onDelete: () => confirmAndDelete(context, ref, game, state),
          ),
        ),
      ),
      ),
    );
  }

  static String? _statePill(LocalGameState state) {
    if (state.updateAvailable) return 'Update available';
    return switch (state.status) {
      InstallStatus.installed => 'Installed',
      InstallStatus.partial => 'Partial',
      InstallStatus.none => null,
    };
  }
}

/// Saturation 1.4 for the blurred backdrop — the standard saturation matrix
/// on Rec. 709 luminance, so a cover washed out by the blur regains its color.
const _saturation = <double>[
  1.31496, -0.28608, -0.02888, 0, 0, //
  -0.08504, 1.11392, -0.02888, 0, 0, //
  -0.08504, -0.28608, 1.37112, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Blurred cover as the backdrop, the sharp one on top; back is a separate,
/// pinned widget above the scroll (see `GameDetailScreen.build`).
class _Hero extends ConsumerWidget {
  const _Hero({required this.game});

  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = game.hasCover ? ref.watch(apiClientProvider) : null;
    final url = client?.coverUrl(game.id, size: 'full') ?? '';
    final headers = client?.authHeaders ?? const <String, String>{};
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (game.hasCover)
            // Scale 1.15 under ClipRect: near the edges the blur pulls in
            // transparency from beyond the image and leaves a bright rim —
            // the enlarged image pushes it out of frame.
            ClipRect(
              child: Transform.scale(
                scale: 1.15,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_saturation),
                    child: CoverImage(
                      title: game.title,
                      url: url,
                      headers: headers,
                      hasCover: true,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(gradient: coverPlaceholderGradient),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x80000000), Colors.transparent, kBgMid],
                stops: [0.0, 0.35, 1.0],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Hero(
                tag: 'cover-${game.id}',
                child: Container(
                  height: 150,
                  width: 150 * 3 / 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusCover),
                    border: Border.all(color: kGlassBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 40,
                        offset: Offset(0, 20),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CoverImage(
                    title: game.title,
                    url: url,
                    headers: headers,
                    hasCover: game.hasCover,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the mods land on the device and how to get them into the emulator.
/// Shown under the "Mod" group only — a game without mods has nothing to say.
class _ModsHint extends ConsumerWidget {
  const _ModsHint({required this.game});

  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    final dir = '${settings.dirFor(game.systemCode)}/${game.folder}/mods';
    return GlassPanel(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Install in the emulator: Add mod → pick the zip from $dir',
              style: const TextStyle(color: kTextDim, fontSize: 12, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: dir));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied')),
              );
            },
            child: const Text('Copy path'),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onChanged,
  });

  final GameFileModel file;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: selected ? 1 : 0.55,
        child: GlassPanel(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          onTap: () => onChanged(!selected),
          child: Row(
            children: [
              Checkbox(value: selected, onChanged: onChanged),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kText, fontSize: 14),
                    ),
                    if (file.version.isNotEmpty)
                      Text(
                        file.version,
                        style: const TextStyle(color: kTextDim, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatBytes(file.size),
                style: const TextStyle(color: kTextDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

/// Bottom bar: a gradient into the background, so the list runs under it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, kBgBottom],
            stops: [0.0, 0.4],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: child,
          ),
        ),
      );
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.game,
    required this.state,
    required this.playKey,
    required this.toFetch,
    required this.offline,
    required this.onDownload,
    required this.onDelete,
  });

  final GameDetail game;
  final LocalGameState state;
  final GlobalKey<_PlayControlState> playKey;
  final int toFetch;
  final bool offline;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider).value;
    final dir = settings?.dirFor(game.systemCode);
    final free = settings == null
        ? null
        : ref.watch(freeBytesProvider(settings.baseDir)).value;
    final installed =
        state.status == InstallStatus.installed && !state.updateAvailable;
    final label = state.updateAvailable
        ? 'Download update · ${formatBytes(toFetch)}'
        : 'Download · ${formatBytes(toFetch)}';
    final footer = offline
        ? 'Offline — downloads unavailable'
        : [
            if (free != null) '${formatBytes(free)} free',
            if (dir != null) 'saving to: $dir',
          ].join(' · ');
    // Play sits above the download/delete row: it is what someone opening an
    // installed game came for, and it needs the full width for itself.
    final boot = state.status == InstallStatus.installed ? bootFile(game) : null;
    // A download in flight (or one that failed) owns the bar: progress and
    // its controls replace the Download button until it finishes or is
    // cancelled — the manager drops the entry when the files are in place.
    final transfer = ref
        .watch(activeDownloadsProvider)
        .where((p) => p.gameId == game.id && p.status != GameProgressStatus.complete)
        .firstOrNull;
    // Play owns the focus whenever it is there; otherwise the row below it
    // does (spec §4). The test is the catalogue, not the resolved emulator:
    // that answer arrives a frame or two later, and by then the row below
    // would already have taken the focus and would never hand it back.
    final playing = boot != null && catalogFor(game.systemCode).isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (boot != null) ...[
          _PlayControl(key: playKey, game: game, file: boot),
          const SizedBox(height: 8),
        ],
        if (transfer != null)
          _TransferControls(progress: transfer, autofocus: !playing)
        else if (installed)
          PrimaryButton(
            label: 'Delete from device',
            onPressed: onDelete,
            ghost: true,
            autofocus: !playing,
          )
        else ...[
          PrimaryButton(
            label: label,
            autofocus: !playing,
            onPressed: offline || toFetch == 0 ? null : onDownload,
          ),
          if (state.presentPaths.isNotEmpty)
            TextButton(
              onPressed: onDelete,
              child: const Text(
                'Delete from device',
                style: TextStyle(color: kTextDim),
              ),
            ),
        ],
        if (footer.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            footer,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kTextDim, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Progress bar plus the controls of a download in flight: Pause/Resume and
/// Cancel while it runs, Retry and Cancel once it failed.
class _TransferControls extends ConsumerWidget {
  const _TransferControls({required this.progress, this.autofocus = false});

  final GameProgress progress;

  /// Set when there is no Play button above to take the focus instead.
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);
    final id = progress.gameId;
    final failed = progress.status == GameProgressStatus.failed;
    final paused = progress.status == GameProgressStatus.paused;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            key: const Key('transfer-bar'),
            value: failed ? 1 : progress.progress.clamp(0.0, 1.0),
            minHeight: 6,
            color: failed ? kDanger : kAccent,
            backgroundColor: kGlassBorder,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          progressSubtitle(progress),
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: failed
                  ? PrimaryButton(
                      key: const Key('transfer-retry'),
                      label: 'Retry',
                      autofocus: autofocus,
                      onPressed: () => manager.retryGame(id),
                    )
                  : paused
                      ? PrimaryButton(
                          key: const Key('transfer-resume'),
                          label: 'Resume',
                          autofocus: autofocus,
                          onPressed: () => manager.resumeGame(id),
                        )
                      : PrimaryButton(
                          key: const Key('transfer-pause'),
                          label: 'Pause',
                          ghost: true,
                          autofocus: autofocus,
                          onPressed: () => manager.pauseGame(id),
                        ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton(
                key: const Key('transfer-cancel'),
                label: 'Cancel',
                ghost: true,
                onPressed: () => manager.cancelGame(id),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Play, or the way to get an emulator set up. Nothing at all while the
/// device is still being asked which emulators it has — a button that
/// flashes "Set up emulator" on every open would only mislead.
class _PlayControl extends ConsumerStatefulWidget {
  const _PlayControl({super.key, required this.game, required this.file});

  final GameDetail game;
  final GameFileModel file;

  @override
  ConsumerState<_PlayControl> createState() => _PlayControlState();
}

class _PlayControlState extends ConsumerState<_PlayControl> {
  /// A launch is in flight — two quick taps would start the emulator twice.
  bool _busy = false;

  GameDetail get game => widget.game;

  /// Start pressed anywhere on the screen: launch, unless there is no
  /// emulator to launch with or a launch is already in flight.
  void playNow() {
    final spec = ref.read(effectiveEmulatorProvider(game.systemCode)).value;
    if (spec == null || _busy) return;
    _play(spec);
  }

  Future<void> _play(EmulatorSpec spec) async {
    setState(() => _busy = true);
    try {
      final settings = await ref.read(storageSettingsProvider.future);
      final tree = await ref.read(romTreeProvider.future);
      final romPath = settings.pathFor(
        game.systemCode,
        game.folder,
        widget.file.name,
      );
      final LaunchRequest request;
      try {
        request = resolveTemplate(spec: spec, romPath: romPath, tree: tree);
      } on LaunchPlanError {
        _snack('Grant folder access in Settings → Emulators');
        return;
      }
      String? error;
      try {
        error = await ref.read(launcherPortProvider).launch(request);
      } catch (e) {
        // The channel wraps anything the Kotlin handler throws into a
        // PlatformException; a snackbar beats an unhandled async error.
        error = e is PlatformException ? (e.message ?? e.code) : '$e';
      }
      if (error != null) _snack("Couldn't start ${spec.name}: $error");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // A system the catalogue knows nothing about: the Emulators screen would
    // only repeat that, so there is nowhere to send anyone.
    if (catalogFor(game.systemCode).isEmpty) {
      return const Text(
        'No emulator configured',
        textAlign: TextAlign.center,
        style: TextStyle(color: kTextDim, fontSize: 13),
      );
    }
    final emulator = ref.watch(effectiveEmulatorProvider(game.systemCode));
    if (emulator.isLoading) return const SizedBox(height: 48);
    final spec = emulator.value;
    if (spec == null) {
      return TextButton(
        key: const Key('setup-emulator'),
        autofocus: true,
        onPressed: () => context.go('/settings/emulators'),
        child: const Text('Set up emulator'),
      );
    }
    return PrimaryButton(
      key: const Key('play-button'),
      autofocus: true,
      label: 'Play',
      icon: Icons.play_arrow_rounded,
      busy: _busy,
      onPressed: () => _play(spec),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextDim),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: PrimaryButton(
                  label: 'Retry',
                  autofocus: true,
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: const [
          PulseBox(height: _heroHeight, radius: BorderRadius.zero),
          Padding(
            padding: EdgeInsets.fromLTRB(60, 18, 60, 8),
            child: PulseBox(height: 24),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 110),
            child: PulseBox(height: 22),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, 0),
            child: PulseBox(height: 52),
          ),
        ],
      );
}
