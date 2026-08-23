import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'app_toast.dart';
import 'database.dart';
import 'defect_parts.dart';

class OrderDefectsSheet extends StatefulWidget {
  final int orderId;
  final String workshop;

  const OrderDefectsSheet({
    super.key,
    required this.orderId,
    this.workshop = '',
  });

  static Future<bool?> open(
    BuildContext context, {
    required int orderId,
    String workshop = '',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderDefectsSheet(orderId: orderId, workshop: workshop),
    );
  }

  @override
  State<OrderDefectsSheet> createState() => _OrderDefectsSheetState();
}

class _OrderDefectsSheetState extends State<OrderDefectsSheet> {
  static const _allTab = 'Все';

  final _description = TextEditingController();
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _defects = [];
  final List<String> _newPhotos = [];
  final Set<int> _expandedIds = {};
  /// Кэш decoded JPEG — иначе при каждом setState новый Uint8List → мигание Image.memory.
  final Map<String, Uint8List> _photoBytes = {};
  String _partFilter = _allTab;
  bool _loading = true;
  bool _saving = false;
  bool _loadBusy = false;
  String _defectsFp = '';
  int _lastSeenRev = -1;

  @override
  void initState() {
    super.initState();
    _description.addListener(() {
      if (mounted) setState(() {});
    });
    _lastSeenRev = DatabaseHelper.dataRevision.value;
    DatabaseHelper.dataRevision.addListener(_onDataRevision);
    _load();
  }

  @override
  void dispose() {
    DatabaseHelper.dataRevision.removeListener(_onDataRevision);
    _description.dispose();
    super.dispose();
  }

  void _onDataRevision() {
    final rev = DatabaseHelper.dataRevision.value;
    if (rev == _lastSeenRev) return;
    _lastSeenRev = rev;
    if (!_saving) unawaited(_load(soft: true));
  }

  String get _draftPart => detectDefectPart(_description.text);

  String _fingerprint(List<Map<String, dynamic>> defects) {
    final buf = StringBuffer();
    for (final d in defects) {
      final id = d['id'];
      final desc = d['description'] ?? '';
      final photos = (d['photos'] as List?) ?? const [];
      buf.write('$id|$desc|${photos.length};');
      for (final p in photos) {
        final b64 = (p is Map ? p['photo_b64'] : null)?.toString() ?? '';
        buf.write('${b64.length}:');
        if (b64.length >= 24) {
          buf.write(b64.substring(0, 12));
          buf.write(b64.substring(b64.length - 12));
        } else {
          buf.write(b64);
        }
        buf.write(',');
      }
    }
    return buf.toString();
  }

