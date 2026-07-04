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
  // Creator Functions — Members
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

  //====================================================
  // Creator Functions — Group Settings
  //====================================================

  Future<void> deleteGroup() async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .delete();

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> updateGroup(
      String name, String description) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "groupName": name,
      "description": description,
    });
  }

  //====================================================
  // Creator Functions — Join Requests
  //====================================================

  Future<void> acceptJoinRequest(String phone) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "members": FieldValue.arrayUnion([phone]),
      "joinRequests": FieldValue.arrayRemove([phone]),
    });
  }

  Future<void> rejectJoinRequest(String phone) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "joinRequests": FieldValue.arrayRemove([phone]),
    });
  }

  //====================================================
  // Creator Functions — Invite Users
  //====================================================

  Future<void> inviteUser(String phone) async {
    await _firestore
        .collection("users")
        .doc(phone)
        .collection("invites")
        .add({
      "groupId": widget.groupId,
      "groupName": widget.groupName,
      "invitedBy": phoneNumber,
      "time": FieldValue.serverTimestamp(),
    });
  }
    //====================================================
  // Member List (Manage Members)
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
                  "Manage Members",
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
  // Manage Group (edit name / description / delete)
  //====================================================

  void openManageGroup(Map<String, dynamic> group) {
    final nameController = TextEditingController(
      text: group["groupName"] ?? widget.groupName,
    );
    final descController = TextEditingController(
      text: group["description"] ?? "",
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Manage Group"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Group Name",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Group Description",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text("Delete Group"),
                      content: const Text(
                        "This will permanently delete the group for everyone. Are you sure?",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, false),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, true),
                          child: const Text(
                            "Delete",
                            style:
                                TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  },
                );

                if (confirm == true) {
                  await deleteGroup();
                }
              },
              child: const Text(
                "Delete Group",
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
              ),
              onPressed: () async {
                final newName = nameController.text.trim();
                final newDesc = descController.text.trim();

                if (newName.isEmpty) return;

                await updateGroup(newName, newDesc);

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text(
                "Save",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  //====================================================
  // Join Requests
  //====================================================

  void openJoinRequests() {
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
          child: StreamBuilder<
              DocumentSnapshot<Map<String, dynamic>>>(
            stream: getGroup(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() ?? {};

              final requests = List<String>.from(
                data["joinRequests"] ?? [],
              );

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Join Requests",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    if (requests.isEmpty)
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 30),
                        child: Text(
                          "No pending join requests",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),

                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          final phone = requests[index];

                          return FutureBuilder<
                              Map<String, dynamic>>(
                            future: getUser(phone),
                            builder: (context, snap) {
                              final user = snap.data ?? {};

                              final username =
                                  user["username"] ??
                                      user["name"] ??
                                      phone;

                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(username),
                                subtitle: Text(phone),
                                trailing: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                      ),
                                      onPressed: () async {
                                        await acceptJoinRequest(
                                            phone);
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        await rejectJoinRequest(
                                            phone);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  //====================================================
  // Invite Users
  //====================================================

  void openInviteUsers() {
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
          child: StreamBuilder<
              QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore.collection("users").snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final users = snapshot.data!.docs
                  .where((doc) => doc.id != phoneNumber)
                  .toList();

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Invite Users",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),

                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final doc = users[index];
                          final data = doc.data();

                          final username =
                              data["username"] ??
                                  data["name"] ??
                                  doc.id;

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(username),
                            subtitle: Text(doc.id),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Colors.black,
                              ),
                              onPressed: () async {
                                await inviteUser(doc.id);

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Invite sent to $username",
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              );
            },
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
              // NOTE: group/member icon removed from app bar per request.
              // Member management now lives only inside the creator's
              // three-dot menu below.

              if (isCreator)
                PopupMenuButton<String>(
                  onSelected: (value) {

                    if (value == "members") {
                      openMemberList(
                        members: members,
                        isCreator: true,
                        creator: creator,
                      );
                    }

                    if (value == "group") {
                      openManageGroup(group);
                    }

                    if (value == "requests") {
                      openJoinRequests();
                    }

                    if (value == "invite") {
                      openInviteUsers();
                    }
                  },
                  itemBuilder: (_) => const [

                    PopupMenuItem(
                      value: "members",
                      child: Text(
                        "Manage Members",
                      ),
                    ),

                    PopupMenuItem(
                      value: "group",
                      child: Text(
                        "Manage Group",
                      ),
                    ),

                    PopupMenuItem(
                      value: "requests",
                      child: Text(
                        "Join Requests",
                      ),
                    ),

                    PopupMenuItem(
                      value: "invite",
                      child: Text(
                        "Invite Users",
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