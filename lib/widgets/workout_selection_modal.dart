import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/workout_history_service.dart';

class WorkoutSelectionModal extends StatefulWidget {
  final Function(WorkoutTemplate, int, String?) onWorkoutSelected;

  const WorkoutSelectionModal({
    super.key,
    required this.onWorkoutSelected,
  });

  @override
  State<WorkoutSelectionModal> createState() => _WorkoutSelectionModalState();
}

class _WorkoutSelectionModalState extends State<WorkoutSelectionModal> {
  final WorkoutHistoryService _historyService = WorkoutHistoryService();
  
  List<WorkoutTemplate>? _templates;
  bool _isLoading = true;
  String _selectedCategory = 'all';

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    
    final templates = await _historyService.getWorkoutTemplates();
    
    setState(() {
      _templates = templates;
      _isLoading = false;
    });
  }

  List<WorkoutTemplate> get _filteredTemplates {
    if (_templates == null) return [];
    if (_selectedCategory == 'all') return _templates!;
    return _templates!.where((t) => t.category == _selectedCategory).toList();
  }

  /// Quick select - use default duration
  void _quickSelectTemplate(WorkoutTemplate template) {
    HapticFeedback.lightImpact();
    Navigator.pop(context);
    widget.onWorkoutSelected(template, template.defaultDurationMinutes, null);
  }

  /// Custom duration dialog - ORIGINAL STYLING preserved
  void _showCustomDurationDialog(WorkoutTemplate template) {
    HapticFeedback.lightImpact();
    int customDuration = template.defaultDurationMinutes;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Text(template.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      template.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Duration section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Set your workout goal',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Decrease button
                          _buildDurationButton(
                            icon: Icons.remove,
                            onTap: customDuration > 5
                                ? () => setDialogState(() => customDuration -= 5)
                                : null,
                          ),
                          const SizedBox(width: 20),
                          // Duration display
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[300]!),
                            ),
                            child: Text(
                              '$customDuration min',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[800],
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Increase button
                          _buildDurationButton(
                            icon: Icons.add,
                            onTap: customDuration < 180
                                ? () => setDialogState(() => customDuration += 5)
                                : null,
                            isAdd: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Quick presets
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [15, 30, 45, 60, 90].map((mins) {
                          final isSelected = customDuration == mins;
                          return GestureDetector(
                            onTap: () => setDialogState(() => customDuration = mins),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.orange[600] : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? Colors.orange[600]! : Colors.grey[300]!,
                                ),
                              ),
                              child: Text(
                                '$mins',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.grey[700],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Notes field
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    hintText: 'Add notes (optional)',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.orange[400]!, width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                    prefixIcon: Icon(Icons.notes, color: Colors.grey[400]),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close dialog
                Navigator.pop(context); // Close selection modal
                final notes = notesController.text.trim();
                widget.onWorkoutSelected(
                  template,
                  customDuration,
                  notes.isEmpty ? null : notes,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Start Workout', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationButton({
    required IconData icon,
    required VoidCallback? onTap,
    bool isAdd = false,
  }) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isEnabled
              ? (isAdd ? Colors.orange[100] : Colors.grey[200])
              : Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 24,
          color: isEnabled
              ? (isAdd ? Colors.orange[800] : Colors.grey[700])
              : Colors.grey[400],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      // FIX: Slightly reduced max height to prevent overflow on smaller screens
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  'Select Workout Type',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Category filter
          _buildCategoryFilter(),
          
          const SizedBox(height: 8),
          Divider(color: Colors.grey[200], height: 1),
          
          // Template list
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
                itemCount: _filteredTemplates.length,
                itemBuilder: (context, index) {
                  final template = _filteredTemplates[index];
                  return _buildTemplateCard(template);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = [
      ('all', 'All', '🏆'),
      ('strength', 'Strength', '💪'),
      ('cardio', 'Cardio', '🏃'),
      ('hiit', 'HIIT', '⚡'),
      ('yoga', 'Yoga', '🧘'),
      ('sports', 'Sports', '⚽'),
      ('other', 'Other', '✨'),
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final (value, label, emoji) = categories[index];
          final isSelected = _selectedCategory == value;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(label),
                ],
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = value),
              backgroundColor: Colors.grey[100],
              selectedColor: Colors.orange[100],
              checkmarkColor: Colors.orange[800],
              side: BorderSide(
                color: isSelected ? Colors.orange[400]! : Colors.grey[300]!,
              ),
              labelStyle: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.orange[900] : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTemplateCard(WorkoutTemplate template) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _quickSelectTemplate(template),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Emoji container
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      template.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (template.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          template.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Duration + edit button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${template.defaultDurationMinutes} min',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ✨ CUSTOM DURATION EDIT BUTTON
                    GestureDetector(
                      onTap: () => _showCustomDurationDialog(template),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}