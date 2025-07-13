import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'main_page.dart';
import 'package:pointycastle/export.dart' as pc;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nicknameController = TextEditingController();

  void _handleRegister() async {
    final nickname = _nicknameController.text.trim().toLowerCase();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı Adı boş olamaz!')),
      );
      return;
    }

    final keys = await createKeyPair();
    final url = Uri.parse('https://whisprapi.ahmetmahirdemirelli.com/api/user/createUser');
    final createUserDto = {
      'nickname': nickname,
      'x25519PublicKey': keys['x25519PublicKey'],
      'ed25519PublicKey': keys['ed25519PublicKey'],
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(createUserDto),
      );

      if (response.statusCode == 201) {
        print('Kullanıcı başarıyla oluşturuldu.');

        final password = generateStrongPassword(32);

        final ed25519PrivateKeyBase64 = keys['ed25519PrivateKey'];
        if (ed25519PrivateKeyBase64 == null) {
          throw Exception('ed25519PrivateKey null olamaz!');
        }
        final ed25519PrivateKeyBytes = base64Decode(ed25519PrivateKeyBase64);

        final x25519PrivateKeyBase64 = keys['x25519PrivateKey'];
        if (x25519PrivateKeyBase64 == null) {
          throw Exception('x25519PrivateKey null olamaz!');
        }
        final x25519PrivateKeyBytes = base64Decode(x25519PrivateKeyBase64);

        final nonce = Uint8List(12);
        final random = Random.secure();
        for (int i = 0; i < nonce.length; i++) {
          nonce[i] = random.nextInt(256);
        }

        final salt = Uint8List(16);
        for (int i = 0; i < salt.length; i++) {
          salt[i] = random.nextInt(256);
        }

        final key = pbkdf2(password, salt);

        final encryptedX25519PrivateKey = encryptAESGCM(key, x25519PrivateKeyBytes, nonce);
        final encryptedEd25519PrivateKey = encryptAESGCM(key, ed25519PrivateKeyBytes, nonce);

        final saveData = jsonEncode({
          'nickname': nickname,
          'x25519PublicKey': keys['x25519PublicKey'],
          'ed25519PublicKey': keys['ed25519PublicKey'],
          'encryptedX25519PrivateKey': base64Encode(encryptedX25519PrivateKey),
          'encryptedEd25519PrivateKey': base64Encode(encryptedEd25519PrivateKey),
          'nonce': base64Encode(nonce),
          'salt': base64Encode(salt),
        });

        final dir = await getApplicationDocumentsDirectory();
        final appDir = Directory('${dir.path}/messaging_app');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }

        final file = File('${appDir.path}/keys_${nickname}.json');
        await file.writeAsString(saveData);

        showDialog(
          context: context,
          builder: (context) {
            bool copied = false;
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Önemli!'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        'Private key güvenliğiniz için şifrelenmiştir.\n'
                        'Bu şifreyi mutlaka saklayın ve unutmayın:\n\n$password',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: copied
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: password));
                                setState(() {
                                  copied = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Şifre kopyalandı!')),
                                );
                              },
                        icon: const Icon(Icons.copy),
                        label: Text(copied ? 'Kopyalandı!' : 'Kopyala'),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const MainPage()),
                        );
                      },
                      child: const Text('Tamam'),
                    ),
                  ],
                );
              },
            );
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt olunuyor: $nickname')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt başarısız: Kullanıcı adı geçersiz.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sunucu bağlantı hatası: $e')),
      );
    }
  }

  Uint8List pbkdf2(String password, Uint8List salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    final params = pc.Pbkdf2Parameters(salt, 10000, 32);
    derivator.init(params);
    return derivator.process(utf8.encode(password));
  }

  String generateStrongPassword(int length) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*()-_=+[]{}|;:,.<>?';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Uint8List encryptAESGCM(Uint8List key, Uint8List data, Uint8List nonce) {
    final cipher = pc.GCMBlockCipher(pc.AESFastEngine());
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(true, params);
    return cipher.process(data);
  }

  Future<Map<String, String>> createKeyPair() async {
    final x25519 = X25519();
    final ed25519 = Ed25519();

    final xKeyPair = await x25519.newKeyPair();
    final xPublicKey = await xKeyPair.extractPublicKey();
    final xPrivateKeyBytes = await xKeyPair.extractPrivateKeyBytes();

    final edKeyPair = await ed25519.newKeyPair();
    final edPublicKey = await edKeyPair.extractPublicKey();
    final edPrivateKeyBytes = await edKeyPair.extractPrivateKeyBytes();

    return {
      'x25519PublicKey': base64Encode(xPublicKey.bytes),
      'x25519PrivateKey': base64Encode(xPrivateKeyBytes),
      'ed25519PublicKey': base64Encode(edPublicKey.bytes),
      'ed25519PrivateKey': base64Encode(edPrivateKeyBytes),
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double contentWidth = defaultTargetPlatform == TargetPlatform.android
        ? screenWidth * 0.8
        : screenWidth * 0.4;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
        toolbarHeight: 40,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                'Kayıt Ol',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              width: contentWidth,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Color.fromARGB(255, 139, 3, 105),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(255, 139, 3, 105).withOpacity(0.3),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nicknameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Kullanıcı Adı',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 139, 3, 105),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Kayıt Ol',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
