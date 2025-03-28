// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:notesplus/service_reminder.dart';
import 'note_model.dart';
import 'doodle_screen.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key}); 

  @override
  _NotesScreenState createState() => _NotesScreenState();
}


class _NotesScreenState extends State<NotesScreen> {
  late Box<Note> notesBox;
  late Box doodlesBox;
  late Box doodleTitlesBox;
  bool isLoading = true;
  
  // Colors for different item types
  final Color noteColor = const Color(0xFFFFDAB9); // Peach color
  final Color doodleColor = const Color(0xFFE6E6FA); // Light violet color

  // For filtering content
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'notes', 'doodles'
  String _viewType = 'grid'; // Default view type

  @override
  void initState() {
    super.initState();
    _loadBoxes();
  }

  Future<void> _loadBoxes() async {
    // Get existing boxes
    notesBox = Hive.box<Note>('notesBox');
    doodlesBox = Hive.box('doodlesBox');
    
    // Make sure doodleTitlesBox is open
    if (!Hive.isBoxOpen('doodleTitlesBox')) {
      doodleTitlesBox = await Hive.openBox('doodleTitlesBox');
    } else {
      doodleTitlesBox = Hive.box('doodleTitlesBox');
    }
    
    setState(() {
      isLoading = false;
    });
  }

void _addNote(String title, String content, {bool hasReminder = false, DateTime? reminderDateTime}) {
  if (title.trim().isEmpty) {
    _showSnackbar('Please enter a title');
    return;
  }
  
  if (content.trim().isEmpty) {
    _showSnackbar('Please enter some content');
    return;
  }
  
  // Generate a unique notification ID
  final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
  
  final note = Note(
    title: title, 
    content: content, 
    createdAt: DateTime.now(),
    hasReminder: hasReminder,
    reminderDateTime: reminderDateTime,
    notificationId: hasReminder ? notificationId : null,
  );

  // Save the note
  notesBox.add(note);

  // Schedule notification if reminder is set
  if (hasReminder && reminderDateTime != null) {
    NotificationService.scheduleNotification(
      id: notificationId,
      title: note.title,
      body: note.content,
      scheduledDate: reminderDateTime,
    );
  }

  // Force a UI update and reset filters
  setState(() {
    _filterType = 'all';
    _searchQuery = '';
  });

  _showSnackbar('Note saved successfully!');
}

  void _editNote(int index, String title, String content) {
  if (title.trim().isEmpty) {
    _showSnackbar('Please enter a title');
    return;
  }
  
  if (content.trim().isEmpty) {
    _showSnackbar('Please enter some content');
    return;
  }
  
  final note = notesBox.getAt(index) as Note;
  final updatedNote = Note(
    title: title, 
    content: content, 
    createdAt: note.createdAt,  // Keep the original creation date
    hasReminder: note.hasReminder,  // Preserve reminder status
    reminderDateTime: note.reminderDateTime,  // Preserve reminder date/time
    notificationId: note.notificationId,  // Preserve notification ID
  );
  notesBox.putAt(index, updatedNote);
  setState(() {});
  _showSnackbar('Note updated successfully!');
}

