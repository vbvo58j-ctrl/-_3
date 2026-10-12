import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ChatMessage {
  final String senderId;
  final String text;
  final DateTime timestamp;

  ChatMessage({required this.senderId, required this.text, required this.timestamp});

  Map<String, dynamic> toJson() => {
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        senderId: json['senderId'],
        text: json['text'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

class BluetoothChatService {
  // معرفات افتراضية لخدمة البلوتوث الخاصة بالتطبيق
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26aae";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _valueSubscription;

  bool _isConnecting = false; // قفل لمنع تضارب طلبات الاتصال المتكررة

  final StreamController<ChatMessage> _messageController = StreamController.broadcast();
  Stream<ChatMessage> get onMessageReceived => _messageController.stream;

  // البحث والاتصال بجهاز قريب مع حماية ضد التضارب
  Future<void> scanAndConnect(Function(String) onStatusUpdate) async {
    if (_isConnecting || FlutterBluePlus.isScanningNow) return;
    _isConnecting = true;

    onStatusUpdate("جاري البحث عن أجهزة قريبة...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult result in results) {
        if (result.advertisementData.serviceUids.contains(serviceUuid)) {
          await FlutterBluePlus.stopScan();
          onStatusUpdate("جاري الاتصال بـ ${result.device.platformName}...");
          await _connectToDevice(result.device, onStatusUpdate);
          break;
        }
      }
    });
    
    // إعادة تعيين قفل الاتصال بعد انتهاء المهلة
    Future.delayed(const Duration(seconds: 6), () {
      _isConnecting = false;
    });
  }

  // تنفيذ الاتصال الفعلي وإدارة الخدمات
  Future<void> _connectToDevice(BluetoothDevice device, Function(String) onStatusUpdate) async {
    try {
      if (_connectedDevice != null) return;

      await device.connect(autoConnect: false);
      _connectedDevice = device;

      // مراقبة حالة قطع الاتصال لتنظيف الموارد تلقائياً
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _cleanUpConnection();
          onStatusUpdate("تم انقطاع الاتصال");
        }
      });

      onStatusUpdate("جاري تجهيز قنوات المحادثة...");
      List<BluetoothService> services = await device.discoverServices();
      
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
              _targetCharacteristic = characteristic;
              await characteristic.setNotifyValue(true);
              
              _valueSubscription = characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  _parseIncomingData(value);
                }
              });

              onStatusUpdate("متصل وجاهز للدردشة");
              _isConnecting = false;
              return;
            }
          }
        }
      }
    } catch (e) {
      _cleanUpConnection();
      _isConnecting = false;
      onStatusUpdate("فشل الاتصال: $e");
    }
  }

  // إرسال الرسائل مع تقسيم الحزم (MTU Fragmentation Protection) لمنع تلف البيانات
  Future<void> sendMessage(String senderId, String text) async {
    if (_targetCharacteristic == null || _connectedDevice == null) return;

    ChatMessage message = ChatMessage(
      senderId: senderId, 
      text: text, 
      timestamp: DateTime.now(),
    );

    String jsonString = jsonEncode(message.toJson());
    List<int> bytes = utf8.encode(jsonString);

    // طلب حجم الحزمة المناسب لتجنب رفض الحزم الكبيرة
    int mtu = await _connectedDevice!.requestMtu(512);
    int chunkSize = mtu - 3; 

    for (int i = 0; i < bytes.length; i += chunkSize) {
      int end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      List<int> chunk = bytes.sublist(i, end);
      
      await _targetCharacteristic!.write(chunk, withoutResponse: true);
    }
  }

  final List<int> _incomingBuffer = [];
  void _parseIncomingData(List<int> data) {
    _incomingBuffer.addAll(data);
    try {
      String jsonString = utf8.decode(_incomingBuffer);
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      ChatMessage message = ChatMessage.fromJson(jsonMap);
      
      _messageController.add(message);
      _incomingBuffer.clear(); // تفريغ المؤقت عند نجاح قراءة الرسالة كاملة
    } catch (e) {
      // الحزمة غير مكتملة، يتم الانتظار حتى وصول باقي البيانات في الدفق القادم
    }
  }

  void _cleanUpConnection() {
    _scanSubscription?.cancel();
    _valueSubscription?.cancel();
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    _targetCharacteristic = null;
    _incomingBuffer.clear();
    _isConnecting = false;
  }
}
