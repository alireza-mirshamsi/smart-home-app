import 'package:flutter/material.dart';

class CustomCard extends StatelessWidget {
  final String name;
  final String imagePath;
  final VoidCallback onTap;

  CustomCard({required this.name, required this.imagePath, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 5,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(imagePath, height: 80, fit: BoxFit.cover),
            SizedBox(height: 10),
            Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
