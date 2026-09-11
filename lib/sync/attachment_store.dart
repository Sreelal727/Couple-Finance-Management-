import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Attachment bytes live in `<documents>/attachments/<id>.<ext>`. Rows describing
/// them sync like any other record; bytes are fetched on demand after rows
/// have been exchanged.
class AttachmentStore {
  AttachmentStore(this._repo, {Directory? dir}) : _dirOverride = dir;

  final Repository _repo;
  final Directory? _dirOverride;
  Directory? _dir;

  Future<Directory> directory() async {
    if (_dir != null) return _dir!;
    final base = _dirOverride ?? await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'attachments'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> fileFor(Attachment a) async => File(p.join((await directory()).path, a.fileName));

  Future<bool> hasBytes(Attachment a) async => (await fileFor(a)).exists();

  Future<Uint8List?> read(Attachment a) async {
    final f = await fileFor(a);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// Saves new bytes for [txnId] and records the attachment row.
  Future<Attachment> add(String txnId, Uint8List bytes, {String mime = 'image/jpeg'}) async {
    final meta = _repo.newMeta();
    final ext = mime == 'image/png' ? 'png' : 'jpg';
    final att = Attachment(
      meta: meta,
      txnId: txnId,
      fileName: '${meta.id}.$ext',
      mime: mime,
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    await (await fileFor(att)).writeAsBytes(bytes, flush: true);
    await _repo.save(att);
    return att;
  }

  /// Stores bytes received from a peer for an attachment row we already have.
  /// Verifies the hash so a corrupted transfer is not kept.
  Future<bool> storeReceived(Attachment a, List<int> bytes) async {
    if (sha256.convert(bytes).toString() != a.sha256) return false;
    await (await fileFor(a)).writeAsBytes(bytes, flush: true);
    return true;
  }

  /// Ids of attachment rows for which this phone has the bytes.
  Future<Set<String>> idsWithBytes() async {
    final all = await _repo.allAttachments();
    final out = <String>{};
    for (final a in all) {
      if (await hasBytes(a)) out.add(a.id);
    }
    return out;
  }

  Future<List<Attachment>> missingBytes() async {
    final all = await _repo.allAttachments();
    final out = <Attachment>[];
    for (final a in all) {
      if (!await hasBytes(a)) out.add(a);
    }
    return out;
  }

  Future<void> delete(Attachment a) async {
    final f = await fileFor(a);
    if (await f.exists()) await f.delete();
    await _repo.softDelete('attachments', a.id);
  }
}
