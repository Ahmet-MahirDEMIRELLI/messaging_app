import 'dart:io';
import 'package:flutter/material.dart';
import 'package:messaging_app/main_page.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  final String nickname;

  const HomePage({super.key, required this.nickname});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> messages = [];
  final TextEditingController messageController = TextEditingController();
  List<Map<String, dynamic>> contacts = [];
  String? selectedUser;  // Başlangıçta seçili kullanıcı yok
  final TextEditingController _newContactController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void sendMessage() {
    final text = messageController.text.trim();
    if (text.isNotEmpty && selectedUser != null) {
      setState(() {
        messages.add(text);
        messageController.clear();
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/contacts_${widget.nickname}.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonData = jsonDecode(content);
        setState(() {
          contacts = jsonData
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
          // Eğer kontak varsa, seçili kullanıcıyı ilk kontak yap
          if (contacts.isNotEmpty) {
            selectedUser = contacts[0]['nickname'];
          } else {
            selectedUser = null;
          }
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
              final newNickname = _newContactController.text.trim();
              if (newNickname.isNotEmpty) {
                setState(() {
                  contacts.add({'nickname': newNickname, 'public_key': ''});
                  // Eğer ilk kontak ise seçili kullanıcı yap
                  if (selectedUser == null) {
                    selectedUser = newNickname;
                  }
                });
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
                          final nickname = contact['nickname'] ?? '';
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
                                messages[index],
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
