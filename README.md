# is_unix_socket_user_check

Decides whether the user on the other end of a Unix-domain socket may connect, from
the kernel's peer credentials: Linux's `SO_PEERCRED`, macOS's `LOCAL_PEERCRED`.

```dart
final check = SocketUserCheck.only(UserId.parse(caller)!);

Future<void> serve(Socket socket) async {
  if (!check.allows(socket)) {
    socket.destroy();
    return;
  }
  // ...
}
```

## Unknown is denied

There is no nullable uid to compare. `allows` is false whenever the user cannot
be read: another kernel, a failed `getsockopt`, a short answer, an unknown
`xucred` version.

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
read the user with `SocketUserReader.userOf` and key the table by `UserId`.
`userOf` returns `UserId?`, and a table keyed by `UserId` cannot be asked about
null.

## Tests

`SocketUserReader` takes the socket read and the `/proc` read as functions, so a
test can fake the kernel's answer. One test reads the running kernel's answer
for a real socket pair.

```sh
dart analyze --fatal-infos
dart test
```
