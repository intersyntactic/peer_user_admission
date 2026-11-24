# is_unix_socket_user_check

Decides whether the user on the other end of a Unix-domain socket may connect, from
the kernel's peer credentials: Linux's `SO_PEERCRED`, macOS's `LOCAL_PEERCRED`.

```dart
final check = SocketUserCheck.only(UserId.parse(caller)!);

Future<void> serve(Socket socket) async {
  switch (check.decide(socket)) {
    case Allowed():
      break;
    case final refused:
      stderr.writeln('refused a peer: $refused');
      socket.destroy();
      return;
  }
  // ...
}
```

`decide` returns a sealed `SocketUserVerdict`; only `Allowed` admits the peer:

| verdict | what it carries |
|---|---|
| `Allowed(user)` | the allowed user the kernel named |
| `NotAllowed(seen, allowed)` | the user the kernel named, and the set it is not in |
| `Unread(why)` | why the kernel named no user: a `WhyUnread` |

`WhyUnread` is sealed too, so a caller can switch on each reason:

| reason | when |
|---|---|
| `UnsupportedKernel()` | neither Linux nor macOS; no read is tried |
| `ReadFailed(exception)` | `getsockopt` threw; `osError` carries the errno |
| `ShortAnswer(length:, expected:)` | fewer bytes than the struct holds |
| `OverflowUid(uid)` | Linux's configured overflow uid |
| `UnknownXucredVersion(version)` | a macOS `xucred` of a layout this reader does not know |
| `RefusedUid(uid)` | a uid `UserId.parse` refuses (below) |

Every case's `toString` is one line fit for a log.

`allows`, which returns a bool, still works but is deprecated: a bool cannot say
why a peer was refused.

## Unknown is denied

There is no nullable uid to compare. `decide` answers `Unread` whenever the user
cannot be read, and `Unread` is not `Allowed`.

`UserId.parse` refuses the ids a kernel uses to say it does not know a user, so
none can be in an allow list:

| id | what it is |
|---|---|
| 65534 | Linux's overflow uid, reported for a user unmapped in the reader's user namespace; also `nobody` |
| 4294967294 | macOS's `nobody` |
| 4294967295 | `(uid_t)-1`, reported by Linux for a peer with no credentials |

On Linux the reader also refuses the overflow uid configured in
`/proc/sys/kernel/overflowuid` when it is not 65534.

The option buffer starts as all ones, so a uid the kernel never wrote reads as
`(uid_t)-1` and is refused, never as root's 0.

## A user per sender

When the decision depends on who the user is, not only on whether they may connect,
read the user with `SocketUserReader.read` and key the table by `UserId`.
`read` returns `UserRead(user)` or the same `Unread(why)` a verdict carries, and
only `UserRead` has a `UserId` to look up. `userOf`, which returns `UserId?`, is
deprecated for the same reason as `allows`.

## Tests

`SocketUserReader` takes the socket read and the `/proc` read as functions, so a
test can fake the kernel's answer. One test reads the running kernel's answer
for a real socket pair.

```sh
dart analyze --fatal-infos
dart test
```
