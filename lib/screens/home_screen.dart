import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'user_setting.dart';
import 'create_group_screen.dart';
import 'chat_screen.dart'; // 🔥 ADDED

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _searchController = TextEditingController();

  String get phoneNumber {
  String phone = _auth.currentUser?.phoneNumber ?? "";

  if (phone.startsWith("+91")) {
    phone = phone.substring(3);
  }

  return phone;
}

  Stream<DocumentSnapshot<Map<String, dynamic>>> getUser() {
    return _firestore.collection("users").doc(phoneNumber).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getGroups() {
    return _firestore.collection("groups").snapshots();
  }

  Future<void> joinGroup(String groupId) async {
    await _firestore.collection("groups").doc(groupId).update({
      "members": FieldValue.arrayUnion([phoneNumber]),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Joined Group")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // 🖤 APP BAR
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: getUser(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text(
                "Tlangau",
                style: TextStyle(color: Colors.white),
              );
            }

            final user = snapshot.data!.data()!;

            return Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    user["name"] ?? "",
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      // 🔥 BODY
      body: Column(
        children: [

          // 🔍 SEARCH
          Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.black54),
                  hintText: "Search or Join Group",
                ),
              ),
            ),
          ),

          // 📌 GROUP LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: getGroups(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final search = _searchController.text.toLowerCase();

                final groups = snapshot.data!.docs.where((doc) {
                  final name =
                      (doc["name"] ?? "").toString().toLowerCase();
                  return name.contains(search);
                }).toList();

                if (groups.isEmpty) {
                  return const Center(
                    child: Text(
                      "No Groups Found",
                      style: TextStyle(fontSize: 18),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index].data();
                    final groupId = groups[index].id;

                    final members =
                        List<String>.from(group["members"] ?? []);

                    final alreadyJoined =
                        members.contains(phoneNumber);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
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

                        trailing: alreadyJoined
                            ? const Text(
                                "Joined",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  joinGroup(groupId);
                                },
                                child: const Text("Join"),
                              ),

                        // 🔥 CLICK TO OPEN CHAT
                        onTap: () {
                          if (!alreadyJoined) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text("Join group first"),
                              ),
                            );
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                groupId: groupId,
                                groupName:
                                    group["name"] ?? "Group",
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // ➕ CREATE GROUP
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateGroupScreen(
                phoneNumber: phoneNumber,
              ),
            ),
          );
        },
        child: const Icon(Icons.group_add),
      ),

      // ⚙️ SETTINGS
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UserSettingScreen(),
              ),
            );
          } else {
            setState(() {
              _currentIndex = 0;
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