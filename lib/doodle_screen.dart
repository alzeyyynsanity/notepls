import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DoodleScreen extends StatefulWidget {
  final String noteKey; // Unique key for the note
  final String? initialTitle; // Optional initial title for the doodle

  const DoodleScreen({
    super.key, 
    required this.noteKey, 
    this.initialTitle,
  });

  @override
  _DoodleScreenState createState() => _DoodleScreenState();
}

class _DoodleScreenState extends State<DoodleScreen> {
  // Store drawing as a list of stroke groups for undo/redo functionality
  List<List<Map<String, dynamic>>> strokeHistory = [];
  List<List<Map<String, dynamic>>> redoStack = [];
  
  // Current stroke group being drawn
  List<Map<String, dynamic>> currentStroke = [];
  
  // Title for the doodle
  late TextEditingController _titleController;
  
  Color selectedColor = Colors.black;
  double strokeWidth = 4.0;
  bool isErasing = false;
  late Box doodlesBox;
  late Box doodleTitlesBox;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _loadDoodle();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _loadDoodle() async {
    // Get reference to the already opened boxes
    doodlesBox = Hive.box('doodlesBox');
    
    // Open or create a box for storing doodle titles
    if (!Hive.isBoxOpen('doodleTitlesBox')) {
      doodleTitlesBox = await Hive.openBox('doodleTitlesBox');
    } else {
      doodleTitlesBox = Hive.box('doodleTitlesBox');
    }
    
    var savedDoodle = doodlesBox.get(widget.noteKey);
    var savedTitle = doodleTitlesBox.get(widget.noteKey);

    if (savedTitle != null && _titleController.text.isEmpty) {
      _titleController.text = savedTitle;
    }

    if (savedDoodle != null) {
      try {
        // First, attempt to load with the new format (list of stroke groups)
        if (savedDoodle is List<List<Map<String, dynamic>>>) {
          if (mounted) {
            setState(() {
              strokeHistory = savedDoodle;
              isLoading = false;
            });
          }
        } 
        // Backward compatibility with old format
        else if (savedDoodle is List) {
          List<Map<String, dynamic>> loadedStrokes = [];
          
          for (var item in savedDoodle) {
            if (item is Map) {
              loadedStrokes.add(Map<String, dynamic>.from(item));
            }
          }

          // Convert old format to new format
          List<List<Map<String, dynamic>>> convertedHistory = [];
          List<Map<String, dynamic>> currentGroup = [];
          
          for (var stroke in loadedStrokes) {
            if (stroke['offset'] == null) {
              if (currentGroup.isNotEmpty) {
                convertedHistory.add(List.from(currentGroup));
                currentGroup = [];
              }
            } else {
              currentGroup.add(stroke);
            }
          }
          
          // Add the last group if it's not empty
          if (currentGroup.isNotEmpty) {
            convertedHistory.add(List.from(currentGroup));
          }

          if (mounted) {
            setState(() {
              strokeHistory = convertedHistory;
              isLoading = false;
            });
          }
        }
      } catch (e) {
        
        if (mounted) {
          setState(() {
            strokeHistory = [];
            isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      
     
      if (widget.initialTitle == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTitleDialog(isNew: true);
        });
      }
    }
  }

  void _saveDoodle() async {
    // Make sure we have a title
    if (_titleController.text.trim().isEmpty) {
      await _showTitleDialog(isNew: false);
    }
    
    // Save the doodle content
    await doodlesBox.put(widget.noteKey, strokeHistory);
    
    // Save the title
    await doodleTitlesBox.put(widget.noteKey, _titleController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doodle saved successfully!'))
      );
      Navigator.pop(context);
    }
  }

  Future<void> _showTitleDialog({required bool isNew}) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: !isNew, // User must set a title for new doodles
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isNew ? 'Name Your Doodle' : 'Edit Doodle Title'),
          content: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Enter a title for your doodle',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: <Widget>[
            if (!isNew)
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                // Basic validation to ensure we have a title
                if (_titleController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop();
                } else {
                  // Show a message that title is required
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a title for your doodle'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _undo() {
    if (strokeHistory.isNotEmpty) {
      setState(() {
        // Move the last stroke group to the redo stack
        redoStack.add(strokeHistory.removeLast());
      });
    }
  }

