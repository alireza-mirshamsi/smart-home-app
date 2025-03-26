import 'package:flutter/material.dart';
import 'package:smart_home_app/Core/Model/shedule_model.dart';

class ScheduleSettings extends StatelessWidget {
  final List<dynamic> smartDevices;
  final Map<int, ScheduleModel> relaySchedules;
  final Function(int) onScheduleTap;

  const ScheduleSettings({
    super.key,
    required this.smartDevices,
    required this.relaySchedules,
    required this.onScheduleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "تنظیم زمان‌بندی",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...smartDevices.map((device) {
              int relayNumber = smartDevices.indexOf(device) + 1;
              relaySchedules[relayNumber] ??= ScheduleModel();
              return GestureDetector(
                onTap: () => onScheduleTap(relayNumber),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        device[0],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Icon(Icons.schedule, color: Colors.blueGrey),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
