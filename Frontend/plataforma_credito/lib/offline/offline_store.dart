import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

abstract interface class OfflineStore {
  Future<String?> read();
  Future<void> write(String contents);
  Future<void> clear();

  static OfflineStore windowsDefault() {
    if (!Platform.isWindows) return MemoryOfflineStore();
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return MemoryOfflineStore();
    return EncryptedFileOfflineStore(
        directory: Directory(
            '$local${Platform.pathSeparator}PlataformaCredito${Platform.pathSeparator}offline'),
        cipher: WindowsDpapiCipher());
  }
}

/// Deliberately the ApiClient default: tests and injected clients do no profile IO.
class MemoryOfflineStore implements OfflineStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String contents) async {
    this.contents = contents;
  }

  @override
  Future<void> clear() async {
    contents = null;
  }
}

abstract interface class OfflineCipher {
  Future<Uint8List> protect(Uint8List bytes);
  Future<Uint8List> unprotect(Uint8List bytes);
}

/// DPAPI CurrentUser. Payload travels only through stdin/stdout, never argv,
/// temporary plaintext, an environment variable, or a script containing data.
class WindowsDpapiCipher implements OfflineCipher {
  Future<Uint8List> _run(Uint8List bytes, bool decrypt) async {
    if (!Platform.isWindows) {
      throw const FileSystemException('DPAPI requiere Windows.');
    }
    final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final executable =
        '$windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final action = decrypt ? 'Unprotect' : 'Protect';
    final script =
        '\$ErrorActionPreference="Stop"; Add-Type -AssemblyName System.Security; '
        '\$inputBytes=[Convert]::FromBase64String([Console]::In.ReadToEnd()); '
        '\$entropy=[Text.Encoding]::UTF8.GetBytes("PlataformaCredito.offline.v1"); '
        '\$result=[Security.Cryptography.ProtectedData]::$action(\$inputBytes,\$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser); '
        '[Console]::Out.Write([Convert]::ToBase64String(\$result))';
    final process = await Process.start(executable,
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false);
    final output = process.stdout.transform(utf8.decoder).join();
    // Never expose process errors: a crypto/provider failure must not echo input.
    final errors = process.stderr.drain<void>();
    process.stdin.write(base64Encode(bytes));
    await process.stdin.close();
    int exit;
    try {
      exit = await process.exitCode.timeout(const Duration(seconds: 20));
    } on Object {
      process.kill();
      await errors;
      throw const FileSystemException(
          'No se pudo proteger el almacenamiento local.');
    }
    final encoded = await output;
    await errors;
    if (exit != 0) {
      throw const FileSystemException(
          'No se pudo proteger el almacenamiento local.');
    }
    return Uint8List.fromList(base64Decode(encoded.trim()));
  }

  @override
  Future<Uint8List> protect(Uint8List bytes) => _run(bytes, false);
  @override
  Future<Uint8List> unprotect(Uint8List bytes) => _run(bytes, true);
}

class EncryptedFileOfflineStore implements OfflineStore {
  EncryptedFileOfflineStore({required this.directory, required this.cipher});
  final Directory directory;
  final OfflineCipher cipher;
  File get _file =>
      File('${directory.path}${Platform.pathSeparator}session.dpapi');
  File get _temporary =>
      File('${directory.path}${Platform.pathSeparator}session.next.dpapi');
  @override
  Future<String?> read() async {
    if (!await _file.exists()) return null;
    final bytes = await _file.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Almacenamiento local demasiado grande.');
    }
    return utf8.decode(await cipher.unprotect(bytes));
  }

  @override
  Future<void> write(String contents) async {
    final plain = utf8.encode(contents);
    if (plain.length > 12 * 1024 * 1024) {
      throw const FileSystemException(
          'El almacenamiento local alcanzó su capacidad.');
    }
    final protected = await cipher.protect(Uint8List.fromList(plain));
    await directory.create(recursive: true);
    await _temporary.writeAsBytes(protected, flush: true);
    // Rename replaces the destination on the same volume. If replacement fails,
    // keep the previous durable version; never delete it to make room.
    await _temporary.rename(_file.path);
  }

  @override
  Future<void> clear() async {
    for (final file in [_file, _temporary]) {
      if (await file.exists()) await file.delete();
    }
  }
}
