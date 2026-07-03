import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  //====================================================
  // Firebase
  //====================================================

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  //====================================================
  // Controllers
  //====================================================

  final TextEditingController messageController =
      TextEditingController();

  Timer? typingTimer;

  //====================================================
  // Cache
  //====================================================

  final Map<String, Map<String, dynamic>> _userCache = {};

  //====================================================
  // Current User Phone
  //====================================================

  String get phoneNumber {
    String phone = _auth.currentUser?.phoneNumber ?? "";

    if (phone.startsWith("+91")) {
      phone = phone.substring(3);
    }

    return phone;
  }

  //====================================================
  // Lifecycle
  //====================================================

  @override
  void initState() {
    super.initState();

    setTyping(false);
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    setTyping(false);
    messageController.dispose();
    super.dispose();
  }

  //====================================================
  // Streams
  //====================================================

  Stream<DocumentSnapshot<Map<String, dynamic>>> getGroup() {
    return _firestore
        .collection("groups")
        .doc(widget.groupId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getMessages() {
    return _firestore
        .collection("groups")
        .doc(widget.groupId)
        .collection("messages")
        .orderBy(
          "time",
          descending: true,
        )
        .snapshots();
  }

  //====================================================
  // Load User Information
  //====================================================

  Future<Map<String, dynamic>> getUser(
      String phone) async {
    if (_userCache.containsKey(phone)) {
      return _userCache[phone]!;
    }

    final doc = await _firestore
        .collection("users")
        .doc(phone)
        .get();

    final data = doc.data() ?? {};

    _userCache[phone] = data;

    return data;
  }

  //====================================================
  // Typing Indicator
  //====================================================

  Future<void> setTyping(bool value) async {
    try {
      await _firestore
          .collection("users")
          .doc(phoneNumber)
          .update({
        "isTyping": value,
        "typingIn": value ? widget.groupId : "",
      });
    } catch (_) {}
  }

  void onTyping(String value) {
    setTyping(value.trim().isNotEmpty);

    typingTimer?.cancel();

    typingTimer = Timer(
      const Duration(seconds: 2),
      () {
        setTyping(false);
      },
    );
  }

  //====================================================
  // Send Message
  //====================================================

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    if (text.isEmpty) return;

    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .collection("messages")
        .add({
      "text": text,
      "sender": phoneNumber,
      "time": FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "lastMessage": text,
      "lastMessageTime":
          FieldValue.serverTimestamp(),
    });

    messageController.clear();

    setTyping(false);

    if (mounted) {
      setState(() {});
    }
  }

  //====================================================
  // Creator Functions
  //====================================================

  Future<void> removeMember(
      String member) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "members":
          FieldValue.arrayRemove([member]),
    });
  }

  Future<void> deleteGroup() async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .delete();

    if (mounted) {
      Navigator.pop(context);
    }
  }
    //====================================================
  // Member List
  //====================================================

  void openMemberList({
    required List<String> members,
    required bool isCreator,
    required String creator,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                const Text(
                  "Group Members",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {

                      final phone = members[index];

                      return FutureBuilder<
                          Map<String, dynamic>>(
                        future: getUser(phone),
                        builder: (context, snapshot) {

                          final user =
                              snapshot.data ?? {};

                          final username =
                              user["username"] ??
                              user["name"] ??
                              phone;

                          final profile =
                              user["photoUrl"] ?? "";

                          final bool creatorMember =
                              phone == creator;

                          return ListTile(

                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  profile.isNotEmpty
                                      ? NetworkImage(
                                          profile,
                                        )
                                      : null,
                              child: profile.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                    )
                                  : null,
                            ),

                            title: Row(
                              children: [

                                Expanded(
                                  child: Text(
                                    username,
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),

                                if (creatorMember)
                                  Container(
                                    padding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration:
                                        BoxDecoration(
                                      color:
                                          Colors.green,
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                                  20),
                                    ),
                                    child: const Text(
                                      "Creator",
                                      style:
                                          TextStyle(
                                        color:
                                            Colors.white,
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            subtitle: Text(phone),

                            trailing:
                                isCreator &&
                                        !creatorMember
                                    ? IconButton(
                                        icon:
                                            const Icon(
                                          Icons
                                              .remove_circle,
                                          color:
                                              Colors.red,
                                        ),
                                        onPressed:
                                            () async {

                                          Navigator.pop(
                                              context);

                                          await removeMember(
                                            phone,
                                          );
                                        },
                                      )
                                    : null,
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  //====================================================
  // Time Formatter
  //====================================================

  String formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "";

    final dt = timestamp.toDate();

    int hour = dt.hour;

    String ampm = "AM";

    if (hour >= 12) {
      ampm = "PM";
    }

    hour = hour % 12;

    if (hour == 0) {
      hour = 12;
    }

    final minute = dt.minute
        .toString()
        .padLeft(2, '0');

    return "$hour:$minute $ampm";
  }
    //====================================================
  // BUILD
  //====================================================

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<
        DocumentSnapshot<Map<String, dynamic>>>(
      stream: getGroup(),
      builder: (context, snapshot) {
        if (!snapshot.hasData ||
            !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final group = snapshot.data!.data()!;

        final List<String> members =
            List<String>.from(
          group["members"] ?? [],
        );

        final String creator =
            group["createdBy"] ?? "";

        final bool isCreator =
            creator == phoneNumber;

        return Scaffold(
          backgroundColor: Colors.white,

          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,

            title: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [

                Text(
                  widget.groupName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),

                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection("users")
                      .where(
                        "typingIn",
                        isEqualTo:
                            widget.groupId,
                      )
                      .where(
                        "isTyping",
                        isEqualTo: true,
                      )
                      .snapshots(),
                  builder:
                      (context, typingSnap) {

                    if (!typingSnap.hasData) {
                      return Text(
                        "${members.length} members",
                        style:
                            const TextStyle(
                          fontSize: 11,
                        ),
                      );
                    }

                    final docs =
                        typingSnap.data!.docs;

                    docs.removeWhere(
                      (doc) =>
                          doc.id ==
                          phoneNumber,
                    );

                    if (docs.isEmpty) {
                      return Text(
                        "${members.length} members",
                        style:
                            const TextStyle(
                          fontSize: 11,
                        ),
                      );
                    }

                    final user =
                        docs.first.data()
                            as Map<String,
                                dynamic>;

                    return Text(
                      "${user["username"] ?? user["name"]} is typing...",
                      style:
                          const TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    );
                  },
                ),
              ],
            ),

            actions: [

              IconButton(
                icon: const Icon(
                  Icons.group,
                ),
                tooltip: "View Members",
                onPressed: () {
                  openMemberList(
                    members: members,
                    isCreator: isCreator,
                    creator: creator,
                  );
                },
              ),

              if (isCreator)
                PopupMenuButton<String>(
                  onSelected: (value) {

                    if (value ==
                        "manage") {
                      openMemberList(
                        members: members,
                        isCreator: true,
                        creator: creator,
                      );
                    }

                    if (value ==
                        "delete") {
                      deleteGroup();
                    }
                  },
                  itemBuilder: (_) => const [

                    PopupMenuItem(
                      value: "manage",
                      child: Text(
                        "Manage Members",
                      ),
                    ),

                    PopupMenuItem(
                      value: "delete",
                      child: Text(
                        "Delete Group",
                      ),
                    ),
                  ],
                ),
            ],
          ),

          body: Column(
            children: [

              //====================================
              // MESSAGE LIST
              //====================================

              Expanded(
                child:
                    StreamBuilder<QuerySnapshot<
                        Map<String, dynamic>>>(
                  stream: getMessages(),
                  builder:
                      (context, snapshot) {

                    if (!snapshot.hasData) {
                      return const Center(
                        child:
                            CircularProgressIndicator(),
                      );
                    }

                    final messages =
                        snapshot.data!.docs;

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          "No messages yet.\nStart chatting 👋",
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      reverse: true,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      itemCount:
                          messages.length,
                      itemBuilder:
                          (context, index) {
                                                    final msg = messages[index].data();

                        final bool isMe =
                            msg["sender"] == phoneNumber;

                        return FutureBuilder<
                            Map<String, dynamic>>(
                          future: getUser(
                            msg["sender"],
                          ),
                          builder:
                              (context, userSnap) {

                            final user =
                                userSnap.data ?? {};

                            final username = isMe
                                ? "You"
                                : (user["username"] ??
                                    user["name"] ??
                                    "User");

                            final profile =
                                user["photoUrl"] ?? "";

                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                vertical: 5,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                mainAxisAlignment: isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                                children: [

                                  if (!isMe)
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage:
                                          profile.isNotEmpty
                                              ? NetworkImage(
                                                  profile,
                                                )
                                              : null,
                                      child:
                                          profile.isEmpty
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 18,
                                                )
                                              : null,
                                    ),

                                  if (!isMe)
                                    const SizedBox(
                                      width: 8,
                                    ),

                                  Flexible(
                                    child: Container(
                                      constraints:
                                          const BoxConstraints(
                                        maxWidth: 280,
                                      ),
                                      padding:
                                          const EdgeInsets.all(
                                              12),
                                      decoration:
                                          BoxDecoration(
                                        color: isMe
                                            ? Colors.black
                                            : Colors.grey
                                                .shade200,
                                        borderRadius:
                                            BorderRadius.only(
                                          topLeft:
                                              const Radius
                                                  .circular(
                                                  18),
                                          topRight:
                                              const Radius
                                                  .circular(
                                                  18),
                                          bottomLeft:
                                              Radius.circular(
                                                  isMe
                                                      ? 18
                                                      : 5),
                                          bottomRight:
                                              Radius.circular(
                                                  isMe
                                                      ? 5
                                                      : 18),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [

                                          Text(
                                            username,
                                            style:
                                                TextStyle(
                                              fontWeight:
                                                  FontWeight
                                                      .bold,
                                              fontSize:
                                                  13,
                                              color: isMe
                                                  ? Colors
                                                      .white70
                                                  : Colors
                                                      .blue,
                                            ),
                                          ),

                                          const SizedBox(
                                            height: 5,
                                          ),

                                          Text(
                                            msg["text"] ??
                                                "",
                                            style:
                                                TextStyle(
                                              fontSize:
                                                  16,
                                              color: isMe
                                                  ? Colors
                                                      .white
                                                  : Colors
                                                      .black,
                                            ),
                                          ),

                                          const SizedBox(
                                            height: 8,
                                          ),

                                          Align(
                                            alignment:
                                                Alignment
                                                    .bottomRight,
                                            child: Text(
                                              formatTime(
                                                msg["time"]
                                                    as Timestamp?,
                                              ),
                                              style:
                                                  TextStyle(
                                                fontSize:
                                                    11,
                                                color: isMe
                                                    ? Colors
                                                        .white60
                                                    : Colors
                                                        .grey,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  if (isMe)
                                    const SizedBox(
                                      width: 8,
                                    ),

                                  if (isMe)
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage:
                                          profile.isNotEmpty
                                              ? NetworkImage(
                                                  profile,
                                                )
                                              : null,
                                      child:
                                          profile.isEmpty
                                              ? const Icon(
                                                  Icons.person,
                                                  size: 18,
                                                )
                                              : null,
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
                            //====================================
              // MESSAGE INPUT
              //====================================

              Container(
                padding: const EdgeInsets.fromLTRB(
                  8,
                  6,
                  8,
                  10,
                ),
                color: Colors.white,
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.end,
                    children: [

                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius:
                                BorderRadius.circular(30),
                          ),
                          child: Row(
                            children: [

                              IconButton(
                                onPressed: () {
                                  // Emoji picker (future)
                                },
                                icon: const Icon(
                                  Icons
                                      .emoji_emotions_outlined,
                                  color: Colors.grey,
                                ),
                              ),

                              Expanded(
                                child: TextField(
                                  controller:
                                      messageController,
                                  minLines: 1,
                                  maxLines: 5,
                                  onChanged: (value) {
                                    onTyping(value);

                                    if (mounted) {
                                      setState(() {});
                                    }
                                  },
                                  decoration:
                                      const InputDecoration(
                                    hintText:
                                        "Type a message",
                                    border:
                                        InputBorder.none,
                                  ),
                                ),
                              ),

                              PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.attach_file,
                                  color: Colors.grey,
                                ),
                                onSelected: (value) {
                                  switch (value) {
                                    case "gallery":
                                      break;

                                    case "document":
                                      break;

                                    case "location":
                                      break;
                                  }
                                },
                                itemBuilder: (_) => const [

                                  PopupMenuItem(
                                    value: "gallery",
                                    child: Row(
                                      children: [
                                        Icon(Icons.image),
                                        SizedBox(width: 10),
                                        Text("Gallery"),
                                      ],
                                    ),
                                  ),

                                  PopupMenuItem(
                                    value: "document",
                                    child: Row(
                                      children: [
                                        Icon(Icons.insert_drive_file),
                                        SizedBox(width: 10),
                                        Text("Document"),
                                      ],
                                    ),
                                  ),

                                  PopupMenuItem(
                                    value: "location",
                                    child: Row(
                                      children: [
                                        Icon(Icons.location_on),
                                        SizedBox(width: 10),
                                        Text("Location"),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.black,
                        child: IconButton(
                          onPressed: sendMessage,
                          icon: const Icon(
                            Icons.send,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}