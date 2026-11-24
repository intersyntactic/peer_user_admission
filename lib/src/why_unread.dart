import 'dart:io';

/// Why the user on the other end of a socket could not be read. Each case is
/// a different way the kernel's answer fell short, so a caller can switch on
/// it and log what it carries.
sealed class WhyUnread {
  const WhyUnread();
}

/// The running kernel is neither Linux nor macOS, so no read was tried.
final class UnsupportedKernel extends WhyUnread {
  const UnsupportedKernel();

  @override
  String toString() => 'peer credentials are only read on Linux and macOS';
}

/// `getsockopt` failed. [exception]'s `osError` carries the errno, when the
/// runtime gave one.
final class ReadFailed extends WhyUnread {
  const ReadFailed(this.exception);

  final SocketException exception;

  /// The operating system's error, or null when the runtime gave none.
  OSError? get osError => exception.osError;

  @override
  String toString() => 'reading the peer credentials failed: $exception';
}

/// The kernel wrote fewer bytes than the credentials struct holds.
final class ShortAnswer extends WhyUnread {
  const ShortAnswer({required this.length, required this.expected});

  final int length;
  final int expected;

  @override
  String toString() =>
      'the kernel answered $length bytes of a $expected-byte struct';
}

/// Linux reported its configured overflow uid, read from
/// `/proc/sys/kernel/overflowuid`: the peer's user is unmapped in the
/// reader's user namespace.
final class OverflowUid extends WhyUnread {
  const OverflowUid(this.uid);

  final int uid;

  @override
  String toString() => 'the kernel reported the overflow uid $uid';
}

/// macOS answered with an `xucred` whose `cr_version` is not
/// `XUCRED_VERSION`, so its layout is unknown.
final class UnknownXucredVersion extends WhyUnread {
  const UnknownXucredVersion(this.version);

  final int version;

  @override
  String toString() =>
      'the kernel answered an xucred of unknown version $version';
}

/// The kernel named a uid that `UserId.parse` refuses: one a kernel uses to
/// say it does not know the user.
final class RefusedUid extends WhyUnread {
  const RefusedUid(this.uid);

  final int uid;

  @override
  String toString() => 'the kernel reported uid $uid, which names no one user';
}
