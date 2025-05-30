import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Thrown when specific device to open connection to is not found
class DeviceNotFoundException extends PlatformException {
  DeviceNotFoundException(String code, String message, String details)
      : super(
          code: code,
          message: message,
          details: details,
        );
}

/// Thrown when device has no interfaces, or when ```getInterface``` method did not return interface
class InterfaceNotFoundException extends PlatformException {
  InterfaceNotFoundException(String code, String message, String details)
      : super(
          code: code,
          message: message,
          details: details,
        );
}

/// Thrown when ```getEndpointCount``` returns 0, or when ```getEndpoint``` method did not return endpoint
class EndpointNotFoundException extends PlatformException {
  EndpointNotFoundException(String code, String message, String details)
      : super(
          code: code,
          message: message,
          details: details,
        );
}

class ListDevicesException extends PlatformException {
  ListDevicesException(String code, String message, String details)
      : super(
          code: code,
          message: message,
          details: details,
        );
}

/// Thrown when failed to obtain permission to connect to device.
class PermissionException extends PlatformException {
  PermissionException(String code, String message, String details)
      : super(
          code: code,
          message: message,
          details: details,
        );
}

/*
Copyright by Ron Bessems (https://github.com/altera2015/usbserial)
*/
class FUWEvent {
  /// Event passed to usbEventStream when a USB device is attached.
  // ignore: constant_identifier_names
  static const String ACTION_USB_ATTACHED =
      "android.hardware.usb.action.USB_DEVICE_ATTACHED";

  /// Event passed to usbEventStream when a USB device is detached.
  // ignore: constant_identifier_names
  static const String ACTION_USB_DETACHED =
      "android.hardware.usb.action.USB_DEVICE_DETACHED";

  /// either ACTION_USB_ATTACHED or ACTION_USB_DETACHED
  String event = "";

  /// The device for which the event was fired.
  FUWDevice? device;

  @override
  String toString() {
    return "FUWEvent: $event, $device";
  }

  Map<String, dynamic> toJson() => {
        'event': event,
        'device': device?.toJson(),
      };
}

/*
Copyright by Ron Bessems (https://github.com/altera2015/usbserial)
*/
/// FUWDevice holds the USB device information
///
/// This is used to determine which Usb Device to open.
class FUWDevice {
  /// Vendor Id
  final int vid;

  /// Product Id
  final int pid;
  final String productName;
  final String manufacturerName;

  /// The device id is unique to this Usb Device until it is unplugged.
  /// when replugged this ID will be different.
  final int deviceId;

  /// The Serial number from the USB device.
  final String? serial;

  FUWDevice(this.vid, this.pid, this.productName, this.manufacturerName,
      this.deviceId, this.serial);

  static FUWDevice fromJSON(dynamic json) {
    return FUWDevice(json["vid"], json["pid"], json["productName"],
        'json["manufacturerName"]', json["deviceId"], json["serialNumber"]);
  }

  Map<String, dynamic> toJson() => {
        'vid': vid,
        'pid': pid,
        'productName': productName,
        'manufacturerName': manufacturerName,
        'deviceId': deviceId,
        'serialNumber': serial,
      };

  @override
  String toString() {
    return "FUWDevice: ${vid.toRadixString(16)}-${pid.toRadixString(16)} $productName, $manufacturerName $serial";
  }
}

class FlutterUsbWrite {
  /// Initializes the plugin and starts listening for potential platform events.
  factory FlutterUsbWrite() {
    if (_instance == null) {
      const MethodChannel methodChannel =
          MethodChannel('flutter_usb_write/methods');
      const EventChannel eventChannel =
          EventChannel('flutter_usb_write/events');
      _instance = FlutterUsbWrite.private(methodChannel, eventChannel);
    }
    return _instance!;
  }

  /// This constructor is only used for testing and shouldn't be accessed by
  /// users of the plugin. It may break or change at any time.
  @visibleForTesting
  FlutterUsbWrite.private(this._methodChannel, this._eventChannel);

  static FlutterUsbWrite? _instance;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<FUWEvent>? _eventStream;

  Stream<FUWEvent> get usbEventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map<FUWEvent>((value) {
        FUWEvent msg = FUWEvent();
        msg.device = FUWDevice.fromJSON(value);
        msg.event = value["event"];
        return msg;
      });
    return _eventStream!;
  }

  /// Returns a list of FWUDevices currently plugged in.
  Future<List<FUWDevice>> listDevices() async {
    List<dynamic> devices = await _methodChannel.invokeMethod("listDevices");
    print(devices.map(FUWDevice.fromJSON).toList().toString());
    return devices.map(FUWDevice.fromJSON).toList();
  }

  /// Opens connection to device with specified deviceId, or with specified VendorId and ProductId
  Future<FUWDevice> open({
    int? deviceId,
    int? vendorId,
    int? productId,
  }) async {
    Map<String, dynamic> args = {
      "vid": vendorId,
      "pid": productId,
      "deviceId": deviceId
    };
    try {
      dynamic result = await _methodChannel.invokeMethod("open", args);
      return FUWDevice.fromJSON(result);
    } on PlatformException catch (e) {
      throw _getTypedException(e);
    }
  }

  /// Sends raw bytes to USB device.
  /// Requires open connection to USB device.
  Future<bool> write(Uint8List bytes) async {
    Map<String, dynamic> args = {"bytes": bytes};
    try {
      return await _methodChannel.invokeMethod("write", args);
    } on PlatformException catch (e) {
      throw _getTypedException(e);
    }
  }

  /// Close USB connection
  Future close() async {
    try {
      return await _methodChannel.invokeMethod("close");
    } on PlatformException catch (e) {
      throw _getTypedException(e);
    }
  }

  /// Optionally set transfer control.
  /// Since this plugin supports only sending data to device, only Device-To-Host ```[requestType]``` makes sense.
  Future<int> controlTransfer(int requestType, int request, int value,
      int index, Uint8List buffer, int length, int timeout) async {
    Map<String, dynamic> args = {
      "requestType": requestType,
      "request": request,
      "value": value,
      "index": index,
      "buffer": buffer,
      "length": length,
      "timeout": timeout = 0,
    };
    try {
      return await _methodChannel.invokeMethod("controlTransfer", args);
    } on PlatformException catch (e) {
      throw _getTypedException(e);
    }
  }

  Exception _getTypedException(PlatformException e) {
    switch (e.code) {
      case "DEVICE_NOT_FOUND_ERROR":
        return DeviceNotFoundException(e.code, e.message ?? "", e.details);
      case "INTERFACE_NOT_FOUND_ERROR":
        return InterfaceNotFoundException(e.code, e.message ?? "", e.details);
      case "ENDPOINT_NOT_FOUND_ERROR":
        return EndpointNotFoundException(e.code, e.message ?? "", e.details);
      case "LIST_DEVICES_ERROR":
        return ListDevicesException(e.code, e.message ?? "", e.details);
      case "PERMISSION_ERROR":
        return PermissionException(e.code, e.message ?? "", e.details);
      default:
        return e;
    }
  }
}
