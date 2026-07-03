import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'welcome_screen.dart';

class UserSettingScreen extends StatelessWidget {
  const UserSettingScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomeScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.black,
              child: Icon(
                Icons.person,
                color: Colors.white,
              ),
            ),
            title: const Text(
              "Profile",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text("View and edit your profile"),
            onTap: () {
              // We'll connect Profile page later.
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(
              Icons.logout,
              color: Colors.red,
            ),
            title: const Text(
              "Logout",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}