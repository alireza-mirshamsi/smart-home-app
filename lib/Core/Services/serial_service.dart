import 'dart:typed_data';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class SerialService {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();

  Stream<bool> getConnectionStatus() {
    return _flutterSerialCommunicationPlugin
        .getDeviceConnectionListener()
        .receiveBroadcastStream()
        .map((event) => event as bool);
  }

  Stream<List<int>> getSerialMessages() {
    return _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .map((event) => event as List<int>);
  }

  Future<List<DeviceInfo>> getAvailableDevices() async {
    return await _flutterSerialCommunicationPlugin.getAvailableDevices();
  }

  Future<bool> connect(DeviceInfo deviceInfo, int baudRate) async {
    return await _flutterSerialCommunicationPlugin.connect(
      deviceInfo,
      baudRate,
    );
  }

  Future<void> disconnect() async {
    await _flutterSerialCommunicationPlugin.disconnect();
  }

  Future<bool> write(String command) async {
    return await _flutterSerialCommunicationPlugin.write(
      Uint8List.fromList(command.codeUnits),
    );
  }
}
