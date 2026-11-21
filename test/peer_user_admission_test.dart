import 'dart:io';
import 'dart:typed_data';

import 'package:is_peer_user_admission/is_peer_user_admission.dart';
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
PeerUserReader answering(
  Kernel kernel,
  Uint8List bytes, {
  int? overflowUid = 65534,
}) => PeerUserReader(
  kernel: kernel,
  readOption: (_, _) => bytes,
  overflowUid: () => overflowUid,
);

void main() {
  late Directory directory;
  late ServerSocket server;
  late Socket client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('peer_user_admission');
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
      expect(UserId.parse(4294967296), isNull);
    });
  });

  group('PeerUserReader on Linux', () {
    test('reads the uid after the pid', () {
      final reader = answering(Kernel.linux, struct(12, first: 42, uid: 1000));
      expect(reader.userOf(client), UserId.parse(1000));
    });

    test('denies the overflow uid', () {
      final reader = answering(Kernel.linux, struct(12, first: 42, uid: 65534));
      expect(reader.userOf(client), isNull);
    });

    test('denies a configured overflow uid that is not 65534', () {
      final reader = answering(
        Kernel.linux,
        struct(12, first: 42, uid: 2000),
        overflowUid: 2000,
      );
      expect(reader.userOf(client), isNull);
    });

    test('denies a peer with no credentials', () {
      final reader = answering(
        Kernel.linux,
        struct(12, first: 0, uid: 4294967295),
      );
      expect(reader.userOf(client), isNull);
    });

    test('denies a short answer', () {
      final reader = answering(Kernel.linux, Uint8List(4));
      expect(reader.userOf(client), isNull);
    });

    test('reads an untouched buffer as (uid_t)-1, never root', () {
      final reader = PeerUserReader(
        kernel: Kernel.linux,
        readOption: (_, option) => option.value,
        overflowUid: () => 65534,
      );
      expect(reader.userOf(client), isNull);
    });

    test('denies when the read throws', () {
      final reader = PeerUserReader(
        kernel: Kernel.linux,
        readOption: (_, _) => throw const SocketException('no peer'),
      );
      expect(reader.userOf(client), isNull);
    });
  });

  group('PeerUserReader on macOS', () {
    test('reads the uid after the version', () {
      final reader = answering(Kernel.macos, struct(76, first: 0, uid: 501));
      expect(reader.userOf(client), UserId.parse(501));
    });

    test('denies an unknown xucred version', () {
      final reader = answering(Kernel.macos, struct(76, first: 1, uid: 501));
      expect(reader.userOf(client), isNull);
    });

    test('denies nobody', () {
      final reader = answering(
        Kernel.macos,
        struct(76, first: 0, uid: 4294967294),
      );
      expect(reader.userOf(client), isNull);
    });
  });

  test('another kernel is denied without a read', () {
    final reader = PeerUserReader(
      kernel: Kernel.other,
      readOption: (_, _) => fail('read on an unknown kernel'),
    );
    expect(reader.userOf(client), isNull);
  });

  group('PeerUserAdmission', () {
    final me = UserId.parse(1000)!;

    test('admits an allowed user', () {
      final admission = PeerUserAdmission.only(
        me,
        reader: answering(Kernel.linux, struct(12, first: 1, uid: 1000)),
      );
      expect(admission.admits(client), isTrue);
    });

    test('denies another user', () {
      final admission = PeerUserAdmission.only(
        me,
        reader: answering(Kernel.linux, struct(12, first: 1, uid: 1001)),
      );
      expect(admission.admits(client), isFalse);
    });

    test('denies a peer whose user cannot be read', () {
      final admission = PeerUserAdmission.only(
        me,
        reader: answering(Kernel.linux, Uint8List(0)),
      );
      expect(admission.admits(client), isFalse);
    });
  });

  test('the running kernel names this process as the peer', () async {
    final result = await Process.run('id', ['-u']);
    final uid = int.parse(
      (result.stdout as String).trim(),
    ); // cast-ok: Process.run decodes stdout to a String by default.
    if (Kernel.current == Kernel.other) {
      markTestSkipped('peer credentials are only read on Linux and macOS');
      return;
    }
    expect(PeerUserReader().userOf(client), UserId.parse(uid));
    expect(PeerUserAdmission.only(UserId.parse(uid)!).admits(client), isTrue);
  });
}
