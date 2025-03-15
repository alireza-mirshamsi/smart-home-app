import 'package:flutter/material.dart';

class ItemListTile extends StatelessWidget {
  final String itemName;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const ItemListTile({
    required this.itemName,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5.0,
        horizontal: 8.0,
      ), // فاصله از اطراف
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, // پس‌زمینه سفید
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2), // سایه ملایم
              spreadRadius: 1,
              blurRadius: 3,
              offset: Offset(0, 2), // جهت سایه
            ),
          ],
        ),
        child: ListTile(
          title: Text(itemName),
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min, // محدود کردن اندازه Row
            children: [
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red), // آیکون حذف
                onPressed: onDelete,
              ),
              Icon(
                Icons.chevron_right, // آیکون chevron right
                color: Colors.grey, // رنگ آیکون
              ),
            ],
          ),
        ),
      ),
    );
  }
}
