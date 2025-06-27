import 'dart:io';
import 'package:flutter/material.dart';
import 'package:messaging_app/main_page.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'dart:math';

class HomePage extends StatefulWidget {
  final String nickname;
  final String password;

  const HomePage({
    super.key,
    required this.nickname,
    required this.password,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class Message {
  final String sender;
  final String receiver;
  final String content;
  final DateTime timestamp;

  Message({
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
  });
}

class Contact {
  final String nickname;
  final String ed25519PublicKey;
  final String x25519PublicKey;

  Contact({
    required this.nickname,
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      nickname: json['nickname'],
      ed25519PublicKey: json['ed25519PublicKey'],
      x25519PublicKey: json['x25519PublicKey'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nickname': nickname,
      'ed25519PublicKey': ed25519PublicKey,
      'x25519PublicKey': x25519PublicKey,
    };
  }
}

class _HomePageState extends State<HomePage> {
  List<Message> messages = [];
  final TextEditingController messageController = TextEditingController();
  List<Contact> contacts = [];
  String? selectedUser;  // Başlangıçta seçili kullanıcı yok
  final TextEditingController _newContactController = TextEditingController();
  late Uint8List decryptedX25519;
  late Uint8List publicX25519;
  late Uint8List decryptedEd25519;
  late Uint8List publicEd25519;

  @override
  void initState() {
    super.initState();
    _loadAndDecryptKeys();
    _loadContacts();
    _loadMessages();
  }

  Uint8List pbkdf2(String password, Uint8List salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    final params = pc.Pbkdf2Parameters(salt, 10000, 32); // 32 byte key
    derivator.init(params);
    return derivator.process(utf8.encode(password));
  }

  Uint8List decryptAESGCM(Uint8List key, Uint8List encryptedData, Uint8List nonce) {
    final cipher = pc.GCMBlockCipher(pc.AESFastEngine());
    final aeadParams = pc.AEADParameters(pc.KeyParameter(key), 128, nonce, Uint8List(0));
    cipher.init(false, aeadParams); // false => decryption
    return cipher.process(encryptedData);
  }

  Future<void> _loadAndDecryptKeys() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/messaging_app/keys_${widget.nickname}.json');

      if (!await file.exists()) {
        throw Exception("Anahtar dosyası bulunamadı.");
      }

      final jsonData = jsonDecode(await file.readAsString());

      final encryptedX25519 = base64Decode(jsonData["encryptedX25519PrivateKey"]);
      final encryptedEd25519 = base64Decode(jsonData["encryptedEd25519PrivateKey"]);
      publicX25519 = base64Decode(jsonData["x25519PublicKey"]);
      publicEd25519 = base64Decode(jsonData["ed25519PublicKey"]);
      final salt = base64Decode(jsonData["salt"]);
      final nonce = base64Decode(jsonData["nonce"]); // base64Encode ile kaydedildiği için

      final key = pbkdf2(widget.password, salt);

      setState(() {
        decryptedX25519 = decryptAESGCM(key, encryptedX25519, nonce);
        decryptedEd25519 = decryptAESGCM(key, encryptedEd25519, nonce);
      });

      print("X25519 çözüldü: ${base64Encode(decryptedX25519)}");
      print("Ed25519 çözüldü: ${base64Encode(decryptedEd25519)}");

    } catch (e) {
      print("Şifre çözme hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Şifre çözme hatası: $e')),
        );
      }
    }
  }

  Future<void> _loadContacts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      final file = File('${appDir.path}/contacts_${widget.nickname}.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(content);

        final loadedContacts = jsonData
            .map((e) => Contact.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        setState(() {
          contacts = loadedContacts;
          selectedUser = contacts.isNotEmpty ? contacts[0].nickname : null;
          messages.clear();
        });
      } else {
        setState(() {
          contacts = [];
          selectedUser = null;
          messages.clear();
        });
        print('Contacts dosyası bulunamadı.');
      }
    } catch (e) {
      print('Contacts dosyası okunurken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kişiler yüklenemedi: $e')),
      );
    }
  }

  Future<void> _loadMessages() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      final file = File('${appDir.path}/messages_${widget.nickname}.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(content);

        final loadedMessages = jsonData.map((item) {
          return Message(
            sender: item['sender'],
            receiver: item['receiver'],
            content: item['content'],
            timestamp: DateTime.parse(item['timestamp']),
          );
        }).toList();

        setState(() {
          messages = loadedMessages;
        });

        print('Mesajlar yüklendi. (${messages.length} adet)');
        print(messages);
      } else {
        print('Mesaj dosyası bulunamadı. Yeni mesaj listesi oluşturulacak.');
        setState(() {
          messages = [];
        });
      }
    } catch (e) {
      print('Mesajlar yüklenirken hata oluştu: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesajlar yüklenemedi: $e')),
      );
    }
  }

  void sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty || selectedUser == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      final contactFile = File('${appDir.path}/contacts_${widget.nickname}.json');

      if (!await contactFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kişi listesi dosyası bulunamadı.')),
        );
        return;
      }

      final content = await contactFile.readAsString();
      final List<dynamic> contactList = jsonDecode(content);

      // selectedUser'ın public anahtarını bul
      final userContact = contactList.firstWhere(
        (contact) => contact['nickname'] == selectedUser,
        orElse: () => null,
      );

      if (userContact == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$selectedUser kişisi bulunamadı.')),
        );
        return;
      }

      final String receiverX25519Base64 = userContact['x25519PublicKey'];
      final Uint8List receiverX25519PublicKey = base64Decode(receiverX25519Base64);
      final encryptedMap = await encodeMessage(receiverX25519PublicKey, text);
      final jsonString = jsonEncode(encryptedMap);
      final encryptedMessageBase64 = base64Encode(utf8.encode(jsonString));
      final sendMessageDto = {
        "sender": widget.nickname,
        "receiver": selectedUser,
        "content": encryptedMessageBase64
      };


      final url = Uri.parse('https://localhost:7064/api/message/sendMessage');
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(sendMessageDto),
        );

        if (response.statusCode == 200) {
          final responseJson = jsonDecode(response.body);

          setState(() {
            messages.add(Message(
              sender: responseJson['sender'],
              receiver: responseJson['receiver'],
              content: text,
              timestamp: DateTime.parse(responseJson['timestamp']),
            ));
            messageController.clear();
          });
        } 
        else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mesaj gönderilemedi: Kullanıcı adı geçersiz.')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sunucu bağlantı hatası: $e')),
        );
      }
    } catch (e) {
      print('Kişi bilgisi okunurken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $e')),
      );
    }
  }

  Future<Map<String, dynamic>> encodeMessage(Uint8List receiverPublicKeyBytes,String message) async {
    final algorithm = X25519();

    // 1. Gönderenin private key objesini oluştur
    final publicKey = SimplePublicKey(publicX25519, type: KeyPairType.x25519,);
    final senderKeyPair = SimpleKeyPairData(decryptedX25519, publicKey: publicKey, type: KeyPairType.x25519,);

    // 2. Alıcının public key objesini oluştur
    final receiverPublicKey = SimplePublicKey(receiverPublicKeyBytes, type: KeyPairType.x25519);

    // 3. Ortak anahtar (shared secret) hesapla
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: senderKeyPair,
      remotePublicKey: receiverPublicKey,
    );

    // 4. Shared secret'tan AES anahtarı türet
    final sharedSecretBytes = await sharedSecret.extractBytes();

    // 5. Mesajı AES-GCM ile şifrele
    final aesGcm = AesGcm.with256bits();

    // Rastgele nonce (12 byte)
    final nonce = _generateNonce(12);

    final secretKey = SecretKey(sharedSecretBytes);

    final secretBox = await aesGcm.encrypt(
      utf8.encode(message),
      secretKey: secretKey,
      nonce: nonce,
    );

    // 6. Base64 olarak döndür
    return {
      'encryptedMessage': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  // Helper fonksiyon: rastgele nonce üretimi
  Uint8List _generateNonce(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }


  void addContact(String newNickname) async {
    final url = Uri.parse('https://localhost:7064/api/user/getKeysByNickname/$newNickname');
    try {
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);

        final newContactMap = {
          "nickname": newNickname,
          "ed25519PublicKey": jsonData["ed25519PublicKey"],
          "x25519PublicKey": jsonData["x25519PublicKey"],
        };

        final dir = await getApplicationDocumentsDirectory();
        final appDir = Directory('${dir.path}/messaging_app');
        final file = File('${appDir.path}/contacts_${widget.nickname}.json');

        List<Map<String, dynamic>> contactList = [];

        if (await file.exists()) {
          final existingContent = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(existingContent);
          contactList = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        }

        final alreadyExists = contactList.any((e) => e["nickname"] == newNickname);
        if (alreadyExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu kişi zaten ekli.')),
          );
          return;
        }

        contactList.add(newContactMap);

        await file.writeAsString(jsonEncode(contactList), flush: true);

        // ✅ Contact model nesnesi olarak da listeye ekleyelim
        final newContact = Contact.fromJson(newContactMap);
        setState(() {
          contacts.add(newContact);
          selectedUser = newNickname;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kişi başarıyla eklendi: $newNickname')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı eklemesi başarısız: Kullanıcı adı geçersiz.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sunucu bağlantı hatası: $e')),
      );
    }
  }

  void _showAddContactDialog() {
    _newContactController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Contact'),
        content: TextField(
          controller: _newContactController,
          decoration: const InputDecoration(
            labelText: 'Nickname',
            hintText: 'Enter new contact nickname',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newNickname = _newContactController.text;
              if (newNickname.isNotEmpty) {
                addContact(newNickname);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    messageController.dispose();
    _newContactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 25;
    final sidebarWidth = screenWidth * 0.15;
    final chatWidth = screenWidth * 0.85;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF212121), // Colors.grey[900]
          border: Border(
            bottom: BorderSide(color: const Color.fromARGB(255, 139, 3, 105), width: 1),
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Welcome, ${widget.nickname}',
            style: const TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Çıkış Yap',
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const MainPage()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey[850],
            border: Border.all(color: Colors.grey, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // 🔵 Sol Panel (%15)
              Container(
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  border: const Border(
                    right: BorderSide(color: Colors.white, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                      child: Text(
                        'Your Contacts',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Divider(color: Colors.deepPurple, thickness: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: contacts.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: Colors.deepPurple,
                          height: 1,
                          thickness: 1,
                        ),
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          final nickname = contact.nickname;
                          final isSelected = selectedUser == nickname;
                          return _HoverableUserItem(
                            nickname: nickname,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                selectedUser = nickname;
                                messages.clear(); // Seçim değişince mesajları temizle
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: const Text(
                          'Add Contact',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 30, 126, 210),
                          iconColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _showAddContactDialog(),
                      ),
                    ),
                  ],
                ),
              ),

              // Sağ Panel (%85)
              Container(
                width: chatWidth,
                child: Column(
                  children: [
                    // Seçili kişinin nickname gösteren üst şerit
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11.25, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                        ),
                        border: const Border(
                          bottom: BorderSide(color: Colors.white, width: 1),
                        ),
                      ),
                      child: Text(
                        selectedUser != null ? 'Chat with $selectedUser' : 'No contact selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),


                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple[400],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                //messages[index],
                                "",
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const Divider(height: 1, color: Colors.white),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: messageController,
                              enabled: selectedUser != null,
                              style: TextStyle(
                                color: selectedUser != null ? Colors.white : Colors.white54,
                              ),
                              decoration: InputDecoration(
                                hintText: selectedUser != null
                                    ? 'Mesaj yaz...'
                                    : 'Select a contact first',
                                hintStyle: TextStyle(color: Colors.white54),
                                filled: true,
                                fillColor: Colors.grey[800],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.send,
                              color: selectedUser != null ? Colors.white : Colors.white38,
                            ),
                            onPressed: selectedUser != null ? sendMessage : null,
                          ),
                        ],
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

class _HoverableUserItem extends StatefulWidget {
  final String nickname;
  final bool isSelected;
  final VoidCallback? onTap;

  const _HoverableUserItem({
    required this.nickname,
    this.isSelected = false,
    this.onTap,
  });

  @override
  State<_HoverableUserItem> createState() => _HoverableUserItemState();
}

class _HoverableUserItemState extends State<_HoverableUserItem> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    if (widget.isSelected) {
      bgColor = Colors.deepPurple[700]!;
    } else if (isHovered) {
      bgColor = Colors.deepPurple[300]!;
    } else {
      bgColor = Colors.transparent;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Text(
            widget.nickname,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