  Uint8List? _bytesFor(String b64) {
    if (b64.isEmpty) return null;
    final cached = _photoBytes[b64];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(b64);
      _photoBytes[b64] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load({bool soft = false}) async {
    if (_loadBusy) return;
    _loadBusy = true;
    try {
      final defects = await DatabaseHelper().getOrderDefects(widget.orderId);
      if (!mounted) return;
      final fp = _fingerprint(defects);
      if (soft && fp == _defectsFp && !_loading) {
        return;
      }
      setState(() {
        _defects = defects;
        _defectsFp = fp;
        _loading = false;
        if (!soft && defects.isNotEmpty) {
          final id = (defects.first['id'] as num?)?.toInt();
          if (id != null) _expandedIds.add(id);
        }
        // Новые id с телефона — раскрыть последний.
        if (soft && defects.isNotEmpty) {
          final id = (defects.first['id'] as num?)?.toInt();
          if (id != null) _expandedIds.add(id);
        }
        final groups = groupDefectsByPart(defects, (d) => d['description']?.toString() ?? '');
        final labels = {_allTab, ...groups.map((e) => e.key)};
        if (!labels.contains(_partFilter)) _partFilter = _allTab;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!soft) showAppToast(context, 'Не удалось загрузить дефекты: $e');
    } finally {
      _loadBusy = false;
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final photo = await _picker.pickImage(
          source: source,
          maxWidth: 1280,
          imageQuality: 70,
        );
        if (photo != null) {
          _newPhotos.add(base64Encode(await photo.readAsBytes()));
        }
      } else {
        final picked = await _picker.pickMultiImage(
          maxWidth: 1280,
          imageQuality: 70,
        );
        for (final photo in picked) {
          _newPhotos.add(base64Encode(await photo.readAsBytes()));
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Камера/галерея: $e');
    }
  }

  Future<void> _add() async {
    final description = _description.text.trim();
    if (description.isEmpty && _newPhotos.isEmpty) return;
    final hadPhotos = _newPhotos.isNotEmpty;
    setState(() => _saving = true);
    try {
      final part = detectDefectPart(description);
      final id = await DatabaseHelper().addOrderDefect(
        orderId: widget.orderId,
        workshop: widget.workshop,
        description: description,
        photosB64: List<String>.from(_newPhotos),
      );
      _description.clear();
      _newPhotos.clear();
      _expandedIds.add(id);
      // После сохранения сразу открыть вкладку элемента.
      if (part != kDefectPartOther) _partFilter = part;
      await _load();
      if (mounted) {
        final msg = !hadPhotos
            ? (part == kDefectPartOther ? 'Дефект сохранён' : 'Дефект → $part')
            : (part == kDefectPartOther ? 'Фото сохранены' : 'Фото сохранены → $part');
        showAppToast(context, msg);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Ошибка сохранения: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openPhoto(String b64) {
    final bytes = _bytesFor(b64);
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(String b64, {VoidCallback? onDelete, VoidCallback? onTap}) {
    final bytes = _bytesFor(b64);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: bytes == null ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: bytes == null
                  ? const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(Icons.broken_image, color: AppColors.textDim),
                    )
                  : Image.memory(
                      bytes,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // Stable identity across rebuilds while typing / soft reload.
                      key: ValueKey<int>(identityHashCode(bytes)),
                    ),
            ),
          ),
        ),
        if (onDelete != null)
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.cancel, color: AppColors.danger, size: 20),
              onPressed: onDelete,
            ),
          ),
      ],
    );
  }

  String _descOf(Map<String, dynamic> defect) {
    final d = defect['description']?.toString().trim() ?? '';
    return d.isEmpty ? 'Без описания' : d;
  }

  List<Map<String, dynamic>> get _visibleDefects {
    if (_partFilter == _allTab) return _defects;
    return _defects
        .where((d) => detectDefectPart(d['description']?.toString() ?? '') == _partFilter)
        .toList();
  }

  Widget _partChip(String label, int count, {required bool selected}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(
          count > 0 ? '$label · $count' : label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textMuted,
          ),
        ),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface2,
        checkmarkColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        onSelected: (_) => setState(() => _partFilter = label),
      ),
    );
  }

  Widget _defectTile(Map<String, dynamic> defect) {
    final id = (defect['id'] as num).toInt();
    final photos = (defect['photos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final open = _expandedIds.contains(id);
    final workshop = defect['workshop']?.toString() ?? '';
    final part = detectDefectPart(defect['description']?.toString() ?? '');

    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (open) {
            _expandedIds.remove(id);
          } else {
            _expandedIds.add(id);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _descOf(defect),
                          style: GoogleFonts.manrope(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_partFilter == _allTab && part != kDefectPartOther)
                          Text(
                            part,
                            style: GoogleFonts.manrope(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${photos.length} фото',
                        style: GoogleFonts.manrope(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
                    onPressed: () async {
                      try {
                        await DatabaseHelper().deleteOrderDefect(id);
                        _expandedIds.remove(id);
                        await _load();
                      } catch (e) {
                        if (!mounted) return;
                        showAppToast(context, 'Удаление: $e');
                      }
                    },
                  ),
                ],
              ),
              if (workshop.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 28, bottom: 4),
                  child: Text(
                    workshop,
                    style: GoogleFonts.manrope(color: AppColors.primary, fontSize: 12),
                  ),
                ),
              if (open) ...[
                if (photos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 4),
                    child: Text(
                      'Без фото',
                      style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: photos.map((p) {
                        final b64 = p['photo_b64']?.toString() ?? '';
                        return _thumb(b64, onTap: () => _openPhoto(b64));
                      }).toList(),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final groups = groupDefectsByPart(_defects, (d) => d['description']?.toString() ?? '');
    final visible = _visibleDefects;
    final draft = _description.text.trim();
    final draftPart = draft.isEmpty ? null : _draftPart;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: maxH,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Дефекты${widget.workshop.isEmpty ? '' : ' · ${widget.workshop}'}',
                    style: GoogleFonts.manrope(
                      color: AppColors.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _description,
                    maxLines: 2,
                    style: GoogleFonts.manrope(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'Описание дефекта',
                      hintText: 'напр. капот, скол',
                      isDense: true,
                      helperText: draftPart == null
                          ? 'Элемент из текста → автогруппировка (капот, крыло, стойка…)'
                          : draftPart == kDefectPartOther
                              ? 'Элемент не распознан → вкладка «Прочее»'
                              : 'Группа: $draftPart',
                      helperStyle: GoogleFonts.manrope(
                        color: draftPart != null && draftPart != kDefectPartOther
                            ? AppColors.primary
                            : AppColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._newPhotos.asMap().entries.map(
                            (e) => _thumb(
                              e.value,
                              onDelete: () => setState(() => _newPhotos.removeAt(e.key)),
                              onTap: () => _openPhoto(e.value),
                            ),
                          ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Камера'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Галерея'),
                      ),
                    ],
                  ),
                  if (_newPhotos.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _newPhotos.length == 1
                          ? '1 фото в черновике — нажмите «Сохранить фото»'
                          : '${_newPhotos.length} фото в черновике — нажмите «Сохранить фото»',
                      style: GoogleFonts.manrope(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _saving || (draft.isEmpty && _newPhotos.isEmpty) ? null : _add,
                      icon: Icon(
                        _newPhotos.isNotEmpty ? Icons.save_alt_rounded : Icons.add_rounded,
                        size: 20,
                      ),
                      label: Text(
                        _saving
                            ? 'Сохраняем…'
                            : _newPhotos.isNotEmpty
                                ? 'Сохранить фото'
                                : 'Сохранить дефект',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  ),
                  const Divider(height: 22),
                  Text(
                    'По элементам (${_defects.length})',
                    style: GoogleFonts.manrope(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_defects.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _partChip(_allTab, _defects.length, selected: _partFilter == _allTab),
                          ...groups.map(
                            (g) => _partChip(
                              g.key,
                              g.value.length,
                              selected: _partFilter == g.key,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _defects.isEmpty
                      ? Center(
                          child: Text(
                            'Дефекты не зафиксированы',
                            style: GoogleFonts.manrope(color: AppColors.textDim),
                          ),
                        )
                      : visible.isEmpty
                          ? Center(
                              child: Text(
                                'В «$_partFilter» пусто',
                                style: GoogleFonts.manrope(color: AppColors.textDim),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, index) => _defectTile(visible[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
