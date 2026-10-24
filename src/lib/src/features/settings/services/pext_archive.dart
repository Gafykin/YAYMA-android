import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Минимальный читатель ZIP для файлов аддонов `.pext` (метод store или deflate).
///
/// Нужен только чтобы достать `metadata.json` и `script.js`; сторонние пакеты
/// для этого не подключаем.
class PextArchive {
  PextArchive._(this._bytes, this._entries);

  final Uint8List _bytes;
  final Map<String, _ZipEntry> _entries;

  static const _eocdSignature = 0x06054b50;
  static const _centralSignature = 0x02014b50;
  static const _localSignature = 0x04034b50;

  /// Разбирает архив. Бросает [FormatException], если это не ZIP.
  static PextArchive parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    // Запись конца центрального каталога ищем с конца файла.
    var eocd = -1;
    final lowest = bytes.length - 22 - 0xFFFF;
    for (var i = bytes.length - 22; i >= 0 && i >= lowest; i--) {
      if (data.getUint32(i, Endian.little) == _eocdSignature) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const FormatException('это не архив .pext (не найден конец ZIP)');
    }

    final count = data.getUint16(eocd + 10, Endian.little);
    var pos = data.getUint32(eocd + 16, Endian.little);
    final entries = <String, _ZipEntry>{};

    for (var i = 0; i < count; i++) {
      if (pos + 46 > bytes.length ||
          data.getUint32(pos, Endian.little) != _centralSignature) {
        throw const FormatException('архив .pext повреждён');
      }
      final method = data.getUint16(pos + 10, Endian.little);
      final compressedSize = data.getUint32(pos + 20, Endian.little);
      final nameLength = data.getUint16(pos + 28, Endian.little);
      final extraLength = data.getUint16(pos + 30, Endian.little);
      final commentLength = data.getUint16(pos + 32, Endian.little);
      final localOffset = data.getUint32(pos + 42, Endian.little);
      if (pos + 46 + nameLength > bytes.length) {
        throw const FormatException('архив .pext повреждён');
      }
      final name = utf8
          .decode(bytes.sublist(pos + 46, pos + 46 + nameLength),
              allowMalformed: true)
          .replaceAll('\\', '/');
      entries[name] = _ZipEntry(
        method: method,
        compressedSize: compressedSize,
        localOffset: localOffset,
      );
      pos += 46 + nameLength + extraLength + commentLength;
    }
    return PextArchive._(bytes, entries);
  }

  bool contains(String name) => _entries.containsKey(name);

  /// Содержимое файла как текст UTF-8 (или `null`, если файла нет в архиве).
  String? readText(String name) {
    final bytes = readBytes(name);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  Uint8List? readBytes(String name) {
    final entry = _entries[name];
    if (entry == null) return null;

    final data = ByteData.sublistView(_bytes);
    final local = entry.localOffset;
    if (local + 30 > _bytes.length ||
        data.getUint32(local, Endian.little) != _localSignature) {
      throw const FormatException('архив .pext повреждён');
    }
    final nameLength = data.getUint16(local + 26, Endian.little);
    final extraLength = data.getUint16(local + 28, Endian.little);
    final start = local + 30 + nameLength + extraLength;
    final end = start + entry.compressedSize;
    if (end > _bytes.length) {
      throw const FormatException('архив .pext повреждён');
    }
    final raw = Uint8List.sublistView(_bytes, start, end);

    switch (entry.method) {
      case 0:
        return raw;
      case 8:
        return Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
      default:
        throw FormatException(
          'неподдерживаемый способ сжатия в архиве (${entry.method})',
        );
    }
  }
}

class _ZipEntry {
  const _ZipEntry({
    required this.method,
    required this.compressedSize,
    required this.localOffset,
  });

  final int method;
  final int compressedSize;
  final int localOffset;
}
