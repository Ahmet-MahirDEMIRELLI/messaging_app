import 'package:flutter/material.dart';
import 'register_page.dart';
import 'home_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _secureStorage = const FlutterSecureStorage();
  bool rememberMe = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadSavedCredentials();
    });
  }

  Future<void> loadSavedCredentials() async {
    final nickname = await _secureStorage.read(key: 'nickname');
    final password = await _secureStorage.read(key: 'password');
    final savedTimeStr = await _secureStorage.read(key: 'saved_time');

    if (nickname != null && password != null && savedTimeStr != null) {
      final savedTime = DateTime.fromMillisecondsSinceEpoch(int.parse(savedTimeStr));
      if (DateTime.now().difference(savedTime).inDays <= 30) {
        _nicknameController.text = nickname;
        _passwordController.text = password;
        setState(() {
          rememberMe = true;
        });
      } 
      else {
        await _secureStorage.delete(key: 'nickname');
        await _secureStorage.delete(key: 'password');
        await _secureStorage.delete(key: 'saved_time');
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async{
    final nickname = _nicknameController.text.trim();
    final password = _passwordController.text.trim();

    if (nickname.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı adı ve şifre boş olamaz!')),
      );
      return;
    }

    if (rememberMe) {
      await _secureStorage.write(key: 'nickname', value: nickname);
      await _secureStorage.write(key: 'password', value: password);
      await _secureStorage.write(
        key: 'saved_time',
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(nickname: nickname.toLowerCase(), password: password),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    double contentWidth = defaultTargetPlatform == TargetPlatform.android
        ? screenWidth * 0.8
        : screenWidth * 0.4;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'Whispr',
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
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color.fromARGB(255, 139, 3, 105), width: 2),
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
                        hintText: 'Kullanıcı Adı',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Şifre',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.grey[850],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text(
                        'Beni 30 gün hatırla',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: rememberMe,
                      onChanged: (bool? value) async {
                        if (value == true && !rememberMe) {
                          final accepted = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Uyarı'),
                              content: const Text(
                                'Bu işlem güvenliğiniz açısından önerilmemektedir.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Vazgeç'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Riskin bana ait olduğunu kabul ediyorum.'),
                                ),
                              ],
                            ),
                          );
                          if (accepted == true) {
                            setState(() {
                              rememberMe = true;
                            });
                          }
                        } else {
                          setState(() {
                            rememberMe = value ?? false;
                          });
                        }
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Giriş Yap',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterPage()),
                          );
                        },
                        child: const Text(
                          'Hesabınız yok mu? Kayıt olun',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
