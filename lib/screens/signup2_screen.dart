import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'home_screen.dart';

class CreateProfileScreen extends StatefulWidget {
  final String phoneNumber;

  const CreateProfileScreen({
    super.key,
    required this.phoneNumber,
  });

  @override
  State<CreateProfileScreen> createState() =>
      _CreateProfileScreenState();
}

class _CreateProfileScreenState
    extends State<CreateProfileScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseStorage _storage =
      FirebaseStorage.instance;

  final ImagePicker _picker =
      ImagePicker();

  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _usernameController =
      TextEditingController();

  File? _image;

  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final XFile? picked =
        await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (picked != null) {
      setState(() {
        _image = File(picked.path);
      });
    }
  }

  Future<String> uploadImage() async {
    if (_image == null) {
      return "";
    }

    final ref = _storage
        .ref()
        .child("profile_images")
        .child("${widget.phoneNumber}.jpg");

    await ref.putFile(_image!);

    return await ref.getDownloadURL();
  }

  Future<void> saveProfile() async {
    final name =
        _nameController.text.trim();

    final username =
        _usernameController.text.trim();

    if (name.isEmpty ||
        username.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            "Please fill all fields.",
          ),
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
                await _firestore
          .collection("users")
          .doc(widget.phoneNumber)
          .update({
        "name": name,
        "username": username,
        "profileImage": imageUrl,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      setState(() {
        _loading = false;
      });

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        ),
        (route) => false,
      );
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
        elevation: 0,
        title: const Text(
          "Create Profile",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            children: [

              const SizedBox(height: 20),

              GestureDetector(
                onTap: pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: _image != null
                      ? FileImage(_image!)
                      : null,
                  child: _image == null
                      ? const Icon(
                          Icons.camera_alt,
                          size: 40,
                          color: Colors.black54,
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                "Tap to choose profile picture",
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 35),

              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: "Username",
                  prefixIcon: const Icon(Icons.alternate_email),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed:
                      _loading ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                    ),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                      : const Text(
                          "Continue",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                ),
              ),
                            const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}