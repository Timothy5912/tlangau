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
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  File? _image;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
    Future<void> pickImage() async {
    final XFile? picked = await _picker.pickImage(
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
    if (_image == null) return "";

    try {
      final ref = _storage
          .ref()
          .child("profile_images")
          .child("${widget.phoneNumber}.jpg");

      await ref.putFile(_image!);
      return await ref.getDownloadURL();
    } catch (e) {
      return "";
    }
  }
    Future<void> saveProfile() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final imageUrl = await uploadImage();

      final data = {
        "phoneNumber": widget.phoneNumber,
        "name": name,
        "username": username,
        "updatedAt": FieldValue.serverTimestamp(),
      };

      // only add image if exists
      if (imageUrl.isNotEmpty) {
        data["profileImage"] = imageUrl;
      }

      await _firestore
          .collection("users")
          .doc(widget.phoneNumber)
          .set(data, SetOptions(merge: true));

      setState(() {
        _loading = false;
      });

      if (!mounted) return;

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
        SnackBar(content: Text(e.toString())),
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
          "Create Profile",
          style: TextStyle(color: Colors.white),
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
                  backgroundImage:
                      _image != null ? FileImage(_image!) : null,
                  child: _image == null
                      ? const Icon(Icons.camera_alt, size: 40)
                      : null,
                ),
              ),

              const SizedBox(height: 10),

              const Text("Tap to choose profile picture"),

              const SizedBox(height: 30),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _loading ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Continue",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}