# Changelog

## 0.2.1

- `ReadFailed.toString` turns line breaks in the exception's text into
  spaces, so every verdict prints on one line, as the README says.

## 0.2.0

- `SocketUserCheck.decide` returns a sealed `SocketUserVerdict`: `Allowed`,
  `NotAllowed(seen, allowed)` or `Unread(why)`, so a caller can log why a peer
  was refused.
- `SocketUserReader.read` returns `UserRead(user)` or `Unread(why)`.
- `WhyUnread` names each way a read falls short: `UnsupportedKernel`,
  `ReadFailed` (with the `SocketException` and its `OSError`), `ShortAnswer`,
  `OverflowUid`, `UnknownXucredVersion` and `RefusedUid`.
- `SocketUserCheck.allows` and `SocketUserReader.userOf` are deprecated in
  favour of `decide` and `read`. Their answers are unchanged.

## 0.1.0

- First release: `UserId`, `SocketUserReader` and `SocketUserCheck`.
