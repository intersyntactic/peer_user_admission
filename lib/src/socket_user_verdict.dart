import 'user_id.dart';
import 'why_unread.dart';

/// What `SocketUserReader.read` found on the other end of a socket: a user,
/// or why there is none.
sealed class SocketUserReading {}

/// What `SocketUserCheck.decide` concluded about a socket. Only [Allowed]
/// admits the peer; every other case refuses it.
sealed class SocketUserVerdict {}

/// The kernel named [user].
final class UserRead implements SocketUserReading {
  const UserRead(this.user);

  final UserId user;

  @override
  String toString() => 'user $user';
}

/// The user could not be read, for the reason in [why]. It is both a reading
/// and a verdict, so a check hands the reader's answer on unchanged.
final class Unread implements SocketUserReading, SocketUserVerdict {
  const Unread(this.why);

  final WhyUnread why;

  @override
  String toString() => 'unread: $why';
}

/// The peer is [user], one of the allowed users.
final class Allowed implements SocketUserVerdict {
  const Allowed(this.user);

  final UserId user;

  @override
  String toString() => 'allowed: user $user';
}

/// The peer is [seen], which is not in [allowed].
final class NotAllowed implements SocketUserVerdict {
  const NotAllowed(this.seen, this.allowed);

  final UserId seen;
  final Set<UserId> allowed;

  @override
  String toString() =>
      'not allowed: user $seen is not one of {${allowed.join(', ')}}';
}
