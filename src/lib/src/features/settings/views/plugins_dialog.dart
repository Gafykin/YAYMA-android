import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yayma/src/features/core/providers/notification_provider.dart';
import 'package:yayma/src/features/core/theme/app_tokens.dart';
import 'package:yayma/src/features/core/views/widgets/common_ui.dart';
import 'package:yayma/src/rust/api/plugins.dart' as rust;

InputDecoration _fieldDecoration(ColorScheme cs, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.24)),
    filled: true,
    fillColor: cs.onSurface.withValues(alpha: 0.05),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide.none,
    ),
  );
}

void _notify(rust.PluginActionDto result) {
  if (result.ok) {
    showAppSuccess(result.message);
  } else {
    showAppError(result.message);
  }
}

/// Управление плагинами: список, включение/выключение, обновление, удаление,
/// установка по ссылке или из JSON-файла.
///
/// Плагин подменяет аудиофайл трека по списку «id трека → ссылка на mp3».
class PluginsDialog extends StatefulWidget {
  const PluginsDialog({super.key});

  static void show(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => const PluginsDialog(),
      ),
    );
  }

  @override
  State<PluginsDialog> createState() => _PluginsDialogState();
}

class _PluginsDialogState extends State<PluginsDialog> {
  List<rust.PluginDto>? _plugins;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final plugins = await rust.pluginList();
    if (!mounted) return;
    setState(() {
      _plugins = plugins;
      _loading = false;
    });
  }

  Future<void> _run(Future<rust.PluginActionDto> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _notify(await action());
    } on Object catch (e) {
      showAppError('Ошибка: $e');
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _installFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AppDialog(
          title: 'Плагин по ссылке',
          contentWidth: 460,
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: TextStyle(color: cs.onSurface),
            decoration: _fieldDecoration(cs, 'https://…/plugin.json'),
          ),
          actions: [
            AppDialog.cancelButton(context),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Установить'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    await _run(() => rust.pluginInstallFromUrl(url: url));
  }

  /// Готовый список замен сообщества FckCensor (формат {"tracks": {id: mp3}}).
  static const _fckCensorUrl =
      'https://raw.githubusercontent.com/Hazzz895/FckCensorData/refs/heads/main/list.json';

  Future<void> _installFckCensor() =>
      _run(() => rust.pluginInstallFromUrl(url: _fckCensorUrl));

  Future<void> _installFromFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || files.single.path == null) return;
    final file = files.single;
    await _run(() async {
      final json = await File(file.path!).readAsString();
      return rust.pluginInstallFromJson(json: json, fileName: file.name);
    });
  }

  Widget _pluginTile(ColorScheme cs, rust.PluginDto plugin) {
    final subtitle = [
      '${plugin.tracksCount} треков',
      if (plugin.description.isNotEmpty) plugin.description,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: plugin.enabled ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          if (plugin.sourceUrl != null)
            IconButton(
              tooltip: 'Обновить список',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(() => rust.pluginRefresh(id: plugin.id)),
                    ),
            ),
          IconButton(
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _busy
                ? null
                : () => unawaited(
                    _run(() => rust.pluginRemove(id: plugin.id)),
                  ),
          ),
          Switch(
            value: plugin.enabled,
            activeThumbColor: cs.primary,
            onChanged: _busy
                ? null
                : (v) => unawaited(
                    _run(
                      () => rust.pluginSetEnabled(id: plugin.id, enabled: v),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plugins = _plugins ?? const <rust.PluginDto>[];

    return AppDialog(
      title: 'Плагины',
      titleIcon: Icons.extension_rounded,
      titleStyle: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      contentWidth: 500,
      content: _loading
          ? const SizedBox(
              height: 150,
              child: Center(child: M3ELoadingIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Плагин подменяет аудиофайл трека по списку «id трека → '
                  'ссылка на mp3» (как аддон FckCensor). Формат файла: '
                  '{"id трека": "https://…/файл.mp3"}. Подключайте только '
                  'списки, которым доверяете. Ручную замену для одного '
                  'трека можно задать в его меню «три точки».',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => unawaited(_installFromUrl()),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('По ссылке'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _busy ? null : () => unawaited(_installFckCensor()),
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('FckCensor'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => unawaited(_installFromFile()),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Из файла'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (plugins.isEmpty)
                  Text(
                    'Плагинов пока нет.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: plugins.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _pluginTile(cs, plugins[index]),
                    ),
                  ),
              ],
            ),
      actions: [AppDialog.closeButton(context)],
    );
  }
}

/// Ручная замена аудио одного трека (аналог «подмены через контекстное меню»
/// в FckCensor). Действует со следующего запуска трека.
class TrackOverrideDialog extends StatefulWidget {
  const TrackOverrideDialog({
    required this.trackId,
    required this.title,
    super.key,
  });

  final String trackId;
  final String title;

  static void show(BuildContext context, String trackId, String title) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => TrackOverrideDialog(trackId: trackId, title: title),
      ),
    );
  }

  @override
  State<TrackOverrideDialog> createState() => _TrackOverrideDialogState();
}