  void _redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        // Move the last undone stroke group back to the history
        strokeHistory.add(redoStack.removeLast());
      });
    }
  }

  void _startStroke(Offset position) {
  setState(() {
    // Start a new stroke group
    currentStroke = [];
    
    // Add the first point
    currentStroke.add({
      'offset': {'dx': position.dx, 'dy': position.dy},
      'color': selectedColor.value, // Always store the actual color
      'strokeWidth': strokeWidth,
      'isEraser': isErasing, // Just store the eraser flag
    });
    
    // Clear redo stack when new drawing starts
    redoStack.clear();
  });
}
void _updateStroke(Offset position) {
  if (currentStroke.isEmpty) return;
  
  setState(() {
    // Add a new point to the current stroke
    currentStroke.add({
      'offset': {'dx': position.dx, 'dy': position.dy},
      'color': selectedColor.value, // Always store the actual color
      'strokeWidth': isErasing ? strokeWidth * 2 : strokeWidth, // Wider for eraser
      'isEraser': isErasing, // Just store the eraser flag
    });
  });
}

  void _endStroke() {
    if (currentStroke.isNotEmpty) {
      setState(() {
        // Add completed stroke group to history
        strokeHistory.add(List.from(currentStroke));
        currentStroke = [];
      });
    }
  }

  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Canvas'),
        content: const Text('Are you sure you want to clear the entire canvas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Save current state to redo stack before clearing
                if (strokeHistory.isNotEmpty) {
                  redoStack = List.from(strokeHistory);
                  strokeHistory = [];
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showTitleDialog(isNew: false),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _titleController.text.isEmpty ? 'Untitled Doodle' : _titleController.text,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 16),
            ],
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 151, 122, 202),
        elevation: 4,
        actions: [
          // Undo button
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: strokeHistory.isEmpty ? null : _undo,
            tooltip: 'Undo',
          ),
          // Redo button
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: redoStack.isEmpty ? null : _redo,
            tooltip: 'Redo',
          ),
          // Save button
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDoodle,
            tooltip: 'Save and exit',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Canvas background
          Container(
            color: Colors.white,
          ),
          // Drawing area
          GestureDetector(
            onPanStart: (details) {
              _startStroke(details.localPosition);
            },
            onPanUpdate: (details) {
              _updateStroke(details.localPosition);
            },
            onPanEnd: (_) {
              _endStroke();
            },
            child: CustomPaint(
              painter: DoodlePainter(strokeHistory, currentStroke),
              size: Size.infinite,
            ),
          ),
          // Tool indicator
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isErasing ? Icons.auto_fix_high : Icons.brush,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isErasing ? 'Eraser' : 'Pen',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 90,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Eraser button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.auto_fix_high, 
                    color: isErasing ? Colors.blue : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      isErasing = !isErasing;
                    });
                  },
                ),
                Text('Eraser', style: TextStyle(
                  fontSize: 12,
                  color: isErasing ? Colors.blue : Colors.grey,
                )),
              ],
            ),
            // Color picker button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.color_lens,
                    color: isErasing ? Colors.grey : selectedColor,
                  ),
                  onPressed: isErasing ? null : _showColorPicker,
                ),
                const Text('Color', style: TextStyle(fontSize: 12)),
              ],
            ),
            // Stroke width button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.line_weight),
                  onPressed: _showStrokeWidthPicker,
                ),
                const Text('Width', style: TextStyle(fontSize: 12)),
              ],
            ),
            // Clear canvas button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _clearCanvas,
                ),
                const Text('Clear', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker() {
  final List<Color> colors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.brown,
  ];

  showModalBottomSheet(
    context: context,
    builder: (context) => Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Color',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: colors.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedColor = colors[index];
                      isErasing = false; // Reset eraser to false when selecting a color
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors[index],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selectedColor == colors[index]
                            ? Colors.blue
                            : Colors.grey,
                        width: selectedColor == colors[index] ? 3 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 3,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

  void _showStrokeWidthPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stroke Width',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            StatefulBuilder(
              builder: (context, setModalState) => Column(
                children: [
                  Slider(
                    value: strokeWidth,
                    min: 1.0,
                    max: 20.0,
                    divisions: 19,
                    label: strokeWidth.round().toString(),
                    onChanged: (value) {
                      setModalState(() {
                        strokeWidth = value;
                      });
                      setState(() {
                        strokeWidth = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStrokePreview(2.0, strokeWidth == 2.0),
                      _buildStrokePreview(5.0, strokeWidth == 5.0),
                      _buildStrokePreview(10.0, strokeWidth == 10.0),
                      _buildStrokePreview(15.0, strokeWidth == 15.0),
                      _buildStrokePreview(20.0, strokeWidth == 20.0),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrokePreview(double width, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          strokeWidth = width;
        });
        Navigator.pop(context);
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Container(
            width: width,
            height: width,
            decoration: BoxDecoration(
              color: selectedColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class DoodlePainter extends CustomPainter {
  final List<List<Map<String, dynamic>>> strokeHistory;
  final List<Map<String, dynamic>> currentStroke;

  DoodlePainter(this.strokeHistory, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes from history
    for (var strokeGroup in strokeHistory) {
      _drawStrokeGroup(canvas, strokeGroup);
    }
    
    // Draw current stroke being drawn
    _drawStrokeGroup(canvas, currentStroke);
  }

void _drawStrokeGroup(Canvas canvas, List<Map<String, dynamic>> strokeGroup) {
  if (strokeGroup.isEmpty) return;
  
  for (int i = 0; i < strokeGroup.length - 1; i++) {
    final current = strokeGroup[i];
    final next = strokeGroup[i + 1];

    final currentOffset = Offset(
      current['offset']['dx'], 
      current['offset']['dy']
    );
    
    final nextOffset = Offset(
      next['offset']['dx'], 
      next['offset']['dy']
    );

    final bool isEraser = current['isEraser'] ?? false;
    
    final paint = Paint()
      ..strokeWidth = current['strokeWidth']
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    
    // Use white color for eraser instead of BlendMode.clear
    if (isEraser) {
      paint.color = Colors.white;
    } else {
      paint.color = Color(current['color']);
    }

    canvas.drawLine(currentOffset, nextOffset, paint);
  }
}

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}