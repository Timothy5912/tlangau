import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'user_setting.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final TextEditingController _searchController =
      TextEditingController();

  String get phoneNumber {
    String phone = _auth.currentUser?.phoneNumber ?? "";

    if (phone.startsWith("+91")) {
      phone = phone.substring(3);
    }

    return phone;
  }

  //====================================================
  // Push Notifications (message alerts + sound)
  //====================================================

  static const AndroidNotificationChannel _messageChannel =
      AndroidNotificationChannel(
    "messages_channel",
    "Messages",
    description: "Notifications for new group messages",
    importance: Importance.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound("images/notification_sound.mp3"),
  );

  Future<void> _setupPushNotifications() async {
    // Ask the user for permission (iOS requires this explicitly).
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Prepare local notifications so we can show a banner + sound
    // even while the app is open in the foreground.
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings =
        InitializationSettings(android: androidInit);

    await _localNotifications.initialize(initSettings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_messageChannel);

    // Save this device's token so the server knows where to send
    // pushes for this user. Refresh it whenever it changes.
    final token = await _messaging.getToken();

    if (token != null) {
      await _firestore.collection("users").doc(phoneNumber).update({
        "fcmToken": token,
      });
    }

    _messaging.onTokenRefresh.listen((newToken) {
      _firestore.collection("users").doc(phoneNumber).update({
        "fcmToken": newToken,
      });
    });

    // Foreground: the OS won't show a system banner for us, so we
    // show one ourselves (with sound) using local notifications.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;

      if (notification == null) return;

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: _messageChannel.sound,
          ),
        ),
      );
    });

    // Tapping a notification while the app is backgrounded opens the
    // relevant group chat.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final groupId = message.data["groupId"];
      final groupName = message.data["groupName"] ?? "Group";

      if (groupId != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getUser() {
    return _firestore
        .collection("users")
        .doc(phoneNumber)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getGroups() {
    return _firestore.collection("groups").snapshots();
  }

  //====================================================
  // Invites
  //====================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> getInvites() {
    return _firestore
        .collection("users")
        .doc(phoneNumber)
        .collection("invites")
        .orderBy("time", descending: true)
        .snapshots();
  }

  Future<Map<String, dynamic>> getUserByPhone(String phone) async {
    final doc = await _firestore.collection("users").doc(phone).get();
    return doc.data() ?? {};
  }

  Future<void> acceptInvite({
    required String inviteId,
    required String groupId,
  }) async {
    await _firestore.collection("groups").doc(groupId).update({
      "members": FieldValue.arrayUnion([phoneNumber]),
    });

    await _firestore
        .collection("users")
        .doc(phoneNumber)
        .collection("invites")
        .doc(inviteId)
        .delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Joined Group"),
      ),
    );
  }

  Future<void> ignoreInvite(String inviteId) async {
    await _firestore
        .collection("users")
        .doc(phoneNumber)
        .collection("invites")
        .doc(inviteId)
        .delete();
  }

  void openInvites() {
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
            stream: getInvites(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final invites = snapshot.data!.docs;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Invites",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    if (invites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 30,
                        ),
                        child: Text(
                          "No invites right now",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),

                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: invites.length,
                        itemBuilder: (context, index) {
                          final inviteDoc = invites[index];
                          final invite = inviteDoc.data();

                          final groupId = invite["groupId"] ?? "";
                          final groupName =
                              invite["groupName"] ?? "a group";
                          final invitedBy =
                              invite["invitedBy"] ?? "";

                          return FutureBuilder<
                              Map<String, dynamic>>(
                            future: getUserByPhone(invitedBy),
                            builder: (context, userSnap) {
                              final inviter = userSnap.data ?? {};

                              final inviterName =
                                  inviter["username"] ??
                                      inviter["name"] ??
                                      invitedBy;

                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.black,
                                  child: Icon(
                                    Icons.groups,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  "$inviterName invites you to join $groupName",
                                ),
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
                                        await acceptInvite(
                                          inviteId: inviteDoc.id,
                                          groupId: groupId,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cancel,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        await ignoreInvite(
                                          inviteDoc.id,
                                        );
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

  Future<void> joinGroup(String groupId) async {
    await _firestore.collection("groups").doc(groupId).update({
      "members": FieldValue.arrayUnion([phoneNumber]),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Joined Group"),
      ),
    );
  }

  Future<void> requestToJoin(String groupId) async {
    await _firestore.collection("groups").doc(groupId).update({
      "joinRequests": FieldValue.arrayUnion([phoneNumber]),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Join request sent"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: getUser(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Text(
                "Tlangau",
                style: TextStyle(
                  color: Colors.white,
                ),
              );
            }

            final user = snapshot.data!.data()!;

            return Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                  ),
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

        actions: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: getInvites(),
            builder: (context, snapshot) {
              final count = snapshot.data?.docs.length ?? 0;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                    ),
                    onPressed: openInvites,
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          "$count",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),

      body: Column(
        children: [
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
                onChanged: (value) {
                  setState(() {});
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  icon: Icon(
                    Icons.search,
                    color: Colors.black54,
                  ),
                  hintText: "Search or Join Group",
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: getGroups(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final search =
                    _searchController.text.toLowerCase();

                final groups = snapshot.data!.docs.where((doc) {
                  final name = (doc["name"] ?? "")
                      .toString()
                      .toLowerCase();

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
                        List<String>.from(
                            group["members"] ?? []);

                    final requests =
                        List<String>.from(
                            group["joinRequests"] ?? []);

                    final alreadyJoined =
                        members.contains(phoneNumber);

                    final requested =
                        requests.contains(phoneNumber);
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

                        subtitle: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              group["lastMessage"] ??
                                  "No messages yet",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              group["isPrivate"] == true
                                  ? "🔒 Private Group"
                                  : "🌍 Public Group",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    group["isPrivate"] == true
                                        ? Colors.red
                                        : Colors.green,
                              ),
                            ),
                          ],
                        ),

                        trailing: alreadyJoined
                            ? const Text(
                                "Joined",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              )
                            : group["isPrivate"] == true
                                ? requested
                                    ? const Text(
                                        "Requested",
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      )
                                    : ElevatedButton(
                                        style:
                                            ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange,
                                          foregroundColor:
                                              Colors.white,
                                        ),
                                        onPressed: () {
                                          requestToJoin(
                                              groupId);
                                        },
                                        child: const Text(
                                            "Request"),
                                      )
                                : ElevatedButton(
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Colors.black,
                                      foregroundColor:
                                          Colors.white,
                                    ),
                                    onPressed: () {
                                      joinGroup(groupId);
                                    },
                                    child:
                                        const Text("Join"),
                                  ),

                        onTap: () {
                          if (!alreadyJoined) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Join the group first or wait for approval.",
                                ),
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
                                    group["name"] ??
                                        "Group",
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

      // ⚙️ Bottom Navigation
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