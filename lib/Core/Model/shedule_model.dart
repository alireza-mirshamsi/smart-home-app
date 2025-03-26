import 'package:flutter/material.dart';

class ScheduleModel {
  TimeOfDay? onTime;
  TimeOfDay? offTime;
  bool onTriggered; // نشان‌دهنده اجرای عملیات روشن
  bool offTriggered; // نشان‌دهنده اجرای عملیات خاموش

  ScheduleModel({
    this.onTime,
    this.offTime,
    this.onTriggered = false,
    this.offTriggered = false,
  });

  Map<String, dynamic> toJson() => {
    'onTime': onTime != null ? '${onTime!.hour}:${onTime!.minute}' : null,
    'offTime': offTime != null ? '${offTime!.hour}:${offTime!.minute}' : null,
    'onTriggered': onTriggered,
    'offTriggered': offTriggered,
  };

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      onTime:
          json['onTime'] != null
              ? TimeOfDay(
                hour: int.parse(json['onTime'].split(':')[0]),
                minute: int.parse(json['onTime'].split(':')[1]),
              )
              : null,
      offTime:
          json['offTime'] != null
              ? TimeOfDay(
                hour: int.parse(json['offTime'].split(':')[0]),
                minute: int.parse(json['offTime'].split(':')[1]),
              )
              : null,
      onTriggered: json['onTriggered'] ?? false,
      offTriggered: json['offTriggered'] ?? false,
    );
  }
}
