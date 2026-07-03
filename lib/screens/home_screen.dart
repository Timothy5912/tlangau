import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_setting.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get phoneNumber => _auth.currentUser?.phoneNumber ?? "";

  Stream<DocumentSnapshot<Map<String, dynamic>>> getUser() {
    return _firestore
        .collection("users")
        .doc(phoneNumber)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getGroups() {
    return _firestore
        .collection("groups")
        .where("members", arrayContains: phoneNumber)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: getUser(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text(
                "Tlangau",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            }

            final user = snapshot.data!.data()!;

            return Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user["name"] ?? "",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: getGroups(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No Groups Yet",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          final groups = snapshot.data!.docs;

          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index].data();

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.black,
                    child: Icon(
                      Icons.groups,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    group["name"] ?? "Unnamed Group",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    group["lastMessage"] ?? "No messages yet",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        group["lastMessageTime"] ?? "",
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if ((group["unreadCount"] ?? 0) > 0)
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.green,
                          child: Text(
                            "${group["unreadCount"]}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    // Chat screen later
                  },
                ),
              );
            },
          );
        },
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Create Group coming soon"),
            ),
          );
        },
        child: const Icon(Icons.group_add),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,

        onTap: (index) {
          if (index == 0) {
            setState(() {
              _currentIndex = 0;
            });
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserSettingScreen(),
              ),
            ).then((_) {
              setState(() {
                _currentIndex = 0;
              });
            });
          }
        },

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
      ),
    );
  }
}