  void _deleteNote(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notesBox.deleteAt(index);
              setState(() {});
              Navigator.pop(context);
              _showSnackbar('Note deleted successfully!');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteDoodle(String doodleKey) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Doodle'),
        content: const Text('Are you sure you want to delete this doodle?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              doodlesBox.delete(doodleKey);
              doodleTitlesBox.delete(doodleKey);
              setState(() {});
              Navigator.pop(context);
              _showSnackbar('Doodle deleted successfully!');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<dynamic> _getFilteredItems() {
    List<dynamic> items = [];
    
    // Get notes
    if (_filterType == 'all' || _filterType == 'notes') {
      for (int i = 0; i < notesBox.length; i++) {
        final note = notesBox.getAt(i) as Note;
        if (_searchQuery.isEmpty || 
            note.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            note.content.toLowerCase().contains(_searchQuery.toLowerCase())) {
          items.add({'type': 'note', 'index': i, 'data': note});
        }
      }
    }
    
    // Get doodles
    if (_filterType == 'all' || _filterType == 'doodles') {
      final doodleKeys = doodlesBox.keys.cast<String>().where((key) => key.startsWith('doodle_')).toList();
      for (int i = 0; i < doodleKeys.length; i++) {
        final doodleKey = doodleKeys[i];
        final doodleTitle = doodleTitlesBox.get(doodleKey) ?? 'Untitled Doodle';
        if (_searchQuery.isEmpty || 
            doodleTitle.toLowerCase().contains(_searchQuery.toLowerCase())) {
          items.add({'type': 'doodle', 'index': i, 'key': doodleKey, 'title': doodleTitle});
        }
      }
    }
    
    // Sort items by most recent (temporarily hardcoded for doodles)
    items.sort((a, b) {
      if (a['type'] == 'note' && b['type'] == 'note') {
        return (b['data'] as Note).createdAt.compareTo((a['data'] as Note).createdAt);
      } else if (a['type'] == 'doodle' && b['type'] == 'doodle') {
        // Extract timestamp from doodle key (doodle_timestamp format)
        final aTime = int.tryParse(a['key'].toString().split('_')[1]) ?? 0;
        final bTime = int.tryParse(b['key'].toString().split('_')[1]) ?? 0;
        return bTime.compareTo(aTime);
      } else if (a['type'] == 'note') {
        // Notes above doodles
        return -1;
      } else {
        // Doodles below notes
        return 1;
      }
    });
    
    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final filteredItems = _getFilteredItems();
    
    return Scaffold(
appBar: AppBar(
  title: const Text(''),
  backgroundColor: const Color.fromARGB(255, 151, 122, 202),
  elevation: 4,
  actions: [
    IconButton(
      icon: Icon(_viewType == 'grid' ? Icons.view_list : Icons.grid_view),
      tooltip: _viewType == 'grid' ? 'Switch to list view' : 'Switch to grid view',
      onPressed: () {
        setState(() {
          _viewType = _viewType == 'grid' ? 'list' : 'grid';
        });
      },
    ),
    IconButton(
      icon: const Icon(Icons.sort),
      tooltip: 'Filter content',
      onPressed: _showFilterDialog,
    ),
  ],
),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color.fromARGB(255, 151, 122, 202),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: Image.asset('assets/logo.png'), // Make sure you have the logo file
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      ' Menu',
                      style: TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('All Notes'),
              onTap: () {
                setState(() {
                  _filterType = 'all';
                  _searchQuery = '';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Text Notes Only'),
              onTap: () {
                setState(() {
                  _filterType = 'notes';
                  _searchQuery = '';
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brush),
              title: const Text('Doodles Only'),
              onTap: () {
                setState(() {
                  _filterType = 'doodles';
                  _searchQuery = '';
                });
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                _showAboutDialog();
              },
            ),
          ],
        ),
      ),
     body: Column(
  children: [
    Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search notes and doodles...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          filled: true,
          fillColor: Colors.white,
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    ),
    Expanded(
      child: filteredItems.isEmpty
          ? _buildEmptyState()
          : _buildContent(filteredItems), // Use the new _buildContent method
    ),
  ],
),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color.fromARGB(255, 151, 122, 202),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Create New',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildAddButton(
                        icon: Icons.text_snippet,
                        label: 'Text Note',
                        onTap: () {
                          Navigator.pop(context);
                          _showNoteDialog(context);
                        },
                      ),
                      _buildAddButton(
                        icon: Icons.brush,
                        label: 'Doodle',
                        onTap: () async {
                          Navigator.pop(context);
                          final String doodleKey = 'doodle_${DateTime.now().millisecondsSinceEpoch}';
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DoodleScreen(
                                noteKey: doodleKey,
                                initialTitle: 'New Doodle',
                              ),
                            ),
                          );
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
  
  Widget _buildAddButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color.fromARGB(255, 151, 122, 202)),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _filterType == 'notes' ? Icons.note_alt_outlined :
            _filterType == 'doodles' ? Icons.brush : Icons.note_add,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No results found for "$_searchQuery"'
                : _filterType == 'notes'
                    ? 'No text notes yet'
                    : _filterType == 'doodles'
                        ? 'No doodles yet'
                        : 'No notes or doodles yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: Icon(
              _filterType == 'doodles' ? Icons.brush : Icons.note_add,
            ),
            label: Text(
              _filterType == 'doodles'
                  ? 'Create a Doodle'
                  : 'Create a Note',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 151, 122, 202),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              if (_filterType == 'doodles') {
                final String doodleKey = 'doodle_${DateTime.now().millisecondsSinceEpoch}';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DoodleScreen(
                      noteKey: doodleKey,
                      initialTitle: 'New Doodle',
                    ),
                  ),
                ).then((_) => setState(() {}));
              } else {
                _showNoteDialog(context);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Notes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Content type filters
            RadioListTile<String>(
              title: const Text('All Items'),
              value: 'all',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Text Notes Only'),
              value: 'notes',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('Doodles Only'),
              value: 'doodles',
              groupValue: _filterType,
              onChanged: (value) {
                setState(() {
                  _filterType = value!;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  
Widget _buildNoteCard(Note note, int index) {
  return Card(
    elevation: 4,
    color: noteColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: InkWell(
      onTap: () {
        _showNoteDetailDialog(note, index);
      },
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.text_snippet, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Reminder indicator
                if (note.hasReminder == true)
                  const Icon(Icons.alarm, color: Colors.red, size: 20),
              ],
            ),
            const Divider(),
            Expanded(
              child: Text(
                note.content,
                style: const TextStyle(fontSize: 14),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _showEditNoteDialog(context, note, index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                      onPressed: () => _deleteNote(index),
                    ),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    ),
  );    
}
  
  Widget _buildDoodleCard(String doodleKey, String doodleTitle) {
    return Card(
      elevation: 4,
      color: doodleColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DoodleScreen(
                noteKey: doodleKey,
                initialTitle: doodleTitle,
              ),
            ),
          ).then((_) {
            // Refresh the UI when returning from the doodle screen
            setState(() {});
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.brush, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      doodleTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.draw,
                    size: 48,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DoodleScreen(
                            noteKey: doodleKey,
                            initialTitle: doodleTitle,
                          ),
                        ),
                      ).then((_) {
                        setState(() {});
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: () => _deleteDoodle(doodleKey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildContent(List<dynamic> items) {
  // Return grid or list view based on the _viewType
  if (_viewType == 'grid') {
    return _buildGridContent(items);
  } else {
    return _buildListContent(items);
  }
}

Widget _buildGridContent(List<dynamic> items) {
  return GridView.builder(
    padding: const EdgeInsets.all(8.0),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.8,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      
      if (item['type'] == 'note') {
        return _buildNoteCard(item['data'] as Note, item['index'] as int);
      } else {
        return _buildDoodleCard(item['key'] as String, item['title'] as String);
      }
    },
  );
}
Widget _buildNoteListItem(Note note, int index) {
  return Card(
    elevation: 3,
    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
    color: noteColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Icons.text_snippet),
      title: Row(
        children: [
          Expanded(
            child: Text(
              note.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Reminder indicator
          if (note.hasReminder == true)
            const Icon(Icons.alarm, color: Colors.red, size: 20),
        ],
      ),
      subtitle: Text(
        note.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _showEditNoteDialog(context, note, index),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: () => _deleteNote(index),
          ),
        ],
      ),
      onTap: () {
        _showNoteDetailDialog(note, index);
      },
    ),
  );
}
Widget _buildDoodleListItem(String doodleKey, String doodleTitle) {
  return Card(
    elevation: 3,
    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
    color: doodleColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: const Icon(Icons.brush),
      title: Text(
        doodleTitle,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: const Text("Tap to view or edit this doodle"),
      trailing: IconButton(
        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
        onPressed: () => _deleteDoodle(doodleKey),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DoodleScreen(
              noteKey: doodleKey,
              initialTitle: doodleTitle,
            ),
          ),
        ).then((_) {
          setState(() {});
        });
      },
    ),
  );
}

Widget _buildListContent(List<dynamic> items) {
  return ListView.builder(
    padding: const EdgeInsets.all(8.0),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      
      if (item['type'] == 'note') {
        return _buildNoteListItem(item['data'] as Note, item['index'] as int);
      } else {
        return _buildDoodleListItem(item['key'] as String, item['title'] as String);
      }
    },
  );
}
  void _showNoteDetailDialog(Note note, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Created: ${note.createdAt.day}/${note.createdAt.month}/${note.createdAt.year}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 10),
              Text(note.content),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditNoteDialog(context, note, index);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

 void _showEditNoteDialog(BuildContext context, Note note, int index) {
  final titleController = TextEditingController(text: note.title);
  final contentController = TextEditingController(text: note.content);
  
  // Initialize reminder-related variables
  bool hasReminder = note.hasReminder;
  DateTime? selectedReminderDate = note.reminderDateTime;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              // Reminder toggle
              SwitchListTile(
                title: const Text('Add Reminder'),
                value: hasReminder,
                onChanged: (bool value) {
                  setState(() {
                    hasReminder = value;
                    if (!value) {
                      selectedReminderDate = null;
                    }
                  });
                },
              ),
              // Reminder date and time picker (if reminder is enabled)
              if (hasReminder)
                ElevatedButton(
                  onPressed: () async {
                    final pickedDateTime = await showDateTimePicker(context);
                    if (pickedDateTime != null) {
                      setState(() {
                        selectedReminderDate = pickedDateTime;
                      });
                    }
                  },
                  child: Text(
                    selectedReminderDate == null
                        ? 'Select Reminder Time'
                        : 'Reminder: ${selectedReminderDate!.toString()}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 151, 122, 202),
            ),
            onPressed: () {
              // Update the note with reminder information
              final updatedNote = Note(
                title: titleController.text, 
                content: contentController.text,
                createdAt: note.createdAt,  // Keep original creation date
                hasReminder: hasReminder,
                reminderDateTime: selectedReminderDate,
                notificationId: hasReminder 
                  ? (note.notificationId ?? DateTime.now().millisecondsSinceEpoch.remainder(100000))
                  : null,
              );

              // Remove previous notification if exists
              if (note.hasReminder == true && note.notificationId != null) {
                NotificationService.cancelNotification(note.notificationId!);
              }

              // Schedule new notification if reminder is set
              if (hasReminder && selectedReminderDate != null) {
                NotificationService.scheduleNotification(
                  id: updatedNote.notificationId!,
                  title: updatedNote.title,
                  body: updatedNote.content,
                  scheduledDate: selectedReminderDate!,
                );
              }

              // Save the updated note
              notesBox.putAt(index, updatedNote);
              
              // Explicitly call setState to trigger UI update
              this.setState(() {});
              
              Navigator.pop(context);
              _showSnackbar('Note updated successfully!');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

 void _showNoteDialog(BuildContext context) {
  final titleController = TextEditingController();
  final contentController = TextEditingController();
  
  // Reminder-related variables
  bool hasReminder = false;
  DateTime? selectedReminderDate;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create New Note'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                  hintText: 'Enter note title',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                  hintText: 'Enter note content',
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              // Reminder toggle
              SwitchListTile(
                title: const Text('Add Reminder'),
                value: hasReminder,
                onChanged: (bool value) {
                  setState(() {
                    hasReminder = value;
                  });
                },
              ),
              // Reminder date and time picker (if reminder is enabled)
              if (hasReminder)
                ElevatedButton(
                  onPressed: () async {
                    final pickedDateTime = await showDateTimePicker(context);
                    if (pickedDateTime != null) {
                      setState(() {
                        selectedReminderDate = pickedDateTime;
                      });
                    }
                  },
                  child: Text(
                    selectedReminderDate == null
                        ? 'Select Reminder Time'
                        : 'Reminder: ${selectedReminderDate!.toString()}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 151, 122, 202),
            ),
            onPressed: () {
              // Call the new _addNote method
              _addNote(
                titleController.text, 
                contentController.text,
                hasReminder: hasReminder,
                reminderDateTime: selectedReminderDate
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}


// Helper method to show date and time picker
Future<DateTime?> showDateTimePicker(BuildContext context) async {
  DateTime? pickedDate = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime(2101),
  );

  TimeOfDay? pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
  );

  if (pickedTime != null) {
    return DateTime(
      pickedDate!.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  return null;
}
  
 void _showAboutDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('About '),
      content: SingleChildScrollView( // Scrollable content
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/art.png', width: 80, height: 80),
            const SizedBox(height: 16),
            const Text(
              'Version 1.0.0',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'This is a simple and intuitive note-taking and doodling app. Create text notes and drawings all in one place.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '© 2025 ',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),

            const Text(
              'Introducing Team Mystique',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Developer 1 - Centered
            Column(
              children: [
                CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/daayata.jpg')),
                const SizedBox(height: 5),
                const Text('Charity Daayata', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Stressed Leader'),
              ],
            ),
            const SizedBox(height: 10),

            // Developer 2 and 3 - Wrapped in Flexible
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded( // Prevents overflow
                  child: Column(
                    children: [
                      CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/sinco.jpg')),
                      const SizedBox(height: 5),
                      const Text('Benjie Sinco', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Sponsor sa Load'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/sale.jpg')),
                      const SizedBox(height: 5),
                      const Text('Alje Sale', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Sponsor sa Load'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Developer 4 and 5 - Wrapped in Flexible
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/angel.jpg')),
                      const SizedBox(height: 5),
                      const Text('Angelica', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Engelbrecht', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Errand Girl'),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      CircleAvatar(radius: 30, backgroundImage: AssetImage('assets/pionan.jpg')),
                      const SizedBox(height: 5),
                      const Text('Cherry Pionan', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text('Laptop Provider'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

  
}
