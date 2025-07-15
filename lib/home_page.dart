import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'main_page.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:media_store_plus/media_store_plus.dart';

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
  final bool isRead;

  Message({
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isRead,
  });

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'receiver': receiver,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      sender: json['sender'],
      receiver: json['receiver'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['isRead'] ?? false,
    );
  }

  Message copyWith({
    String? sender,
    String? receiver,
    String? content,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return Message(
      sender: sender ?? this.sender,
      receiver: receiver ?? this.receiver,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }
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

class ChatItem {
  final Message? message;
  final DateTime? dateHeader;

  ChatItem.message(this.message) : dateHeader = null;
  ChatItem.dateHeader(this.dateHeader) : message = null;
}

class _HomePageState extends State<HomePage> {
  List<Message> messages = [];
  List<Message> messagesToShow = [];
  Map<String, int> unreadCounts = {};
  List<Contact> contacts = [];
  final TextEditingController _messageController = TextEditingController();
  String? selectedUser;
  final TextEditingController _newContactController = TextEditingController();
  late Uint8List decryptedX25519;
  late Uint8List publicX25519;
  late Uint8List decryptedEd25519;
  late Uint8List publicEd25519;
  DateTime lastMessageDateTime = DateTime(2000).toUtc().add(const Duration(hours: 3));
  Timer? _timer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    asyncInit(); // Async işlemleri burada başlat
  }

  void asyncInit() async {
    await _loadAndDecryptKeys();
    await _loadContacts();
    await _loadMessages();
    await getNewMessages();
    setState(() {
      unreadCounts = getUnreadCounts();
    });

    if(selectedUser != null){
      showMessages();
    }

    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      getNewMessages();
    });
  }

  void showMessages() {
    setState(() {
      messagesToShow = messages.where((msg) =>
        msg.sender == selectedUser || msg.receiver == selectedUser
      ).toList();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
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
      final nonce = base64Decode(jsonData["nonce"]);

      final key = pbkdf2(widget.password, salt);

      setState(() {
        decryptedX25519 = decryptAESGCM(key, encryptedX25519, nonce);
        decryptedEd25519 = decryptAESGCM(key, encryptedEd25519, nonce);
      });
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
        });
      } else {
        setState(() {
          contacts = [];
          selectedUser = null;
          messages.clear();
        });
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
        final decryptedMessages = await decryptLoadedMessages(jsonData);

        setState(() {
          messages.addAll(decryptedMessages);
        });

        for(int i = 0; i < messages.length; i++){
          if (lastMessageDateTime.isBefore(messages[i].timestamp)) {
            lastMessageDateTime = messages[i].timestamp.add(const Duration(microseconds: 1));
          }
        }
      } 
      else {
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
    final text = _messageController.text.trim();

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
      final String dataToSign = '${widget.nickname.toLowerCase()}|${selectedUser?.toLowerCase()}|$encryptedMessageBase64';
      final Uint8List signatureBytes = await signWithPrivateKey(dataToSign);
      final String signatureBase64 = base64Encode(signatureBytes);
      final sendMessageDto = {
        "sender": widget.nickname,
        "receiver": selectedUser,
        "content": encryptedMessageBase64,
        "signature": signatureBase64,
      };


      final url = Uri.parse('https://whisprapi.ahmetmahirdemirelli.com/api/message/sendMessage');
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(sendMessageDto),
        );

        if (response.statusCode == 200) {
          final responseJson = jsonDecode(response.body);
          DateTime msgTime = DateTime.parse(responseJson['timestamp']);
          Message newMessage = Message(sender: responseJson['sender'], receiver: responseJson['receiver'], content: "Your message", timestamp: msgTime, isRead: true);
          setState(() {
            messages.add(newMessage);
            messagesToShow.add(newMessage);
            _messageController.clear();
          });

          List<Message> encryptedMessages = [];
          encryptedMessages.add(newMessage);
          await saveMessages(encryptedMessages);
        }
        else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mesaj gönderilemedi: İmza geçersiz.')),
          ); 
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

  Future<void> getNewMessages() async{
    final url = Uri.parse('https://whisprapi.ahmetmahirdemirelli.com/api/message/getNewMessages/${widget.nickname}/${lastMessageDateTime.toIso8601String()}');
    try {
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'}
      );

      if (response.statusCode == 200) {
        final List<dynamic> responseJson = jsonDecode(response.body);
        await processNewMessages(responseJson);
      } 
      else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sistem hatası')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sunucu bağlantı hatası: $e')),
      );
    }
  }

  Future<void> processNewMessages(List<dynamic> responseJson) async {
    List<Message> newMessages = [];
    List<Message> encryptedMessages = [];
    for (var item in responseJson) {
      try {
        String decryptedContent = await decodeMessage(item['sender'], item['content']);
        DateTime msgTime = DateTime.parse(item['timestamp']).toUtc().add(const Duration(hours: 3));
        Message newMessage = Message(sender: item['sender'], receiver: item['receiver'], content: decryptedContent, timestamp: msgTime, isRead: selectedUser == item['sender'] ? true : false);
        if(!newMessage.isRead){
          setState(() {
            setState(() {
              unreadCounts.update(
                newMessage.sender,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            });
          });
        }

        newMessages.add(newMessage);
        Message encryptedMessage = newMessage.copyWith(content: item['content']);
        encryptedMessages.add(encryptedMessage);

        if (lastMessageDateTime.isBefore(msgTime)) {
          lastMessageDateTime = msgTime.add(const Duration(microseconds: 1));
        }
      } 
      catch (e, stack) {
        print('Error decoding message from ${item['sender']}: $e');
        print(stack);
      }
    }

    setState(() {
      messages.addAll(newMessages);
      final matchedMessages = newMessages.where((msg) =>
        msg.sender == selectedUser || msg.receiver == selectedUser
      );
      messagesToShow.addAll(matchedMessages);
    });

    if (encryptedMessages.isNotEmpty) {
      await saveMessages(encryptedMessages);
    }
  }

  Future<void> saveMessages(List<Message> messagesToSave) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final file = File('${appDir.path}/messages_${widget.nickname}.json');

      List<dynamic> existingMessages = [];

      if (!await file.exists()) {
        await file.create(recursive: true);
        await file.writeAsString('[]', flush: true);
      }

      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        existingMessages = jsonDecode(content);
      }

      for (var msg in messagesToSave) {
        existingMessages.add(msg.toJson());
      }

      // Dosyaya yaz
      final encoder = const JsonEncoder.withIndent('  ');
      final beautifiedJson = encoder.convert(existingMessages);
      await file.writeAsString(beautifiedJson, flush: true);
    } 
    catch (e) {
      print('Mesaj kaydedilirken hata oluştu: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj kaydedilemedi: $e')),
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

  Future<String> decodeMessage(String senderNickname, String encryptedData) async {
    // 1. contacts listesinden sender'ın public key'i bulunuyor
    final contactEntry = await getContactOrAdd(senderNickname);

    final senderPublicKeyBase64 = contactEntry.x25519PublicKey;
    final senderPublicKeyBytes = base64Decode(senderPublicKeyBase64);

    // 2. encryptedData JSON string olarak geliyor, parse et
    final decodedJsonString = utf8.decode(base64Decode(encryptedData));
    final Map<String, dynamic> encryptedJson = jsonDecode(decodedJsonString);
    final encryptedMessage = base64Decode(encryptedJson['encryptedMessage']);
    final nonce = base64Decode(encryptedJson['nonce']);
    final macBytes = base64Decode(encryptedJson['mac']);

    // 3. Ortak anahtarı hesapla (X25519)
    final algorithm = X25519();
    final receiverPublicKey = SimplePublicKey(publicX25519, type: KeyPairType.x25519,);
    final receiverKeyPair = SimpleKeyPairData(decryptedX25519, publicKey: receiverPublicKey, type: KeyPairType.x25519,);

    final senderPublicKey = SimplePublicKey(
      senderPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: receiverKeyPair,
      remotePublicKey: senderPublicKey,
    );

    final sharedSecretBytes = await sharedSecret.extractBytes();

    // 4. AES-GCM ile şifre çözme
    final aesGcm = AesGcm.with256bits();
    final secretKey = SecretKey(sharedSecretBytes);
    final secretBox = SecretBox(
      encryptedMessage,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decryptedBytes);
  }

  Future<List<Message>> decryptLoadedMessages(List<dynamic> jsonData) async {
    final List<Future<Message>> decryptFutures = jsonData.map((item) async {
      String decryptedContent;
      if(item['sender'] != widget.nickname){
        decryptedContent = await decodeMessage(item['sender'], item['content']);
      }
      else{
        decryptedContent = "Your message";
      }

      DateTime msgTime = DateTime.parse(item['timestamp']);
      if (lastMessageDateTime.isBefore(msgTime)) {
        lastMessageDateTime = msgTime.add(const Duration(microseconds: 1));
      }

      return Message(
        sender: item['sender'],
        receiver: item['receiver'],
        content: decryptedContent,
        timestamp: DateTime.parse(item['timestamp']),
        isRead: item['isRead'] ?? false,
      );
    }).toList();

    // Tüm şifre çözüm işlemleri bitince liste dön
    return await Future.wait(decryptFutures);
  }

  Uint8List _generateNonce(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> signWithPrivateKey(String data) async {
    final algorithm = Ed25519();
    final senderPublicKey = SimplePublicKey(publicEd25519, type: KeyPairType.ed25519,);
    final senderKeyPair = SimpleKeyPairData(decryptedEd25519, publicKey: senderPublicKey, type: KeyPairType.ed25519,);
    final signature = await algorithm.sign(
      utf8.encode(data),
      keyPair: senderKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }
  
  Future<Contact> getContactOrAdd(String senderNickname) async {
    // 1. Kişi zaten var mı kontrol et
    Contact? contactEntry = contacts.firstWhereOrNull((c) => c.nickname == senderNickname);

    // 2. Yoksa kişiyi eklemeyi dene
    if (contactEntry == null) {
      await addContact(senderNickname);

      // 3. Ekledikten sonra tekrar kontrol et
      contactEntry = contacts.firstWhere(
        (c) => c.nickname == senderNickname,
        orElse: () => throw Exception('Gönderen bulunamadı: $senderNickname'),
      );
    }

    return contactEntry;
  }
  
  Future<void> addContact(String newNickname) async {
    final url = Uri.parse('https://whisprapi.ahmetmahirdemirelli.com/api/user/getKeysByNickname/$newNickname');
    try {
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);

        final newContactMap = {
          "nickname": newNickname.toLowerCase(),
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

        final encoder = const JsonEncoder.withIndent('  ');
        final beautifiedJson = encoder.convert(contactList);
        await file.writeAsString(beautifiedJson, flush: true);

        // ✅ Contact model nesnesi olarak da listeye ekleyelim
        final newContact = Contact.fromJson(newContactMap);
        setState(() {
          contacts.add(newContact);
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

  List<ChatItem> buildChatItems(List<Message> messages) {
    List<ChatItem> chatItems = [];
    DateTime? lastDate;

    for (var msg in messages) {
      final msgDate = DateTime(msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);

      if (lastDate == null || msgDate.isAfter(lastDate)) {
        chatItems.add(ChatItem.dateHeader(msgDate));
        lastDate = msgDate;
      }
      chatItems.add(ChatItem.message(msg));
    }
    return chatItems;
  }
  
  Map<String, int> getUnreadCounts() {
    final Map<String, int> unreadCountMap = {};

    for (var msg in messages) {
      if (!msg.isRead) {
        unreadCountMap.update(msg.sender, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    return unreadCountMap;
  }

  Future<void> markRead() async{
    setState(() {
      if (unreadCounts.containsKey(selectedUser)) {
        unreadCounts.remove(selectedUser);
      }
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      final file = File('${appDir.path}/messages_${widget.nickname}.json');

      List<dynamic> existingMessages = [];

      if (!await file.exists()) {
        await file.create(recursive: true);
        await file.writeAsString('[]', flush: true);
      }

      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        existingMessages = jsonDecode(content);
      }

      // Sondan başa işle
      for (var i = existingMessages.length - 1; i >= 0; i--) {
        final msg = existingMessages[i];
        
        if (msg is Map<String, dynamic>) {
          final isTargetMessage = msg['sender'] == selectedUser;

          if (!isTargetMessage) continue;

          if (msg['isRead'] == false) {
            msg['isRead'] = true;
          } 
          else {
            // İlk okunmuş mesaja ulaştıysan daha geriye gitmeye gerek yok
            break;
          }
        }
      }

      // Dosyaya yaz
      final encoder = const JsonEncoder.withIndent('  ');
      final beautifiedJson = encoder.convert(existingMessages);
      await file.writeAsString(beautifiedJson, flush: true);
    } 
    catch (e) {
      print('Mesaj kaydedilirken hata oluştu: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj kaydedilemedi: $e')),
      );
    }
  }

  Future<void> _clearMessages() async {
    setState(() {
      // selectedUser olan mesajları filtrele, sadece diğer mesajları bırak
      messages = messages.where((msg) =>
        msg.sender != selectedUser && msg.receiver != selectedUser
      ).toList();

      messagesToShow = [];
    });

    // Güncellenmiş mesajları dosyaya kaydet
    try {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/messaging_app');
      final file = File('${appDir.path}/messages_${widget.nickname}.json');

      if (await file.exists()) {
        // messages listesini json'a çevirip yaz
        final jsonStr = jsonEncode(messages.map((m) => m.toJson()).toList());
        await file.writeAsString(jsonStr);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçili kişiyle olan mesajlar temizlendi.')),
      );
    } catch (e) {
      print('Mesajlar temizlenirken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesajlar temizlenirken hata oluştu: $e')),
      );
    }
  }
  
  String getTurkishDate(DateTime? dateTime){
    if (dateTime == null) return '';
  
    int day = dateTime.day;
    int month = dateTime.month;
    int year = dateTime.year;
    String monthTurkish = "";

    switch(month){
      case 1:
        monthTurkish = "Ocak";
        break;
      case 2:
        monthTurkish = "Şubat";
        break;
      case 3:
        monthTurkish = "Mart";
        break;
      case 4:
        monthTurkish = "Nisan";
        break;
      case 5:
        monthTurkish = "Mayıs";
        break;
      case 6:
        monthTurkish = "Haziran";
        break;
      case 7:
        monthTurkish = "Temmuz";
        break;
      case 8:
        monthTurkish = "Ağustos";
        break;
      case 9:
        monthTurkish = "Eylül";
        break;
      case 10:
        monthTurkish = "Ekim";
        break;
      case 11:
        monthTurkish = "Kasım";
        break;
      case 12:
        monthTurkish = "Aralık";
        break;
    }

    return '$day $monthTurkish $year';
  }
  
  void _showAddContactDialog() {
    _newContactController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Kişi Ekle'),
        content: TextField(
          controller: _newContactController,
          decoration: const InputDecoration(
            labelText: 'Kullanıcı adı',
            hintText: 'Yeni kişinin kullanıcı adını giriniz',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final newNickname = _newContactController.text;
              if (newNickname.isNotEmpty) {
                addContact(newNickname);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> saveToDownloadWithMediaStore() async {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = "messaging_app";
    final mediaStore = MediaStore();

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sourceFile = File('${appDir.path}/messaging_app/keys_${widget.nickname}.json');

      if (!await sourceFile.exists()) {
        print("❌ Kaynak dosya bulunamadı: ${sourceFile.path}");
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/keys_${widget.nickname}.json';

      await sourceFile.copy(tempFilePath);

      await mediaStore.saveFile(
        tempFilePath: tempFilePath,
        dirType: DirType.download,
        dirName: DirName.download,
        relativePath: "MySecureKeys",
      );
    } catch (e) {
      print("❌ Hata oluştu: $e");
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _newContactController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 25;
    final isMobile = screenWidth < 600;
    double contentWidth = defaultTargetPlatform == TargetPlatform.android
        ? screenWidth * 0.95
        : screenWidth * 0.8;
    final sidebarWidth = isMobile ? contentWidth : contentWidth * 0.15;
    final chatWidth = isMobile ? contentWidth : contentWidth * 0.85;
    final chatItems = buildChatItems(messagesToShow);

    bool showChat = selectedUser != null;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF212121),
            border: Border(
              bottom: BorderSide(color: Color.fromARGB(255, 139, 3, 105), width: 1),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Hoşgeldin ${widget.nickname}',
              style: const TextStyle(color: Colors.white),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (defaultTargetPlatform == TargetPlatform.android)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'logout') {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (context) => const MainPage()),
                        (route) => false,
                      );
                    } else if (value == 'download_keys') {
                      saveToDownloadWithMediaStore();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: Text('Çıkış Yap'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'download_keys',
                      child: Text('Keys Dosyasını İndir'),
                    ),
                  ],
                )
              else
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
          child: isMobile
              ? (!showChat
                  ? _buildSidebar(sidebarWidth)
                  : _buildChat(chatWidth, chatItems))
              : Row(
                  children: [
                    _buildSidebar(sidebarWidth),
                    _buildChat(chatWidth, chatItems),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSidebar(double width) {
    return Container(
      width: width,
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
            padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
            child: Text(
              'Kişileriniz',
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
                final unreadCount = unreadCounts[nickname] ?? 0;
                return _HoverableUserItem(
                  nickname: nickname,
                  isSelected: isSelected,
                  unreadCount: unreadCount,
                  onTap: () {
                    setState(() {
                      selectedUser = nickname;
                      showMessages();
                      markRead();
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
                'Kişi Ekle',
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
    );
  }

  Widget _buildChat(double width, List<ChatItem> chatItems) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Başlık kısmı - mobilde geri butonu göster
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11.25, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: isMobile
                  ? const BorderRadius.only(
                      topRight: Radius.circular(12),
                      topLeft: Radius.circular(12),
                    )
                  : const BorderRadius.only(
                      topRight: Radius.circular(12),
                    ),
              border: const Border(
                bottom: BorderSide(color: Colors.white, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        selectedUser = null;  // Geri dönmek için seçili kullanıcıyı kaldır
                      });
                    },
                  ),
                Expanded(
                  child: Text(
                    selectedUser ?? 'Kişi seçilmedi',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Yeni: sağa dikey üç nokta menüsü
                if (selectedUser != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'clear_messages') {
                        _clearMessages();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'clear_messages',
                        child: Text('Mesajları Temizle'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: chatItems.length,
              controller: _scrollController,
              itemBuilder: (context, index) {
                final item = chatItems[index];
                if (item.dateHeader != null) {
                  final dateStr = getTurkishDate(item.dateHeader);
                  return Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        dateStr,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                } else {
                  final msg = item.message!;
                  final isMine = msg.sender == widget.nickname;
                  final timeText =
                      "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}";

                  return Align(
                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.purple[400] : Colors.blue[700],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            msg.content,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeText,
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }
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
                    controller: _messageController,
                    enabled: selectedUser != null,
                    style: TextStyle(
                      color: selectedUser != null ? Colors.white : Colors.white54,
                    ),
                    decoration: InputDecoration(
                      hintText: selectedUser != null ? 'Mesaj yaz...' : 'Select a contact first',
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
    );
  }

}


class _HoverableUserItem extends StatefulWidget {
  final String nickname;
  final bool isSelected;
  final VoidCallback? onTap;
  final int unreadCount;

  const _HoverableUserItem({
    required this.nickname,
    this.isSelected = false,
    this.onTap,
    this.unreadCount = 0,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.nickname,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              if (widget.unreadCount != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
