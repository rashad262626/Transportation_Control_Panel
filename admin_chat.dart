import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminChatScreen extends StatefulWidget {
  final String chatId;
  final String userPhone;
  final String userName;

  const AdminChatScreen({
    super.key,
    required this.chatId,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  Future<void> sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance
          .collection('chat_chat')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'text': messageText,
        'sender': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
        'seenTimestamp': null,
      });

      await FirebaseFirestore.instance
          .collection('chat_chat')
          .doc(widget.chatId)
          .set({
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'status': 'open',
      }, SetOptions(merge: true));

      _messageController.clear();

      Future.delayed(const Duration(milliseconds: 200), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل إرسال الرسالة: $e')));
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> markMessagesAsSeen(List<QueryDocumentSnapshot> messages) async {
    final batch = FirebaseFirestore.instance.batch();
    bool hasUpdates = false;

    for (var msg in messages) {
      final data = msg.data() as Map<String, dynamic>;
      if (data['sender'] != 'admin' && data['seen'] == false) {
        final docRef = FirebaseFirestore.instance
            .collection('chat_chat')
            .doc(widget.chatId)
            .collection('messages')
            .doc(msg.id);
        batch.update(docRef, {
          'seen': true,
          'seenTimestamp': FieldValue.serverTimestamp(),
        });
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      try {
        await batch.commit();
      } catch (e) {
        debugPrint('خطأ في تحديث حالة القراءة: $e');
      }
    }
  }

  String formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return "${dateTime.day.toString().padLeft(2, '0')}/"
        "${dateTime.month.toString().padLeft(2, '0')}/"
        "${dateTime.year} - "
        "${dateTime.hour.toString().padLeft(2, '0')}:"
        "${dateTime.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.orange[50],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text(
              "أنت الآن تتحدث مع المستخدم. يرجى الرد على استفساراته.",
              style: TextStyle(fontSize: 14, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_chat')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final messages = snapshot.data!.docs;

                markMessagesAsSeen(messages);

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent + 80,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data() as Map<String, dynamic>;
                    final isAdmin = data['sender'] == 'admin';

                    return Align(
                      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisAlignment:
                        isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: CircleAvatar(
                                backgroundColor: Colors.grey[200],
                                backgroundImage: const AssetImage('assets/images/user.png'),
                                radius: 18,
                              ),
                            ),
                          Flexible(
                            child: Column(
                              crossAxisAlignment:
                              isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.symmetric(vertical: 5),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: isAdmin
                                        ? LinearGradient(
                                      colors: [
                                        Colors.deepPurple.shade400,
                                        Colors.deepPurple.shade300,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                        : LinearGradient(
                                      colors: [
                                        Colors.grey.shade300,
                                        Colors.grey.shade200,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isAdmin ? 16 : 0),
                                      bottomRight: Radius.circular(isAdmin ? 0 : 16),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(1, 2),
                                      )
                                    ],
                                  ),
                                  child: Text(
                                    data['text'],
                                    style: TextStyle(
                                      color: isAdmin ? Colors.white : Colors.black,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (isAdmin)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, right: 4),
                                    child: Text(
                                      (data['seen'] == true &&
                                          data['seenTimestamp'] != null)
                                          ? "تم الاطلاع ${formatTimestamp(data['seenTimestamp'])}"
                                          : "غير مقروء",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: data['seen'] == true
                                            ? Colors.green[800]
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: CircleAvatar(
                                backgroundColor: Colors.deepPurple[100],
                                child: const Icon(Icons.support_agent, color: Colors.white),
                                radius: 18,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
              color: Colors.white,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'اكتب ردك...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => sendMessage(),
                    enabled: !_isSending,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.send, color: Colors.deepPurple),
                  onPressed: _isSending ? null : sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
