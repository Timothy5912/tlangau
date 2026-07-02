import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Map<String, String>> groupChats = [
    {"name": "Btech IT", "message": "Vawiinah ka e lo"},
    {"name": "Hmeichhe duhlo pawl", "message": "Period tawh phawt chu duhllo ang u.."},
    {"name": "Chanmari Veng", "message": "Kan vengah lo leng suh se"},
    {"name": "Tlangau App", "message": "Dawnga hi bang ang u ti reng a......"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // 🖤 TOP BAR WITH PROFILE
      appBar: AppBar(
        backgroundColor: Colors.black,

        title: Row(
          children: [
            // 📸 PROFILE PICTURE (JPG / asset image)
            const CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage("images/me.jpg"),
            ),

            const SizedBox(width: 10),

            // 👤 PROFILE NAME
            const Text(
              "Timothy",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        actions: const [
          Icon(Icons.search, color: Colors.white),
          SizedBox(width: 15),
          Icon(Icons.more_vert, color: Colors.white),
          SizedBox(width: 10),
        ],
      ),

      // 🤍 GROUP CHAT LIST
      body: ListView.builder(
        itemCount: groupChats.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.black,
                child: Icon(Icons.group, color: Colors.white),
              ),
              title: Text(
                groupChats[index]["name"]!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(groupChats[index]["message"]!),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          );
        },
      ),

      // 🖤 BOTTOM BAR (ONLY GROUP)
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
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