import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'note_model.g.dart'; // Important: This should match your generated file

@HiveType(typeId: 0)
class Note {
  @HiveField(0)
  final String title;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final List<List<Map<String, double>>>? doodlePaths; // Convert Offset to Map

  @HiveField(4)
  final List<int>? doodleColors; // Convert Color to int

  // New fields for reminder functionality
  @HiveField(5)
  final bool hasReminder;

  @HiveField(6)
  final DateTime? reminderDateTime;

  @HiveField(7)
  final int? notificationId;

  Note({
    required this.title,
    required this.content,
    required this.createdAt,
    this.doodlePaths,
    this.doodleColors,
    this.hasReminder = false,
    this.reminderDateTime,
    this.notificationId,
  });

  // Convert Offset list to a storable format
  static List<Map<String, double>> encodeOffsets(List<Offset> offsets) {
    return offsets.map((offset) => {'dx': offset.dx, 'dy': offset.dy}).toList();
  }

  static List<Offset> decodeOffsets(List<Map<String, double>> encodedOffsets) {
    return encodedOffsets.map((map) => Offset(map['dx']!, map['dy']!)).toList();
  }

  void save() {}
}