class _TrackOverrideDialogState extends State<TrackOverrideDialog> {
  final _controller = TextEditingController();
  final _vkIdController = TextEditingController();
  final _vkTokenController = TextEditingController();
  final _vkUserAgentController = TextEditingController();
  String _source = 'url';
  bool _saving = false;
  bool _loading = true;
  bool _hasOverride = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _vkIdController.dispose();
    _vkTokenController.dispose();
    _vkUserAgentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final current = await rust.pluginGetTrackOverride(trackId: widget.trackId);
    if (!mounted) return;
    setState(() {
      _hasOverride = current != null;
      _controller.text = current ?? '';
      _source = (current != null && current.startsWith('https://')) ? 'url' : 'url';
      _loading = false;
    });
  }

  Future<void> _save(String? url) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      var resolvedUrl = url;
      if (url != null && _source == 'vk') {
        resolvedUrl = await _resolveVkAudioUrl();
      }
      final result = await rust.pluginSetTrackOverride(
        trackId: widget.trackId,
        url: resolvedUrl,
      );
      _notify(result);
      if (result.ok && mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) showAppError('Не удалось получить аудио VK: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _resolveVkAudioUrl() async {
    final audioId = _vkIdController.text.trim();
    final token = _vkTokenController.text.trim();
    final userAgent = _vkUserAgentController.text.trim();
    if (!RegExp(r'^-?\d+_\d+(?:_[A-Za-z0-9]+)?$').hasMatch(audioId)) {
      throw const FormatException('ID должен иметь формат owner_id_audio_id');
    }
    if (token.isEmpty || userAgent.isEmpty) {
      throw const FormatException('Укажи VK-токен и User-Agent');
    }

    final uri = Uri.https('api.vk.com', '/method/audio.getById', {
      'access_token': token,
      'audios': audioId,
      'v': '5.95',
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('VK вернул HTTP ' + response.statusCode.toString());
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Неожиданный ответ VK');
      }
      if (decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final code = error['error_code'] ?? '?';
        final message = error['error_msg'] ?? 'неизвестная ошибка';
        throw FormatException('VK API ' + code.toString() + ': ' + message.toString());
      }
      final items = decoded['response'];
      if (items is! List || items.isEmpty || items.first is! Map) {
        throw const FormatException('VK не вернул аудиозапись');
      }
      final audioUrl = (items.first as Map)['url'];
      if (audioUrl is! String || !audioUrl.startsWith('https://')) {
        throw const FormatException(
          'Для этой записи VK не вернул доступную HTTPS-ссылку',
        );
      }
      return audioUrl;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppDialog(
      title: 'Подмена аудио',
      titleIcon: Icons.swap_horiz_rounded,
      titleStyle: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      contentWidth: 460,
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: M3ELoadingIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Выбери источник аудио для замены. Изменение вступит в силу '
                  'при следующем запуске трека.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _source,
                  decoration: _fieldDecoration(cs, 'Источник аудио'),
                  items: const [
                    DropdownMenuItem(value: 'url', child: Text('Прямая ссылка')),
                    DropdownMenuItem(value: 'vk', child: Text('VK Audio')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _source = value ?? 'url'),
                ),
                const SizedBox(height: 12),
                if (_source == 'url')
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    style: TextStyle(color: cs.onSurface),
                    decoration: _fieldDecoration(cs, 'https://…/track.mp3'),
                  )
                else ...[
                  TextField(
                    controller: _vkIdController,
                    style: TextStyle(color: cs.onSurface),
                    decoration: _fieldDecoration(cs, 'ID VK: owner_id_audio_id'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _vkTokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TextStyle(color: cs.onSurface),
                    decoration: _fieldDecoration(cs, 'VK Audio API token'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _vkUserAgentController,
                    autocorrect: false,
                    style: TextStyle(color: cs.onSurface),
                    decoration: _fieldDecoration(cs, 'User-Agent из токен-клиента'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Токен используется только для запроса и не сохраняется '
                    'приложением. VK может выдавать временные аудиоссылки: '
                    'если они истекут, подмена вернётся к оригиналу.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ],
            ),
      actions: [
        AppDialog.cancelButton(context),
        if (_hasOverride)
          TextButton(
            onPressed: _loading || _saving ? null : () => unawaited(_save(null)),
            child: const Text('Вернуть оригинал'),
          ),
        ElevatedButton(
          onPressed: _loading || _saving
              ? null
              : () => unawaited(
                  _save(_source == 'url' ? _controller.text.trim() : 'vk://resolve'),
                ),
          child: Text(_saving ? 'Получение…' : 'Сохранить'),
        ),
      ],
    );
  }
}
).hasMatch(audioId)) {
      throw const FormatException('ID должен иметь формат owner_id_audio_id');
    }
    if (token.isEmpty || userAgent.isEmpty) {
      throw const FormatException('Укажи VK-токен и User-Agent');
    }

    final uri = Uri.https('api.vk.com', '/method/audio.getById', {
      'access_token': token,
      'audios': audioId,
      'v': '5.199',
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('VK вернул HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Неожиданный ответ VK');
      }
      if (decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final code = error['error_code'] ?? '?';
        final message = error['error_msg'] ?? 'неизвестная ошибка';
        throw FormatException('VK API ${code}: ${message}');
      }
      final items = decoded['response'];
      if (items is! List || items.isEmpty || items.first is! Map) {
        throw const FormatException('VK не вернул аудиозапись');
      }
      final audioUrl = (items.first as Map)['url'];
      if (audioUrl is! String || !audioUrl.startsWith('https://')) {
        throw const FormatException(
          'Для этой записи VK не вернул доступную HTTPS-ссылку',
        );
      }
      return audioUrl;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppDialog(
      title: 'Подмена аудио',
      titleIcon: Icons.swap_horiz_rounded,
      titleStyle: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
      contentWidth: 460,
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: M3ELoadingIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ссылка на mp3-файл, который будет играть вместо '
                  'оригинала. Заменится со следующего запуска трека.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: cs.onSurface),
                  decoration: _fieldDecoration(cs, 'https://…/track.mp3'),
                ),
              ],
            ),
      actions: [
        AppDialog.cancelButton(context),
        if (_hasOverride)
          TextButton(
            onPressed: () => unawaited(_save(null)),
            child: const Text('Вернуть оригинал'),
          ),
        ElevatedButton(
          onPressed: _loading
              ? null
              : () => unawaited(_save(_controller.text.trim())),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
