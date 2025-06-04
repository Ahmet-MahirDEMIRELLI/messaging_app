import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' as pc;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _nicknameController = TextEditingController();

  void _handleRegister() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname boş olamaz!')),
      );
      return;
    }

    // key oluşturmadan nickname kontrolü yap

    final keys = await createKeyPair();

    print('Kayıt olunuyor: $nickname');
    print('X25519 Public Key: ${keys['x25519PublicKey']}');
    print('X25519 Private Key: ${keys['x25519PrivateKey']}');
    print('Ed25519 Public Key: ${keys['ed25519PublicKey']}');
    print('Ed25519 Private Key: ${keys['ed25519PrivateKey']}');

    // 1. Güçlü şifre oluştur
    final password = generateStrongPassword(32);

    // 2. Private key'i byte dizisine çevir (örnek ed25519 private key)
    final privateKeyBase64 = keys['ed25519PrivateKey'];
    if (privateKeyBase64 == null) {
      // Hata yönetimi
      throw Exception('ed25519PrivateKey null olamaz!');
    }
    final privateKeyBytes = base64Decode(privateKeyBase64);

    // 3. Şifreleme için rastgele nonce üret (12 byte)
    final nonce = Uint8List(12);
    final random = Random.secure();
    for (int i = 0; i < nonce.length; i++) {
      nonce[i] = random.nextInt(256);
    }

    // 4. Password'u 32 byte key'e dönüştürmek için PBKDF2 uygula (salt da random olmalı)
    final salt = Uint8List(16);
    for (int i = 0; i < salt.length; i++) {
      salt[i] = random.nextInt(256);
    }
    final key = pbkdf2(password, salt);

    // 5. Private key'i AES-GCM ile şifrele
    final encryptedPrivateKey = encryptAESGCM(key, privateKeyBytes, nonce);

    // 6. Şifrelenmiş veriyi ve nonce+salt'ı JSON yapısında sakla
    final saveData = jsonEncode({
      'encryptedPrivateKey': base64Encode(encryptedPrivateKey),
      'nonce': base64Encode(nonce),
      'salt': base64Encode(salt),
    });

    // 7. Dosya yolunu al ve dosyaya yaz (örnek: private_key.json)
    final dir = await getApplicationDocumentsDirectory();
    final appDir = Directory('${dir.path}/messaging_app');

    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }

    final file = File('${appDir.path}/private_key_${nickname}.json');
    print('File path: ${file.path}');
    await file.writeAsString(saveData);

    // 8. Kullanıcıya şifreyi göster ve saklamasını söyle
    showDialog(
      context: context,
      builder: (context) {
        bool copied = false; // Buton durumu için değişken

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
                    onPressed: copied ? null : () {
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
                  onPressed: () => Navigator.pop(context),
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

    // TODO: Backend'e nickname + public key'leri POST et
    // LOGİN E gönder
  }

  // PBKDF2 fonksiyonu
  Uint8List pbkdf2(String password, Uint8List salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    final params = pc.Pbkdf2Parameters(salt, 10000, 32); // 10k iterasyon, 32 byte key
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

    // X25519 anahtar çifti oluştur
    final xKeyPair = await x25519.newKeyPair();
    final xPublicKey = await xKeyPair.extractPublicKey();
    final xPrivateKeyBytes = await xKeyPair.extractPrivateKeyBytes();

    // Ed25519 anahtar çifti oluştur
    final edKeyPair = await ed25519.newKeyPair();
    final edPublicKey = await edKeyPair.extractPublicKey();
    final edPrivateKeyBytes = await edKeyPair.extractPrivateKeyBytes();

    // Base64 encode et
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
              width: screenWidth * 0.4,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color.fromARGB(255, 139, 3, 105),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(255, 139, 3, 105).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
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
                      hintText: 'Nickname',
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
