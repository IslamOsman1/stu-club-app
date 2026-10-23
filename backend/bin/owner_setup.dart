part of 'server.dart';

extension OwnerSetup on ClubServer {
  // Operator-only environment configuration. Never accepted from an HTTP request.
  Future<void> bootstrapOwner(Map<String, String> env) async {
    final email = (env['STU_OWNER_EMAIL'] ?? '').trim().toLowerCase();
    final password = env['STU_OWNER_PASSWORD'] ?? '';
    if (email.isEmpty || password.isEmpty) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        password.length < 10 ||
        password.length > 128) {
      throw StateError(
        'Owner configuration requires a valid email and a 10–128 character password.',
      );
    }
    final existing = rows('users')
        .where((u) => u['email'] == email)
        .firstOrNull;
    if (existing != null) {
      if (existing['role'] == 'admin') return;
      final derived = await kdf.deriveKeyFromPassword(
        password: password,
        nonce: base64.decode(existing['salt']),
      );
      final actual = await derived.extractBytes(),
          expected = base64.decode(existing['password']);
      var difference = 0;
      for (var i = 0; i < 32; i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (difference != 0) {
        throw StateError(
          'Owner password does not match the existing account. No account was changed.',
        );
      }
      existing['role'] = 'admin';
      existing['verified'] = true;
      existing['disabled'] = false;
    } else {
      final salt = List.generate(24, (_) => random.nextInt(256));
      final hash = await kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      rows('users').add({
        'id': id(),
        'email': email,
        'name': 'مشرف StuClub',
        'university': institutionList().first['id'],
        'role': 'admin',
        'bio': '',
        'verified': true,
        'disabled': false,
        'salt': base64.encode(salt),
        'password': base64.encode(await hash.extractBytes()),
      });
    }
    save();
  }
}
