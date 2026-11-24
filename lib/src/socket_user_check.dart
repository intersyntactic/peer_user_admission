import 'dart:io';

import 'socket_user_reader.dart';
import 'socket_user_verdict.dart';
import 'user_id.dart';

/// Decides whether a socket's user may connect: only when the kernel names its
/// user and that user is one of the allowed ones. A connection whose user cannot
/// be read is denied.
final class SocketUserCheck {
  /// Allows the users in [allowed], read by [reader], the running kernel's
  /// by default.
  SocketUserCheck(Iterable<UserId> allowed, {SocketUserReader? reader})
    : _allowed = Set.unmodifiable(allowed),
      _reader = reader ?? SocketUserReader();

  /// Allows only [user].
  SocketUserCheck.only(UserId user, {SocketUserReader? reader})
    : this([user], reader: reader);

  final Set<UserId> _allowed;
  final SocketUserReader _reader;

  /// Whether the user on the other end of [socket] may connect, and if not,
  /// why. Admit the peer only on [Allowed].
  SocketUserVerdict decide(Socket socket) => switch (_reader.read(socket)) {
    UserRead(:final user) when _allowed.contains(user) => Allowed(user),
    UserRead(:final user) => NotAllowed(user, _allowed),
    final Unread unread => unread,
  };

  /// Whether the user on the other end of [socket] is an allowed one.
  @Deprecated('Use decide, whose verdict says why a peer is refused.')
  bool allows(Socket socket) => decide(socket) is Allowed;
}
