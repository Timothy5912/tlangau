import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'welcome_screen.dart';
import 'profile_edit_screen.dart';
import 'home_screen.dart';

class UserSettingScreen extends StatelessWidget {
  const UserSettingScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
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
              child: Icon(Icons.person),
            ),
            title: const Text(
              "Profile",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text("View and edit your profile"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileEditScreen(),
                ),
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
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

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.groups),
            label: "Groups",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const HomeScreen(),
              ),
            );
          }
        },
      ),
    );
  }
}