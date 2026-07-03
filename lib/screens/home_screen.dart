import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final String phoneNumber;

  _HomeScreenState() : phoneNumber = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args =
        ModalRoute.of(context)?.settings.arguments;

    if (args is String && args.isNotEmpty) {
      // phone number passed from CreateProfileScreen
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> getUser() {
    final routeArgs =
        ModalRoute.of(context)?.settings.arguments;

    String number = "";

    if (routeArgs is String) {
      number = routeArgs;
    }

    return FirebaseFirestore.instance
        .collection("users")
        .doc(number)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getGroups() {
    final routeArgs =
        ModalRoute.of(context)?.settings.arguments;

    String number = "";

    if (routeArgs is String) {
      number = routeArgs;
    }

    return FirebaseFirestore.instance
        .collection("groups")
        .where(
          "members",
          arrayContains: number,
        )
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,

        title: StreamBuilder<
            DocumentSnapshot<Map<String, dynamic>>>(
          stream: getUser(),

          builder: (context, snapshot) {

            if (!snapshot.hasData ||
                !snapshot.data!.exists) {
              return const Text(
                "Loading...",
                style: TextStyle(
                  color: Colors.white,
                ),
              );
            }

            final user = snapshot.data!.data()!;

            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage:
                      user["profileImage"] != null &&
                              user["profileImage"] != ""
                          ? NetworkImage(
                              user["profileImage"],
                            )
                          : null,
                  child:
                      user["profileImage"] == null ||
                              user["profileImage"] == ""
                          ? const Icon(Icons.person)
                          : null,
                ),

                const SizedBox(width: 12),

                Text(
                  user["name"] ?? "",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),

        actions: const [
          Icon(Icons.search, color: Colors.white),
          SizedBox(width: 15),
          Icon(Icons.more_vert, color: Colors.white),
          SizedBox(width: 10),
        ],
      ),
            body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: getGroups(),
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
                "No Groups Yet",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }

          final groups = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: groups.length,
            itemBuilder: (context, index) {

              final group = groups[index].data();

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),

                child: ListTile(

                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.black,

                    backgroundImage:
                        group["groupImage"] != null &&
                                group["groupImage"] != ""
                            ? NetworkImage(
                                group["groupImage"],
                              )
                            : null,

                    child: group["groupImage"] == null ||
                            group["groupImage"] == ""
                        ? const Icon(
                            Icons.groups,
                            color: Colors.white,
                          )
                        : null,
                  ),

                  title: Text(
                    group["name"] ?? "",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  subtitle: Text(
                    group["lastMessage"] ??
                        "No messages yet",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  trailing: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [

                      Text(
                        group["lastMessageTime"] ?? "",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 5),

                      if ((group["unreadCount"] ?? 0) > 0)
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.green,
                          child: Text(
                            group["unreadCount"]
                                .toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),

                  onTap: () {

                    Navigator.pushNamed(
                      context,
                      "/chat",
                      arguments: {
                        "groupId": groups[index].id,
                        "groupName":
                            group["name"],
                      },
                    );

                  },

                ),
              );
            },
          );
        },
      ),
            floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.pushNamed(
            context,
            "/createGroup",
          );
        },
        child: const Icon(Icons.group_add),
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,

        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });

          if (index == 1) {
            Navigator.pushNamed(
              context,
              "/settings",
            );
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