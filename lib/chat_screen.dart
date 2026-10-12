import 'dart:async';

import 'package:flutter/material.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final BluetoothChatService _chatService = BluetoothChatService();

  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  StreamSubscription<ChatMessage>? _messageSubscription;

  String _connectionStatus = 'غير متصل';

  final String _myUserId =
      'user_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();

    _listenToMessages();
  }

  // استقبال الرسائل الواردة
  void _listenToMessages() {
    _messageSubscription = _chatService.onMessageReceived.listen(
      (ChatMessage message) {
        if (!mounted) return;

        setState(() {
          _messages.add(message);
        });

        _scrollToBottom();
      },
      onError: (Object error) {
        if (!mounted) return;

        setState(() {
          _connectionStatus = 'حدث خطأ أثناء استقبال الرسائل';
        });

        debugPrint('Message stream error: $error');
      },
    );
  }

  // الانتقال إلى آخر رسالة
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // إرسال الرسالة
  Future<void> _sendMessage() async {
    final String text = _controller.text.trim();

    if (text.isEmpty) return;

    final ChatMessage message = ChatMessage(
      senderId: _myUserId,
      text: text,
      timestamp: DateTime.now(),
    );

    // إضافة الرسالة إلى الواجهة
    setState(() {
      _messages.add(message);
    });

    _controller.clear();

    _scrollToBottom();

    try {
      await _chatService.sendMessage(_myUserId, text);
    } catch (error) {
      debugPrint('Send message error: $error');

      if (!mounted) return;

      setState(() {
        _connectionStatus = 'تعذر إرسال الرسالة';
      });
    }
  }

  // البحث عن الأجهزة والاتصال بها
  Future<void> _scanAndConnect() async {
    if (!mounted) return;

    setState(() {
      _connectionStatus = 'جارٍ البحث عن الأجهزة...';
    });

    try {
      await _chatService.scanAndConnect((String status) {
        if (!mounted) return;

        setState(() {
          _connectionStatus = status;
        });
      });
    } catch (error) {
      debugPrint('Bluetooth connection error: $error');

      if (!mounted) return;

      setState(() {
        _connectionStatus = 'فشل الاتصال';
      });
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();

    _controller.dispose();
    _scrollController.dispose();

    // إذا كان chatService مشتركًا بين عدة صفحات،
    // فلا تغلقه هنا قبل التأكد من ملكية هذا الكائن.

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),

      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'واتساب بلوتوث',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(
              _connectionStatus,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'البحث عن الأجهزة',
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: _scanAndConnect,
          ),
        ],
      ),

      body: Column(
        children: [
          // قائمة الرسائل
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد رسائل حتى الآن',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,

                    itemBuilder: (context, index) {
                      final ChatMessage msg = _messages[index];

                      final bool isMe =
                          msg.senderId == _myUserId;

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,

                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78,
                          ),

                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),

                          padding: const EdgeInsets.all(10),

                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFFDCF8C6)
                                : Colors.white,

                            borderRadius: BorderRadius.circular(10),
                          ),

                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                msg.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text(
                                '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
                                '${msg.timestamp.minute.toString().padLeft(2, '0')}',

                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // حقل كتابة الرسائل
          SafeArea(
            top: false,

            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),

              color: Colors.white,

              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,

                      textInputAction: TextInputAction.send,

                      onSubmitted: (_) => _sendMessage(),

                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF3F3F3),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  IconButton(
                    tooltip: 'إرسال الرسالة',
                    onPressed: _sendMessage,

                    icon: const Icon(
                      Icons.send,
                      color: Color(0xFF075E54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}