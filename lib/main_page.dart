import 'package:flutter/material.dart';
import 'register_page.dart';
import 'home_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final TextEditingController _nicknameController = TextEditingController();

  void _handleLogin() {
    final nickname = _nicknameController.text.trim();

    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname boş olamaz!')),
      );
      return;
    }

    // Burada backend'e nickname doğrulaması yapılabilir, şimdilik direkt geçiyoruz

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(nickname: nickname),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      // AppBar kaldırıldı
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                'Messaging App',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Border'lı box (giriş kutusu)
            Container(
              width: screenWidth * 0.4,
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
    );
  }
}
