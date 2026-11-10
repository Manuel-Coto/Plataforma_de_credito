import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
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

/// DPAPI CurrentUser, called directly in a worker isolate. Plaintext remains in
/// process memory; native buffers are cleared and released after the call.
class WindowsDpapiCipher implements OfflineCipher {
  Future<Uint8List> _run(Uint8List bytes, bool decrypt) async {
    if (!Platform.isWindows) {
      throw const FileSystemException('DPAPI requiere Windows.');
    }
    try {
      return await Isolate.run(
          () => _WindowsDpapiBindings().transform(bytes, decrypt));
    } on Object {
      // Provider and allocation errors must never include the protected data.
      throw const FileSystemException(
          'No se pudo proteger el almacenamiento local.');
    }
  }

  @override
  Future<Uint8List> protect(Uint8List bytes) => _run(bytes, false);
  @override
  Future<Uint8List> unprotect(Uint8List bytes) => _run(bytes, true);
}

final class _DataBlob extends Struct {
  @Uint32()
  external int size;
  external Pointer<Uint8> data;
}

typedef _LocalAllocNative = Pointer<Void> Function(Uint32, UintPtr);
typedef _LocalAllocDart = Pointer<Void> Function(int, int);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);
typedef _CryptNative = Int32 Function(
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Pointer<_DataBlob>);
typedef _CryptDart = int Function(Pointer<_DataBlob>, Pointer<Void>,
    Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);

class _WindowsDpapiBindings {
  final _crypt = DynamicLibrary.open('Crypt32.dll');
  final _kernel = DynamicLibrary.open('Kernel32.dll');
  late final _allocate =
      _kernel.lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  late final _free =
      _kernel.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  late final _protect =
      _crypt.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  late final _unprotect =
      _crypt.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');

  Uint8List transform(Uint8List bytes, bool decrypt) {
    final allocations = <Pointer<Void>>[];
    final buffers = <Uint8List>[];
    Pointer<Void> allocate(int size) {
      // LMEM_FIXED | LMEM_ZEROINIT; LocalFree also owns the DPAPI output.
      final pointer = _allocate(0x0040, size);
      if (pointer == nullptr) {
        throw const FileSystemException(
            'No se pudo asignar memoria protegida.');
      }
      allocations.add(pointer);
      return pointer;
    }

    Pointer<_DataBlob> blob(Uint8List contents) {
      final pointer = allocate(sizeOf<_DataBlob>()).cast<_DataBlob>();
      pointer.ref.size = contents.length;
      pointer.ref.data =
          allocate(contents.isEmpty ? 1 : contents.length).cast<Uint8>();
      final buffer = pointer.ref.data.asTypedList(contents.length);
      buffers.add(buffer);
      buffer.setAll(0, contents);
      return pointer;
    }

    Pointer<_DataBlob>? output;
    try {
      final input = blob(bytes);
      // Keep the same entropy and CurrentUser scope as existing .dpapi files.
      final entropy =
          blob(Uint8List.fromList(utf8.encode('PlataformaCredito.offline.v1')));
      output = allocate(sizeOf<_DataBlob>()).cast<_DataBlob>();
      final succeeded = (decrypt ? _unprotect : _protect)(
          input, nullptr, entropy, nullptr, nullptr, 1, output);
      // CRYPTPROTECT_UI_FORBIDDEN; no machine-scope flag is set.
      if (succeeded == 0) {
        throw const FileSystemException(
            'DPAPI no pudo completar la operación.');
      }
      return Uint8List.fromList(output.ref.data.asTypedList(output.ref.size));
    } finally {
      if (output != null && output.ref.data != nullptr) {
        output.ref.data
            .asTypedList(output.ref.size)
            .fillRange(0, output.ref.size, 0);
        _free(output.ref.data.cast<Void>());
      }
      for (final buffer in buffers) {
        buffer.fillRange(0, buffer.length, 0);
      }
      for (final pointer in allocations.reversed) {
        _free(pointer);
      }
    }
  }
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
