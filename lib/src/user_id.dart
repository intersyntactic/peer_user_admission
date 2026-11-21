/// A user id that names one real user: never one the kernel uses to say it
/// does not know the user.
///
/// [parse] refuses:
/// - 65534, the overflow uid Linux reports for a user unmapped in the
///   reader's user namespace, and Linux's `nobody`;
/// - 4294967294, macOS's `nobody`;
/// - 4294967295, `(uid_t)-1`, which Linux reports for a peer with no
///   credentials;
/// - anything outside `uid_t`'s 32 bits.
///
/// So none of them can be in an allow list built from [UserId]s.
final class UserId {
  const UserId._(this.number);

  /// The id as the kernel writes it.
  final int number;

  /// The ids [parse] refuses inside `uid_t`'s range.
  static const Set<int> refused = {65534, 4294967294, 4294967295};

  /// [number] as a user id; null when it is negative, wider than 32 bits, or
  /// one of [refused].
  static UserId? parse(int number) {
    if (number < 0 || number > 0xFFFFFFFF) return null;
    if (refused.contains(number)) return null;
    return UserId._(number);
  }

  @override
  bool operator ==(Object other) => other is UserId && other.number == number;

  @override
  int get hashCode => number.hashCode;

  @override
  String toString() => '$number';
}
