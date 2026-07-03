import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'signup_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _generateOtp() async {
    final String phone = _phoneController.text.trim(); // 10 digits only

    if (phone.isEmpty || phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter valid 10-digit number")),
      );
      return;
    }

    setState(() => _isLoading = true);

    await _auth.verifyPhoneNumber(
      // +91 is used ONLY for Firebase authentication
      phoneNumber: "+91$phone",

      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "OTP failed")),
        );
      },

      codeSent: (String verificationId, int? resendToken) {
        setState(() => _isLoading = false);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SignupScreen(
              verificationId: verificationId,
              // Pass ONLY the 10-digit number
              phoneNumber: phone,
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        setState(() => _isLoading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 56,
              color: Colors.black,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Text(
                "Tlangau",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ),

            const SizedBox(height: 40),

            const Text(
              "Enter Phone Number",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  prefixText: "+91 ",
                  border: OutlineInputBorder(),
                  hintText: "Enter phone number",
                ),
              ),
            ),

            ElevatedButton(
              onPressed: _isLoading ? null : _generateOtp,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Generate OTP"),
            ),
          ],
        ),
      ),
    );
  }
}