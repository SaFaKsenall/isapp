import 'package:flutter/material.dart';


class WIPPage extends StatelessWidget {
  final String title;
  final String message;
  
  const WIPPage({
    super.key, 
    this.title = 'Yapım Aşamasında',
    this.message = 'Bu sayfa şu anda geliştirme aşamasındadır. Yakında hizmetinizde olacaktır.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.construction,
                size: 80.0,
                color: Colors.orange,
              ),
              const SizedBox(height: 20.0),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16.0),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16.0,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30.0),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}