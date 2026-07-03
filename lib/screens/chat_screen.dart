import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String phoneNumber;

  const ChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.phoneNumber,
  });

  @override
  State<ChatScreen> createState() =>
      _ChatScreenState();
}

class _ChatScreenState
    extends State<ChatScreen> {

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final TextEditingController
      _messageController =
      TextEditingController();

  final ScrollController
      _scrollController =
      ScrollController();

  Future<Map<String, dynamic>>
      getCurrentUser() async {

    final doc =
        await _firestore
            .collection("users")
            .doc(widget.phoneNumber)
            .get();

    return doc.data()!;
  }

  Future<void> sendMessage() async {

    final text =
        _messageController.text.trim();

    if (text.isEmpty) return;

    final user =
        await getCurrentUser();

    final messageRef = _firestore
        .collection("groups")
        .doc(widget.groupId)
        .collection("messages")
        .doc();

    await messageRef.set({

      "message": text,

      "senderName":
          user["name"],

      "senderPhone":
          widget.phoneNumber,

      "senderImage":
          user["profileImage"],

      "timestamp":
          FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({

      "lastMessage": text,

      "lastMessageTime":
          DateTime.now()
              .toString()
              .substring(11,16),

    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.white,

      appBar: AppBar(

        backgroundColor: Colors.black,

        title: Text(
          widget.groupName,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ),
            body: Column(
        children: [

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection("groups")
                  .doc(widget.groupId)
                  .collection("messages")
                  .orderBy("timestamp")
                  .snapshots(),
              builder: (context, snapshot) {

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (!snapshot.hasData ||
                    snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No messages yet.\nStart the conversation!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                WidgetsBinding.instance
                    .addPostFrameCallback((_) {

                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController
                          .position
                          .maxScrollExtent,
                    );
                  }

                });

                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.all(12),
                  itemCount: messages.length,

                  itemBuilder: (context, index) {

                    final msg =
                        messages[index];

                    final data =
                        msg.data()
                            as Map<String, dynamic>;

                    final bool isMe =
                        data["senderPhone"] ==
                            widget.phoneNumber;

                    return Align(

                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,

                      child: Container(

                        margin:
                            const EdgeInsets.only(
                          bottom: 12,
                        ),

                        constraints:
                            const BoxConstraints(
                          maxWidth: 300,
                        ),

                        padding:
                            const EdgeInsets.all(12),

                        decoration: BoxDecoration(

                          color: isMe
                              ? Colors.black
                              : Colors.grey.shade200,

                          borderRadius:
                              BorderRadius.circular(
                            15,
                          ),
                        ),

                        child: Column(

                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,

                          children: [

                            if (!isMe)
                              Row(
                                children: [

                                  CircleAvatar(
                                    radius: 15,

                                    backgroundImage:
                                        data["senderImage"] !=
                                                    null &&
                                                data["senderImage"] !=
                                                    ""
                                            ? NetworkImage(
                                                data[
                                                    "senderImage"],
                                              )
                                            : null,

                                    child:
                                        data["senderImage"] ==
                                                    null ||
                                                data["senderImage"] ==
                                                    ""
                                            ? const Icon(
                                                Icons.person,
                                                size: 16,
                                              )
                                            : null,
                                  ),

                                  const SizedBox(
                                      width: 8),

                                  Expanded(
                                    child: Text(
                                      data[
                                              "senderName"] ??
                                          "",
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                  ),

                                ],
                              ),

                            if (!isMe)
                              const SizedBox(height: 8),

                            Text(
                              data["message"] ?? "",
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : Colors.black,
                                fontSize: 16,
                              ),
                            ),

                            const SizedBox(height: 6),

                            Align(
                              alignment:
                                  Alignment.bottomRight,
                              child: Text(

                                data["timestamp"] == null
                                    ? ""
                                    : (data["timestamp"]
                                            as Timestamp)
                                        .toDate()
                                        .toString()
                                        .substring(11, 16),

                                style: TextStyle(
                                  color: isMe
                                      ? Colors.white70
                                      : Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ),

                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
                    Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Colors.grey,
                  width: 0.3,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization:
                          TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),

                  const SizedBox(width: 10),

                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.black,
                    child: IconButton(
                      icon: const Icon(
                        Icons.send,
                        color: Colors.white,
                      ),
                      onPressed: sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}