import 'dart:io';

import 'peer_user_reader.dart';
import 'user_id.dart';

/// Decides whether a socket's peer may in: only when the kernel names its
/// user and that user is one of the allowed ones. A peer whose user cannot
/// be read is denied.
final class PeerUserAdmission {
  /// Admits the users in [allowed], read by [reader], the running kernel's
  /// by default.
  PeerUserAdmission(Iterable<UserId> allowed, {PeerUserReader? reader})
    : _allowed = Set.unmodifiable(allowed),
      _reader = reader ?? PeerUserReader();

  /// Admits only [user].
  PeerUserAdmission.only(UserId user, {PeerUserReader? reader})
    : this([user], reader: reader);

  final Set<UserId> _allowed;
  final PeerUserReader _reader;

  /// Whether [socket]'s peer is an allowed user.
  bool admits(Socket socket) {
    final user = _reader.userOf(socket);
    return user != null && _allowed.contains(user);
  }
}
