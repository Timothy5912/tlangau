import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CreateGroupScreen extends StatefulWidget {
  final String phoneNumber;

  const CreateGroupScreen({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<CreateGroupScreen> createState() =>
      _CreateGroupScreenState();
}

class _CreateGroupScreenState
    extends State<CreateGroupScreen> {
  final TextEditingController nameController =
      TextEditingController();

  final TextEditingController descController =
      TextEditingController();

  bool isPrivate = false;
  bool loading = false;

  @override
  void dispose() {
    nameController.dispose();
    descController.dispose();
    super.dispose();
  }

  //==========================
  // Normalize Phone Number
  //==========================

  String get phoneNumber {
    String phone = widget.phoneNumber;

    if (phone.startsWith("+91")) {
      phone = phone.substring(3);
    }

    return phone.trim();
  }

  //==========================
  // Invite Code
  //==========================

  String generateInviteCode() {
    const chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    final random = Random();

    return List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  //==========================
  // Create Group
  //==========================

  Future<void> createGroup() async {
    final name = nameController.text.trim();
    final description = descController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter group name"),
        ),
      );
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final groupRef =
          FirebaseFirestore.instance
              .collection("groups")
              .doc();

      final inviteCode =
          isPrivate ? generateInviteCode() : "";

      await groupRef.set({
        "groupId": groupRef.id,

        "name": name,

        "description": description,

        // Creator phone number
        "createdBy": phoneNumber,

        // Members
        "members": [
          phoneNumber,
        ],

        "isPrivate": isPrivate,

        "inviteCode": inviteCode,

        "createdAt":
            FieldValue.serverTimestamp(),

        "lastMessage": "",

        "lastMessageTime":
            FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    }

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  //==========================
  // UI
  //==========================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Create Group"),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Group Name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Description",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SwitchListTile(
              value: isPrivate,
              title: const Text("Private Group"),
              subtitle: const Text(
                "Members need an invite code",
              ),
              onChanged: (value) {
                setState(() {
                  isPrivate = value;
                });
              },
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed:
                    loading ? null : createGroup,
                child: loading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Text(
                        "Create Group",
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}