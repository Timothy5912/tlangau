import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// If you add the `share_plus` package to pubspec.yaml you can uncomment
// this import and use Share.share(...) inside shareGroupLink() below to
// open the native share sheet instead of / in addition to copying the
// link to the clipboard.
// import 'package:share_plus/share_plus.dart';

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

  // The message currently being replied to (if any). Holds the raw
  // Firestore message data plus its doc id so we can attach a quoted
  // preview onto the next message that gets sent.
  String? _replyingToId;
  Map<String, dynamic>? _replyingToMessage;

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

  // Some groups may have been created back when the phone number was
  // stored with a "+91" prefix, others without it (depending on where
  // in the app the write happened). Comparing against a single format
  // silently returns zero matches if it doesn't line up — which is
  // what caused the "Make Announcement" group list to show blank on
  // some accounts/devices even though the groups existed. Instead we
  // match against every format we can reasonably expect.
  List<String> get possibleCreatorPhoneFormats {
    final raw = (_auth.currentUser?.phoneNumber ?? "").trim();
    final stripped =
        raw.startsWith("+91") ? raw.substring(3) : raw;
    final withPrefix =
        raw.startsWith("+91") ? raw : "+91$raw";

    final formats = <String>{
      if (raw.isNotEmpty) raw,
      if (stripped.isNotEmpty) stripped,
      if (withPrefix.isNotEmpty) withPrefix,
    };

    return formats.toList();
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
  // Reply To Message
  //====================================================

  void startReply(String messageId, Map<String, dynamic> message) {
    setState(() {
      _replyingToId = messageId;
      _replyingToMessage = message;
    });
  }

  void cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToMessage = null;
    });
  }

  //====================================================
  // Send Message
  //====================================================

  Future<void> sendMessage() async {
  final text = messageController.text.trim();

  if (text.isEmpty) return;

  final Map<String, dynamic> data = {
    "text": text,
    "sender": phoneNumber,
    "time": FieldValue.serverTimestamp(),
  };

  if (_replyingToId != null && _replyingToMessage != null) {
    data["replyToId"] = _replyingToId;
    data["replyToSender"] = _replyingToMessage!["sender"];
    data["replyToText"] = _replyingToMessage!["text"] ?? "";
  }

  await _firestore
      .collection("groups")
      .doc(widget.groupId)
      .collection("messages")
      .add(data);

  await _firestore
      .collection("groups")
      .doc(widget.groupId)
      .update({
    "lastMessage": text,
    "lastMessageTime": FieldValue.serverTimestamp(),
  });

  // Notify other group members
  try {
    final response = await http.post(
      Uri.parse("https://tlangau-notify.tlangau.workers.dev"),
      headers: {
        "Content-Type": "application/json",
        "x-app-secret": "Tlangau_2026_Notify_8P#x4Lm!Q9vR2zK",
      },
      body: jsonEncode({
        "groupId": widget.groupId,
        "senderPhone": phoneNumber,
        "text": text,
        "type": "message",
      }),
    );

    debugPrint(
      "Worker Response: ${response.statusCode} ${response.body}",
    );
  } catch (e) {
    debugPrint("Notification Error: $e");
  }

  messageController.clear();

  setTyping(false);

  cancelReply();

  if (mounted) {
    setState(() {});
  }
}
  //====================================================
  // Message Actions (Reply / Delete)
  //====================================================

  void showMessageActions({
    required String messageId,
    required Map<String, dynamic> message,
    required bool isMe,
    required bool isCreator,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text("Reply"),
                onTap: () {
                  Navigator.pop(context);
                  startReply(messageId, message);
                },
              ),
              if (isMe || isCreator)
                ListTile(
                  leading: const Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  title: const Text(
                    "Delete",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    confirmDeleteMessage(
                      messageId,
                      deletedByCreator: !isMe && isCreator,
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  //====================================================
  // Delete Message
  //====================================================
  //
  // Instead of hard-deleting the document (which would need every
  // message to carry its own doc id around and would lose the fact
  // that "something" was there), we mark the message as deleted and
  // keep a flag for who deleted it. The message bubble is then shown
  // as a small "This message was deleted" / "This message was deleted
  // by creator" placeholder to everyone in the chat.

  Future<void> deleteMessage(
    String messageId, {
    required bool deletedByCreator,
  }) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .collection("messages")
        .doc(messageId)
        .update({
      "deleted": true,
      "deletedByCreator": deletedByCreator,
      "text": "",
    });
  }

  void confirmDeleteMessage(
    String messageId, {
    required bool deletedByCreator,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Delete Message"),
          content: const Text(
            "This message will be deleted for everyone. Are you sure?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await deleteMessage(
                  messageId,
                  deletedByCreator: deletedByCreator,
                );
              },
              child: const Text(
                "Delete",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  //====================================================
  // Creator Functions — Announcements
  //====================================================

  Future<void> sendAnnouncementToGroups(
      String text, List<String> groupIds) async {
    final trimmed = text.trim();

    if (trimmed.isEmpty || groupIds.isEmpty) return;

    final batch = _firestore.batch();

    for (final gid in groupIds) {
      final groupRef = _firestore.collection("groups").doc(gid);
      final messageRef = groupRef.collection("messages").doc();

      batch.set(messageRef, {
        "text": trimmed,
        "sender": phoneNumber,
        "time": FieldValue.serverTimestamp(),
        "type": "announcement",
      });

      batch.update(groupRef, {
        "lastMessage": "📢 $trimmed",
        "lastMessageTime": FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Announcement sent to ${groupIds.length} group${groupIds.length == 1 ? '' : 's'}",
          ),
        ),
      );
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
  // Member Functions — Leave Group
  //====================================================

  Future<void> leaveGroup() async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "members": FieldValue.arrayRemove([phoneNumber]),
    });

    if (mounted) {
      Navigator.pop(context);
    }
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
      String name, String description, bool isPrivate) async {
    await _firestore
        .collection("groups")
        .doc(widget.groupId)
        .update({
      "groupName": name,
      "description": description,
      "isPrivate": isPrivate,
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
  // Group Invite Link (share-to-join)
  //====================================================
  //
  // NOTE: Replace the domain below with your actual hosting / dynamic
  // link domain, and make sure your app can handle incoming links of
  // this shape (e.g. via Firebase Dynamic Links, go_router deep links,
  // or a universal/app link) by reading the groupId and either adding
  // the opener straight to "members" or into "joinRequests" depending
  // on whether the group is open or approval-based.

  String get groupInviteLink =>
      "https://yourapp.com/join/${widget.groupId}";

  Future<void> shareGroupLink() async {
    final link = groupInviteLink;

    await Clipboard.setData(ClipboardData(text: link));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Group link copied to clipboard"),
        ),
      );
    }

    // If you add the `share_plus` package to pubspec.yaml, you can
    // open the native share sheet instead of (or in addition to) just
    // copying to the clipboard:
    //
    // await Share.share(
    //   'Join my group "${widget.groupName}" — $link',
    // );
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

    bool isPrivate = group["isPrivate"] ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                  const SizedBox(height: 16),

                  // Public / Private toggle -----------------------
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Group Type",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text("Public"),
                          selected: !isPrivate,
                          selectedColor: Colors.black,
                          labelStyle: TextStyle(
                            color: !isPrivate
                                ? Colors.white
                                : Colors.black,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              isPrivate = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text("Private"),
                          selected: isPrivate,
                          selectedColor: Colors.black,
                          labelStyle: TextStyle(
                            color: isPrivate
                                ? Colors.white
                                : Colors.black,
                          ),
                          onSelected: (_) {
                            setDialogState(() {
                              isPrivate = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPrivate
                        ? "Only invited users or approved requests can join."
                        : "Anyone with the group link can join instantly.",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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
                  onPressed: () {
                    Navigator.pop(context);
                    openMakeAnnouncement();
                  },
                  child: const Text(
                    "Make Announcement",
                    style: TextStyle(color: Color(0xFFB8860B)),
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

                    await updateGroup(newName, newDesc, isPrivate);

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
      },
    );
  }

  //====================================================
  // Make Announcement (creator only)
  //====================================================

  void openMakeAnnouncement() {
    final announcementController = TextEditingController();

    // Pre-select the group the user is currently in.
    final Set<String> selectedGroupIds = {widget.groupId};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Make Announcement",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: announcementController,
                      maxLines: 4,
                      autofocus: true,
                      style: const TextStyle(color: Colors.black),
                      cursorColor: Colors.black,
                      decoration: InputDecoration(
                        hintText: "Type an announcement",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.grey.shade400,
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Send to",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // List of groups the user created — pick any
                    // combination to broadcast this announcement to.
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 240,
                      ),
                      child: Builder(
                        builder: (context) {
                          final formats =
                              possibleCreatorPhoneFormats;

                          if (formats.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 20,
                              ),
                              child: Text(
                                "Could not read your phone number. Please re-login and try again.",
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: Colors.grey),
                              ),
                            );
                          }

                          return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>>(
                            stream: _firestore
                                .collection("groups")
                                .where(
                                  "createdBy",
                                  whereIn: formats,
                                )
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Text(
                                    "Couldn't load your groups.\n${snapshot.error}",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }

                              if (!snapshot.hasData) {
                                return const Padding(
                                  padding:
                                      EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Center(
                                    child:
                                        CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final groups = snapshot.data!.docs;

                              if (groups.isEmpty) {
                                return const Padding(
                                  padding:
                                      EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Text(
                                    "No groups found",
                                    style: TextStyle(
                                        color: Colors.grey),
                                  ),
                                );
                              }

                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: groups.length,
                                itemBuilder: (context, index) {
                                  final doc = groups[index];
                                  final data = doc.data();

                                  final name =
                                      data["groupName"] ??
                                          data["name"] ??
                                          "Untitled (${doc.id})";

                                  final checked =
                                      selectedGroupIds
                                          .contains(doc.id);

                                  return CheckboxListTile(
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity
                                            .leading,
                                    activeColor: Colors.black,
                                    checkColor: Colors.white,
                                    value: checked,
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.black,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          selectedGroupIds
                                              .add(doc.id);
                                        } else {
                                          selectedGroupIds
                                              .remove(doc.id);
                                        }
                                      });
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final text = announcementController.text.trim();

                    if (text.isEmpty ||
                        selectedGroupIds.isEmpty) {
                      return;
                    }

                    Navigator.pop(context);

                    await sendAnnouncementToGroups(
                      text,
                      selectedGroupIds.toList(),
                    );
                  },
                  child: const Text(
                    "Post",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  //====================================================
  // Group Info (view-only, for members)
  //====================================================

  void openGroupInfo(Map<String, dynamic> group) {
    final name = group["groupName"] ?? widget.groupName;
    final description = group["description"] ?? "";
    final bool isPrivate = group["isPrivate"] ?? false;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Group Info"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Group Name",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                "Description",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description.isNotEmpty
                    ? description
                    : "No description",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                "Group Type",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isPrivate ? "Private" : "Public",
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                "Close",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        );
      },
    );
  }

  //====================================================
  // Leave Group Confirmation
  //====================================================

  void confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text("Leave Group"),
          content: const Text(
            "Are you sure you want to leave this group?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await leaveGroup();
              },
              child: const Text(
                "Leave",
                style: TextStyle(color: Colors.red),
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
  // Invite Users (search by username / phone + share link)
  //====================================================

  void openInviteUsers() {
    final searchController = TextEditingController();
    String searchQuery = "";

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
        // StatefulBuilder gives this sheet its own local setState so the
        // search box can filter the list live without touching the rest
        // of the ChatScreen state.
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: StreamBuilder<
                  QuerySnapshot<Map<String, dynamic>>>(
                stream:
                    _firestore.collection("users").snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final query = searchQuery.trim().toLowerCase();

                  final users = snapshot.data!.docs.where((doc) {
                    if (doc.id == phoneNumber) return false;

                    if (query.isEmpty) return true;

                    final data = doc.data();

                    final username = (data["username"] ??
                            data["name"] ??
                            "")
                        .toString()
                        .toLowerCase();

                    final phone = doc.id.toLowerCase();

                    return username.contains(query) ||
                        phone.contains(query);
                  }).toList();

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

                        // Share group link ------------------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(
                                  color: Colors.black,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(30),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onPressed: shareGroupLink,
                              icon: const Icon(Icons.link),
                              label: const Text(
                                "Share Group Link",
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        // Search by username / phone --------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          child: TextField(
                            controller: searchController,
                            onChanged: (value) {
                              setModalState(() {
                                searchQuery = value;
                              });
                            },
                            decoration: InputDecoration(
                              hintText:
                                  "Search by username or phone number",
                              prefixIcon:
                                  const Icon(Icons.search),
                              suffixIcon: searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                      ),
                                      onPressed: () {
                                        searchController.clear();
                                        setModalState(() {
                                          searchQuery = "";
                                        });
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                vertical: 0,
                                horizontal: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        if (users.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 30,
                            ),
                            child: Text(
                              "No matching users",
                              style:
                                  TextStyle(color: Colors.grey),
                            ),
                          ),

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
                                      ScaffoldMessenger.of(
                                              context)
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

                    if (value == "announcement") {
                      openMakeAnnouncement();
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

                    PopupMenuItem(
                      value: "announcement",
                      child: Text(
                        "Make Announcement",
                      ),
                    ),
                  ],
                )
              else
                PopupMenuButton<String>(
                  onSelected: (value) {

                    if (value == "info") {
                      openGroupInfo(group);
                    }

                    if (value == "leave") {
                      confirmLeaveGroup();
                    }
                  },
                  itemBuilder: (_) => const [

                    PopupMenuItem(
                      value: "info",
                      child: Text(
                        "Group Info",
                      ),
                    ),

                    PopupMenuItem(
                      value: "leave",
                      child: Text(
                        "Leave Group",
                        style: TextStyle(color: Colors.red),
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
                                                    final msgDoc = messages[index];
                        final msg = msgDoc.data();

                        // Announcement banner ----------------------
                        if (msg["type"] == "announcement") {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.campaign,
                                    color: Colors.amber.shade800,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Announcement",
                                          style: TextStyle(
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors
                                                .amber.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          msg["text"] ?? "",
                                          style: const TextStyle(
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          formatTime(
                                            msg["time"]
                                                as Timestamp?,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors
                                                .amber.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final bool isMe =
                            msg["sender"] == phoneNumber;

                        // Deleted message placeholder ----------------
                        if (msg["deleted"] == true) {
                          final bool deletedByCreator =
                              msg["deletedByCreator"] == true;

                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 5,
                            ),
                            child: Row(
                              mainAxisAlignment: isMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius:
                                        BorderRadius.circular(
                                            14),
                                    border: Border.all(
                                      color:
                                          Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize:
                                        MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.block,
                                        size: 14,
                                        color:
                                            Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        deletedByCreator
                                            ? "This message was deleted by creator"
                                            : "This message was deleted",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontStyle:
                                              FontStyle.italic,
                                          color: Colors
                                              .grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

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
                                    child: GestureDetector(
                                      onLongPress: () =>
                                          showMessageActions(
                                        messageId: msgDoc.id,
                                        message: msg,
                                        isMe: isMe,
                                        isCreator: isCreator,
                                      ),
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

                                            if ((msg["replyToText"] ??
                                                    "")
                                                .toString()
                                                .isNotEmpty)
                                              FutureBuilder<
                                                  Map<String,
                                                      dynamic>>(
                                                future: getUser(
                                                  msg["replyToSender"] ??
                                                      "",
                                                ),
                                                builder: (context,
                                                    replySnap) {
                                                  final replyUser =
                                                      replySnap
                                                              .data ??
                                                          {};

                                                  final replyName =
                                                      msg["replyToSender"] ==
                                                              phoneNumber
                                                          ? "You"
                                                          : (replyUser[
                                                                  "username"] ??
                                                              replyUser[
                                                                  "name"] ??
                                                              "User");

                                                  return Container(
                                                    margin:
                                                        const EdgeInsets
                                                            .only(
                                                      bottom: 6,
                                                    ),
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                    decoration:
                                                        BoxDecoration(
                                                      color: isMe
                                                          ? Colors
                                                              .white24
                                                          : Colors
                                                              .black
                                                              .withOpacity(
                                                                  0.06),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(
                                                                  8),
                                                      border: Border(
                                                        left:
                                                            BorderSide(
                                                          color: isMe
                                                              ? Colors
                                                                  .white70
                                                              : Colors
                                                                  .blue,
                                                          width: 3,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          replyName,
                                                          style:
                                                              TextStyle(
                                                            fontSize:
                                                                11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold,
                                                            color: isMe
                                                                ? Colors
                                                                    .white70
                                                                : Colors
                                                                    .blue,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          msg["replyToText"] ??
                                                              "",
                                                          maxLines: 2,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          style:
                                                              TextStyle(
                                                            fontSize:
                                                                12,
                                                            color: isMe
                                                                ? Colors
                                                                    .white70
                                                                : Colors
                                                                    .black54,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),

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
              // REPLY PREVIEW
              //====================================

              if (_replyingToId != null && _replyingToMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 36,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FutureBuilder<
                            Map<String, dynamic>>(
                          future: getUser(
                            _replyingToMessage!["sender"] ?? "",
                          ),
                          builder: (context, snap) {
                            final u = snap.data ?? {};

                            final name = _replyingToMessage![
                                        "sender"] ==
                                    phoneNumber
                                ? "You"
                                : (u["username"] ??
                                    u["name"] ??
                                    "User");

                            return Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Replying to $name",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _replyingToMessage!["text"] ??
                                      "",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: cancelReply,
                      ),
                    ],
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