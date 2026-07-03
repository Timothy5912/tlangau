import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseStorage _storage =
      FirebaseStorage.instance;

  final ImagePicker _picker =
      ImagePicker();

  final TextEditingController
      _groupNameController =
      TextEditingController();

  File? _groupImage;

  bool _loading = false;

  List<String> selectedMembers = [];

  @override
  void initState() {
    super.initState();

    selectedMembers.add(widget.phoneNumber);
  }

  Future<void> pickImage() async {

    final XFile? image =
        await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (image != null) {
      setState(() {
        _groupImage = File(image.path);
      });
    }
  }

  Future<String> uploadImage() async {

    if (_groupImage == null) {
      return "";
    }

    final ref = _storage
        .ref()
        .child("group_images")
        .child(
            "${DateTime.now().millisecondsSinceEpoch}.jpg");

    await ref.putFile(_groupImage!);

    return await ref.getDownloadURL();
  }

  Future<void> createGroup() async {

    if (_groupNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text("Enter group name"),
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {

      final imageUrl =
          await uploadImage();
                final doc =
          _firestore.collection("groups").doc();

      await doc.set({
        "name": _groupNameController.text.trim(),
        "groupImage": imageUrl,
        "admin": widget.phoneNumber,
        "members": selectedMembers,
        "createdAt": FieldValue.serverTimestamp(),
        "lastMessage": "",
        "lastMessageTime": "",
      });

      setState(() {
        _loading = false;
      });

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Create Group",
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: Column(
        children: [

          const SizedBox(height: 20),

          Center(
            child: GestureDetector(
              onTap: pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey.shade300,
                backgroundImage:
                    _groupImage != null
                        ? FileImage(_groupImage!)
                        : null,
                child: _groupImage == null
                    ? const Icon(
                        Icons.camera_alt,
                        size: 40,
                        color: Colors.black54,
                      )
                    : null,
              ),
            ),
          ),

          const SizedBox(height: 25),

          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: "Group Name",
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Select Members",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection("users")
                  .snapshots(),
              builder: (context, snapshot) {

                if (!snapshot.hasData) {
                  return const Center(
                    child:
                        CircularProgressIndicator(),
                  );
                }

                final users =
                    snapshot.data!.docs;

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {

                    final user =
                        users[index];

                    final phone =
                        user["phoneNumber"];

                    if (phone ==
                        widget.phoneNumber) {
                      return const SizedBox();
                    }

                    final selected =
                        selectedMembers.contains(
                            phone);

                    return CheckboxListTile(

                      value: selected,

                      title: Text(
                        user["name"] ?? "",
                      ),

                      subtitle: Text(
                        phone,
                      ),

                      secondary: CircleAvatar(
                        backgroundImage:
                            user["profileImage"] !=
                                        null &&
                                    user["profileImage"] !=
                                        ""
                                ? NetworkImage(
                                    user[
                                        "profileImage"],
                                  )
                                : null,
                        child: user["profileImage"] ==
                                    null ||
                                user["profileImage"] ==
                                    ""
                            ? const Icon(
                                Icons.person,
                              )
                            : null,
                      ),

                      onChanged: (value) {

                        setState(() {

                          if (value!) {
                            selectedMembers
                                .add(phone);
                          } else {
                            selectedMembers
                                .remove(phone);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
                    Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _loading ? null : createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Create Group",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }
}