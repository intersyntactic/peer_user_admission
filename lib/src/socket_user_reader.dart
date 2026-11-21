import 'dart:io';
import 'dart:typed_data';

import 'user_id.dart';

/// The kernels whose peer credentials [SocketUserReader] knows how to read.
enum Kernel {
  linux,
  macos,
  other;

  /// The kernel this program runs on.
  static Kernel get current {
    if (Platform.isLinux) return linux;
    if (Platform.isMacOS) return macos;
    return other;
  }
}

/// Reads a raw socket option from [socket]: what `getsockopt` writes into
/// [option]'s value.
typedef ReadSocketOption = Uint8List Function(
  Socket socket,
  RawSocketOption option,
);

Uint8List _getRawOption(Socket socket, RawSocketOption option) =>
    socket.getRawOption(option);

/// Linux's configured overflow uid, or null when it cannot be read.
int? _linuxOverflowUid() {
  try {
    final text = File('/proc/sys/kernel/overflowuid').readAsStringSync();
    return int.tryParse(text.trim());
  } on FileSystemException {
    return null;
  }
}

/// Reads the user on the other end of a Unix-domain socket from the kernel:
/// Linux's `SO_PEERCRED`, macOS's `LOCAL_PEERCRED`.
final class SocketUserReader {
  /// A reader for [kernel], the running one by default. [readOption] and
  /// [overflowUid] are the socket and `/proc` reads, passed in so a test can
  /// fake them.
  SocketUserReader({
    Kernel? kernel,
    this._readOption = _getRawOption,
    this._overflowUid = _linuxOverflowUid,
  }) : _kernel = kernel ?? Kernel.current;

  final Kernel _kernel;
  final ReadSocketOption _readOption;
  final int? Function() _overflowUid;

  /// `SOL_SOCKET`, `SO_PEERCRED`, and `struct ucred { pid; uid; gid; }`.
  static const _linuxLevel = 1;
  static const _linuxOption = 17;
  static const _ucredLength = 12;

  /// `SOL_LOCAL`, `LOCAL_PEERCRED`, and `struct xucred { cr_version; cr_uid;
  /// cr_ngroups; cr_groups[16]; }`, whose `cr_version` is `XUCRED_VERSION`.
  static const _macosLevel = 0;
  static const _macosOption = 1;
  static const _xucredLength = 76;
  static const _xucredVersion = 0;

  /// The uid sits after one 32-bit field in both structs.
  static const _uidOffset = 4;

  /// The user on the other end of [socket]; null when the kernel does not
  /// say, or says a user [UserId.parse] refuses, or Linux's configured
  /// overflow uid.
  UserId? userOf(Socket socket) {
    try {
      return switch (_kernel) {
        Kernel.linux => _linux(socket),
        Kernel.macos => _macos(socket),
        Kernel.other => null,
      };
    } on SocketException {
      return null;
    }
  }

  UserId? _linux(Socket socket) {
    final ucred = _read(socket, _linuxLevel, _linuxOption, _ucredLength);
    if (ucred == null) return null;
    final uid = ucred.getUint32(_uidOffset, Endian.host);
    if (uid == _overflowUid()) return null;
    return UserId.parse(uid);
  }

  UserId? _macos(Socket socket) {
    final xucred = _read(socket, _macosLevel, _macosOption, _xucredLength);
    if (xucred == null) return null;
    if (xucred.getUint32(0, Endian.host) != _xucredVersion) return null;
    return UserId.parse(xucred.getUint32(_uidOffset, Endian.host));
  }

  /// The option's bytes, or null when fewer than [length] came back. The
  /// buffer starts as all ones, so a uid the kernel never wrote reads as
  /// `(uid_t)-1`, which [UserId.parse] refuses, never as root's 0.
  ByteData? _read(Socket socket, int level, int option, int length) {
    final buffer = Uint8List(length)..fillRange(0, length, 0xFF);
    final bytes = _readOption(socket, RawSocketOption(level, option, buffer));
    if (bytes.length < length) return null;
    return ByteData.sublistView(bytes);
  }
}
