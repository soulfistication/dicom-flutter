import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dicom/dicom.dart';
import '../state/viewer_controller.dart';
import 'theme.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final ViewerController controller;
  final VoidCallback onBack;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  ViewerController get v => widget.controller;

  Offset? _dragStart;
  Offset? _offsetStart;
  double? _pinchStartScale;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (v.metaOpen) {
        v.closeMetadata();
      } else {
        widget.onBack();
      }
      return KeyEventResult.handled;
    }
    if (v.count > 1) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        v.goToIndex(v.index + 1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        v.goToIndex(v.index - 1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: v,
      builder: (context, _) {
        return Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: Scaffold(
            backgroundColor: AppColors.viewerBg,
            body: Stack(
              children: [
                Column(
                  children: [
                    _ViewerBar(
                      title: v.title,
                      onBack: widget.onBack,
                      onMeta: v.openMetadata,
                    ),
                    Expanded(child: _buildStage()),
                    _Controls(controller: v),
                  ],
                ),
                if (v.metaOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: v.closeMetadata,
                      child: Container(color: Colors.black54),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _MetadataDrawer(controller: v),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStage() {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          final mods = HardwareKeyboard.instance.logicalKeysPressed;
          final zoom = mods.contains(LogicalKeyboardKey.controlLeft) ||
              mods.contains(LogicalKeyboardKey.controlRight) ||
              mods.contains(LogicalKeyboardKey.metaLeft) ||
              mods.contains(LogicalKeyboardKey.metaRight) ||
              mods.contains(LogicalKeyboardKey.altLeft) ||
              mods.contains(LogicalKeyboardKey.altRight);
          if (zoom) {
            final f = math.exp(-signal.scrollDelta.dy * 0.0015);
            v.setScale(v.scale * f);
          } else if (v.count > 1) {
            v.goToIndex(v.index + (signal.scrollDelta.dy > 0 ? 1 : -1));
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: v.resetView,
        onScaleStart: (d) {
          if (d.pointerCount >= 2) {
            _pinchStartScale = v.scale;
          } else {
            _dragStart = d.focalPoint;
            _offsetStart = Offset(v.offset.dx, v.offset.dy);
          }
        },
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2 && _pinchStartScale != null) {
            v.setScale(_pinchStartScale! * d.scale);
            return;
          }
          if (_dragStart == null || _offsetStart == null) return;
          final dx = d.focalPoint.dx - _dragStart!.dx;
          final dy = d.focalPoint.dy - _dragStart!.dy;
          if (v.tool == ViewerTool.pan) {
            v.setOffset(Offset(_offsetStart!.dx + dx, _offsetStart!.dy + dy));
          } else {
            // Approximate movement deltas from focal point delta.
            final last = _dragStart!;
            final mdx = d.focalPoint.dx - last.dx;
            final mdy = d.focalPoint.dy - last.dy;
            _dragStart = d.focalPoint;
            v.adjustWindow(-mdy, mdx);
          }
        },
        onScaleEnd: (_) {
          _dragStart = null;
          _offsetStart = null;
          _pinchStartScale = null;
        },
        child: Container(
          color: AppColors.viewerBg,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (v.loading)
                const Center(
                  child: Text('Loading…',
                      style: TextStyle(color: Colors.white70)),
                )
              else if (v.stageError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      v.stageError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else if (v.displayImage != null)
                Center(
                  child: Transform.translate(
                    offset: Offset(v.offset.dx, v.offset.dy),
                    child: Transform.scale(
                      scale: v.scale,
                      child: RawImage(
                        image: v.displayImage,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ..._overlays(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _overlays() {
    if (v.file == null) return const [];
    final ds = v.file!.dataset;
    final img = v.image;
    final patient =
        (ds.string(Tag.patientName) ?? '').replaceAll('^', ' ').trim();
    final style = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      height: 1.35,
      shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
    );

    final tl = <String>[
      if (patient.isNotEmpty) 'Patient: $patient',
      if (ds.string(Tag.studyDescription) != null)
        ds.string(Tag.studyDescription)!,
    ];
    final tr = <String>[
      if (ds.string(Tag.modality) != null) ds.string(Tag.modality)!,
      if (img != null) '${img.info.columns} × ${img.info.rows}',
    ];
    final bl = <String>[
      if (img != null && img.supportsWindowing)
        'W: ${v.window.width.round()}  L: ${v.window.center.round()}',
      if (v.scale != 1) 'Zoom: ${v.scale.toStringAsFixed(1)}×',
    ];
    final noun = v.navKind == NavKind.frame ? 'Frame' : 'Slice';
    final br = <String>[
      if (v.count > 1) '$noun ${v.index + 1}/${v.count}',
      DicomDictionary.transferSyntaxName(v.file!.transferSyntax),
    ];

    Widget corner(Alignment a, List<String> lines, TextAlign align) {
      return Align(
        alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            lines.join('\n'),
            textAlign: align,
            style: style,
          ),
        ),
      );
    }

    return [
      corner(Alignment.topLeft, tl, TextAlign.left),
      corner(Alignment.topRight, tr, TextAlign.right),
      corner(Alignment.bottomLeft, bl, TextAlign.left),
      corner(Alignment.bottomRight, br, TextAlign.right),
    ];
  }
}

class _ViewerBar extends StatelessWidget {
  const _ViewerBar({
    required this.title,
    required this.onBack,
    required this.onMeta,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onMeta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8C000000),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: onMeta,
                icon: const Icon(Icons.menu, color: Colors.white),
                tooltip: 'Metadata',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final ViewerController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller;
    return Material(
      color: const Color(0x8C000000),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (v.count > 1) ...[
                Row(
                  children: [
                    const Icon(Icons.view_day_outlined,
                        color: Colors.white70, size: 18),
                    Expanded(
                      child: Slider(
                        value: v.index.toDouble(),
                        min: 0,
                        max: (v.count - 1).toDouble(),
                        divisions: v.count > 1 ? v.count - 1 : null,
                        onChanged: (x) => v.goToIndex(x.round()),
                        activeColor: AppColors.accent,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${v.index + 1} / ${v.count}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<ViewerTool>(
                      segments: const [
                        ButtonSegment(
                          value: ViewerTool.wl,
                          label: Text('Window/Level'),
                        ),
                        ButtonSegment(
                          value: ViewerTool.pan,
                          label: Text('Pan'),
                        ),
                      ],
                      selected: {v.tool},
                      onSelectionChanged: (s) => v.setTool(s.first),
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return Colors.white;
                          }
                          return Colors.white70;
                        }),
                        backgroundColor:
                            WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return AppColors.accent;
                          }
                          return Colors.white12;
                        }),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: v.resetView,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'Reset view',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataDrawer extends StatelessWidget {
  const _MetadataDrawer({required this.controller});
  final ViewerController controller;

  @override
  Widget build(BuildContext context) {
    final v = controller;
    final f = v.file!;
    final width = MediaQuery.sizeOf(context).width.clamp(0, 440).toDouble();
    final drawerW = width < 440 ? width * 0.92 : 440.0;

    return Material(
      color: AppColors.surface,
      elevation: 16,
      child: SizedBox(
        width: drawerW,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Metadata',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: v.closeMetadata,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search tag, name or value',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: v.setMetaQuery,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _summaryRow(
                      'Transfer Syntax',
                      DicomDictionary.transferSyntaxName(f.transferSyntax),
                    ),
                    _summaryRow(
                      'Encoding',
                      f.isExplicitVR ? 'Explicit VR' : 'Implicit VR',
                    ),
                    _summaryRow(
                      'Byte Order',
                      f.isLittleEndian ? 'Little Endian' : 'Big Endian',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: v.filteredMetaRows.length,
                  itemBuilder: (context, i) {
                    final r = v.filteredMetaRows[i];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        8 + r.depth * 14.0,
                        8,
                        12,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                r.tag,
                                style: const TextStyle(
                                  fontFamily: 'Menlo',
                                  fontSize: 11,
                                  color: AppColors.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentWeak,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  r.vr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (r.value.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                r.value,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.text2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String k, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: AppColors.text2)),
          ),
          Text(val, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
