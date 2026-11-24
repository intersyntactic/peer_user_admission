import 'dart:io';
import 'dart:typed_data';

import 'package:is_unix_socket_user_check/is_unix_socket_user_check.dart';
import 'package:test/test.dart';

/// A struct of [length] bytes with [first] then [uid] as host-order u32s.
Uint8List struct(int length, {required int first, required int uid}) {
  final bytes = Uint8List(length);
  ByteData.sublistView(bytes)
    ..setUint32(0, first, Endian.host)
    ..setUint32(4, uid, Endian.host);
  return bytes;
}

/// A reader that answers every option read with [bytes].
SocketUserReader answering(
  Kernel kernel,
  Uint8List bytes, {
  int? overflowUid = 65534,
}) => SocketUserReader(
  kernel: kernel,
  readOption: (_, _) => bytes,
  overflowUid: () => overflowUid,
);

/// A reading of the user [uid].
Matcher isUserRead(int uid) =>
    isA<UserRead>().having((r) => r.user, 'user', UserId.parse(uid));

/// An [Unread] whose reason matches [why].
Matcher isUnread(Matcher why) => isA<Unread>().having((u) => u.why, 'why', why);

void main() {
  late Directory directory;
  late ServerSocket server;
  late Socket client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('unix_socket_user_check');
    final address = InternetAddress(
      '${directory.path}/socket',
      type: InternetAddressType.unix,
    );
    server = await ServerSocket.bind(address, 0);
    client = await Socket.connect(address, 0);
  });

  tearDown(() async {
    client.destroy();
    await server.close();
    await directory.delete(recursive: true);
  });

  group('UserId.parse', () {
    test('takes an ordinary uid and root', () {
      expect(UserId.parse(501)?.number, 501);
      expect(UserId.parse(0)?.number, 0);
    });

    test('refuses the overflow uid, nobody and (uid_t)-1', () {
      expect(UserId.parse(65534), isNull);
      expect(UserId.parse(4294967294), isNull);
      expect(UserId.parse(4294967295), isNull);
    });

    test('refuses numbers outside uid_t', () {
      expect(UserId.parse(-1), isNull);
      expect(UserId.parse(-2), isNull);
      expect(UserId.parse(4294967296), isNull);
    });
  });

  group('SocketUserReader on Linux', () {
    test('reads the uid after the pid', () {
      final reader = answering(Kernel.linux, struct(12, first: 42, uid: 1000));
      expect(reader.read(client), isUserRead(1000));
    });

    test('names the overflow uid', () {
      final reader = answering(Kernel.linux, struct(12, first: 42, uid: 65534));
      expect(
        reader.read(client),
        isUnread(isA<OverflowUid>().having((w) => w.uid, 'uid', 65534)),
      );
    });

    test('names a configured overflow uid that is not 65534', () {
      final reader = answering(
        Kernel.linux,
        struct(12, first: 42, uid: 2000),
        overflowUid: 2000,
      );
      expect(
        reader.read(client),
        isUnread(isA<OverflowUid>().having((w) => w.uid, 'uid', 2000)),
      );
    });

    test('refuses 65534 when the overflow uid cannot be read', () {
      final reader = answering(
        Kernel.linux,
        struct(12, first: 42, uid: 65534),
        overflowUid: null,
      );
      expect(
        reader.read(client),
        isUnread(isA<RefusedUid>().having((w) => w.uid, 'uid', 65534)),
      );
    });

    test('refuses a peer with no credentials', () {
      final reader = answering(
        Kernel.linux,
        struct(12, first: 0, uid: 4294967295),
      );
      expect(
        reader.read(client),
        isUnread(isA<RefusedUid>().having((w) => w.uid, 'uid', 4294967295)),
      );
    });

    test('names a short answer and its length', () {
      final reader = answering(Kernel.linux, Uint8List(4));
      expect(
        reader.read(client),
        isUnread(
          isA<ShortAnswer>()
              .having((w) => w.length, 'length', 4)
              .having((w) => w.expected, 'expected', 12),
        ),
      );
    });

    test('reads an untouched buffer as (uid_t)-1, never root', () {
      final reader = SocketUserReader(
        kernel: Kernel.linux,
        readOption: (_, option) => option.value,
        overflowUid: () => 65534,
      );
      expect(
        reader.read(client),
        isUnread(isA<RefusedUid>().having((w) => w.uid, 'uid', 4294967295)),
      );
    });

    test('carries the OSError when the read throws', () {
      final reader = SocketUserReader(
        kernel: Kernel.linux,
        readOption: (_, _) => throw const SocketException(
          'getsockopt',
          osError: OSError('Bad file descriptor', 9),
        ),
      );
      expect(
        reader.read(client),
        isUnread(
          isA<ReadFailed>().having((w) => w.osError?.errorCode, 'errno', 9),
        ),
      );
    });
  });

  test('every reason prints on one line, even an OS message with breaks', () {
    const reasons = <WhyUnread>[
      UnsupportedKernel(),
      ReadFailed(
        SocketException(
          'getsockopt\nfailed',
          osError: OSError('Bad file\r\ndescriptor\u2028here', 9),
        ),
      ),
      ShortAnswer(length: 4, expected: 12),
      OverflowUid(65534),
      UnknownXucredVersion(1),
      RefusedUid(4294967295),
    ];
    for (final why in reasons) {
      final line = '${Unread(why)}';
      expect(line, isNot(matches(RegExp('[\n\r\v\f\u0085\u2028\u2029]'))));
    }
    expect(
      '${reasons[1]}',
      allOf(
        contains('getsockopt failed'),
        contains('Bad file descriptor here'),
      ),
    );
  });

  group('SocketUserReader on macOS', () {
    test('reads the uid after the version', () {
      final reader = answering(Kernel.macos, struct(76, first: 0, uid: 501));
      expect(reader.read(client), isUserRead(501));
    });

    test('names an unknown xucred version', () {
      final reader = answering(Kernel.macos, struct(76, first: 1, uid: 501));
      expect(
        reader.read(client),
        isUnread(
          isA<UnknownXucredVersion>().having((w) => w.version, 'version', 1),
        ),
      );
    });

    test('names a short answer and its length', () {
      final reader = answering(Kernel.macos, Uint8List(12));
      expect(
        reader.read(client),
        isUnread(
          isA<ShortAnswer>()
              .having((w) => w.length, 'length', 12)
              .having((w) => w.expected, 'expected', 76),
        ),
      );
    });

    test('refuses nobody', () {
      final reader = answering(
        Kernel.macos,
        struct(76, first: 0, uid: 4294967294),
      );
      expect(
        reader.read(client),
        isUnread(isA<RefusedUid>().having((w) => w.uid, 'uid', 4294967294)),
      );
    });
  });

  test('another kernel is unread without a read', () {
    final reader = SocketUserReader(
      kernel: Kernel.other,
      readOption: (_, _) => fail('read on an unknown kernel'),
    );
    expect(reader.read(client), isUnread(isA<UnsupportedKernel>()));
  });

  test('userOf is null exactly when read is unread', () {
    expect(answering(Kernel.linux, Uint8List(0)).userOf(client), isNull);
    expect(
      answering(Kernel.linux, struct(12, first: 1, uid: 1000)).userOf(client),
      UserId.parse(1000),
    );
  });

  group('SocketUserCheck', () {
    final me = UserId.parse(1000)!;

    SocketUserCheck checkSeeing(Uint8List bytes) =>
        SocketUserCheck.only(me, reader: answering(Kernel.linux, bytes));

    test('allows an allowed user', () {
      expect(
        checkSeeing(struct(12, first: 1, uid: 1000)).decide(client),
        isA<Allowed>().having((v) => v.user, 'user', me),
      );
    });

    test('refuses another user, saying who it saw', () {
      expect(
        checkSeeing(struct(12, first: 1, uid: 1001)).decide(client),
        isA<NotAllowed>()
            .having((v) => v.seen, 'seen', UserId.parse(1001))
            .having((v) => v.allowed, 'allowed', {me}),
      );
    });

    test("hands on the reader's Unread", () {
      expect(
        checkSeeing(Uint8List(0)).decide(client),
        isUnread(isA<ShortAnswer>()),
      );
    });

    test('allows is true only for Allowed', () {
      expect(
        checkSeeing(struct(12, first: 1, uid: 1000)).allows(client),
        isTrue,
      );
      expect(
        checkSeeing(struct(12, first: 1, uid: 1001)).allows(client),
        isFalse,
      );
      expect(checkSeeing(Uint8List(0)).allows(client), isFalse);
    });
  });

  test(
    'the running kernel names this process as the user on the other end',
    () async {
      final result = await Process.run('id', ['-u']);
      final uid = int.parse(
        (result.stdout as String).trim(),
      ); // cast-ok: Process.run decodes stdout to a String by default.
      if (Kernel.current == Kernel.other) {
        markTestSkipped('peer credentials are only read on Linux and macOS');
        return;
      }
      expect(SocketUserReader().read(client), isUserRead(uid));
      expect(
        SocketUserCheck.only(UserId.parse(uid)!).decide(client),
        isA<Allowed>(),
      );
    },
  );
}
