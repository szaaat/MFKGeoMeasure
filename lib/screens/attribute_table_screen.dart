import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/geo_feature.dart';
import '../models/field_definition.dart';
import '../services/project_service.dart';
import '../widgets/export_config_dialog.dart';

class AttributeTableScreen extends StatefulWidget {
  final ProjectLayer layer;
  const AttributeTableScreen({super.key, required this.layer});

  @override
  State<AttributeTableScreen> createState() => _AttributeTableScreenState();
}

class _AttributeTableScreenState extends State<AttributeTableScreen> {
  String _searchQuery = "";
  String _sortKey = "createdAt";
  bool _sortAscending = false;
  
  // Filtering states
  final Map<String, dynamic> _filters = {}; // e.g. {'HDOP': {'op': '<', 'val': 1.0}}
  
  // Column Visibility
  late Set<String> _visibleColumns;
  
  final ScrollController _horizontalHeaderScroll = ScrollController();
  final ScrollController _horizontalBodyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _horizontalBodyScroll.addListener(() {
      if (_horizontalHeaderScroll.hasClients) {
        _horizontalHeaderScroll.jumpTo(_horizontalBodyScroll.offset);
      }
    });
    
    // Initialize visible columns with all available
    _visibleColumns = _getAllPossibleColumns().toSet();
  }

  @override
  void dispose() {
    _horizontalHeaderScroll.dispose();
    _horizontalBodyScroll.dispose();
    super.dispose();
  }

  List<String> _getAllPossibleColumns() {
    final List<String> cols = ["Name", "Description", "Type"];
    for (var f in widget.layer.fields) {
      cols.add(f.key);
    }
    final Set<String> statKeys = {};
    for (var f in widget.layer.features) {
      statKeys.addAll(f.calculatedStats.keys);
    }
    final priorityStats = [
      'EOV Y', 'EOV X', 'Ellipszoidi magasság', 'Balti magasság', 
      'Survey Method', 'GNSS Source', 'RTK Status', 'Correction Age', 
      'Sats Used', 'HDOP', 'Timestamp Source'
    ];
    for (var ps in priorityStats) {
      if (statKeys.contains(ps)) cols.add(ps);
    }
    cols.add("Created At");
    return cols;
  }

  List<GeoFeature> _getFilteredAndSortedFeatures() {
    Iterable<GeoFeature> filtered = widget.layer.features;
    
    // 1. Text Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((f) {
        if (f.name.toLowerCase().contains(q)) return true;
        if (f.description.toLowerCase().contains(q)) return true;
        for (var val in f.customData.values) {
          if (val.toString().toLowerCase().contains(q)) return true;
        }
        for (var val in f.calculatedStats.values) {
          if (val.toString().toLowerCase().contains(q)) return true;
        }
        return false;
      });
    }

    // 2. Advanced Attribute Filters
    if (_filters.isNotEmpty) {
      _filters.forEach((key, filter) {
        filtered = filtered.where((f) {
          final val = _getValue(f, key);
          if (val == null) return false;
          
          final op = filter['op'];
          final target = filter['val'];

          if (val is num && target is num) {
            if (op == '<') return val < target;
            if (op == '<=') return val <= target;
            if (op == '>') return val > target;
            if (op == '>=') return val >= target;
            if (op == '==') return val == target;
          } else {
            if (op == '==') return val.toString().toLowerCase() == target.toString().toLowerCase();
            if (op == 'contains') return val.toString().toLowerCase().contains(target.toString().toLowerCase());
          }
          return true;
        });
      });
    }

    final list = filtered.toList();
    
    // 3. Sorting
    list.sort((a, b) {
      dynamic valA = _getValue(a, _sortKey);
      dynamic valB = _getValue(b, _sortKey);
      
      int cmp;
      if (valA == null && valB == null) {
        cmp = 0;
      } else if (valA == null) {
        cmp = -1;
      } else if (valB == null) {
        cmp = 1;
      } else if (valA is Comparable && valB is Comparable) {
        try {
          cmp = valA.compareTo(valB);
        } catch (_) {
           cmp = valA.toString().compareTo(valB.toString());
        }
      } else {
        cmp = valA.toString().compareTo(valB.toString());
      }
      
      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  dynamic _getValue(GeoFeature f, String key) {
    if (key == "Name") return f.name;
    if (key == "Description") return f.description;
    if (key == "Type") return f.type.name;
    if (key == "Created At") return f.createdAt;
    if (f.customData.containsKey(key)) return f.customData[key];
    if (f.calculatedStats.containsKey(key)) return f.calculatedStats[key];
    return null;
  }

  String _formatValue(dynamic val) {
    if (val == null) return "-";
    if (val is DateTime) return DateFormat('yyyy-MM-dd HH:mm').format(val);
    if (val is double) return val.toStringAsFixed(3);
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    final projectService = context.watch<ProjectService>();
    final allPossibleCols = _getAllPossibleColumns();
    final columns = allPossibleCols.where((c) => _visibleColumns.contains(c)).toList();
    final features = _getFilteredAndSortedFeatures();
    final selectedCount = projectService.selectedFeatureIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${widget.layer.name} - GIS Table", style: const TextStyle(fontSize: 16)),
            Text("${features.length} / ${widget.layer.features.length} features", style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          if (selectedCount > 0)
            Center(child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text("$selectedCount selected", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
            )),
          IconButton(
            icon: const Icon(Icons.view_column),
            onPressed: () => _showColumnConfig(allPossibleCols),
            tooltip: "Oszlopok kezelése",
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _showFilterDialog,
            tooltip: "Szűrés",
          ),
          if (selectedCount > 0)
            PopupMenuButton<String>(
              onSelected: (val) => _handleBulkAction(val, projectService),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, size: 18), SizedBox(width: 8), Text("Export Selected")])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text("Delete Selected", style: TextStyle(color: Colors.red))])),
                const PopupMenuItem(value: 'clear', child: Row(children: [Icon(Icons.clear_all, size: 18), SizedBox(width: 8), Text("Clear Selection")])),
              ],
            )
        ],
      ),
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Gyorskeresés...",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchQuery = "")) : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // --- TABLE HEADER ---
          Container(
            color: Colors.grey[200],
            child: SingleChildScrollView(
              controller: _horizontalHeaderScroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSelectionHeader(projectService, features),
                  for (var col in columns) _buildHeaderCell(col),
                ],
              ),
            ),
          ),

          // --- TABLE BODY (Virtualized) ---
          Expanded(
            child: SingleChildScrollView(
              controller: _horizontalBodyScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (columns.length * 150.0) + 50.0,
                child: ListView.builder(
                  itemCount: features.length,
                  itemBuilder: (ctx, index) {
                    final f = features[index];
                    final isSelected = projectService.selectedFeatureIds.contains(f.id);
                    
                    return GestureDetector(
                      onTap: () {
                        projectService.selectFeature(widget.layer.id, f.id);
                      },
                      onLongPress: () {
                        projectService.selectFeature(widget.layer.id, f.id, multiSelect: true);
                      },
                      onDoubleTap: () => _editFeature(context, f),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.withValues(alpha: 0.15) : (index % 2 == 0 ? Colors.white : Colors.grey[50]),
                          border: Border(bottom: BorderSide(color: Colors.grey[300]!, width: 0.5)),
                        ),
                        height: 48,
                        child: Row(
                          children: [
                            _buildSelectionCell(projectService, f, isSelected),
                            for (var col in columns) _buildBodyCell(f, col, isSelected),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader(ProjectService service, List<GeoFeature> visibleFeatures) {
    final allVisibleSelected = visibleFeatures.isNotEmpty && visibleFeatures.every((f) => service.selectedFeatureIds.contains(f.id));
    return Container(
      width: 50,
      alignment: Alignment.center,
      child: Checkbox(
        value: allVisibleSelected,
        onChanged: (val) {
          if (val == true) {
            for (var f in visibleFeatures) {
              if (!service.selectedFeatureIds.contains(f.id)) {
                service.selectFeature(widget.layer.id, f.id, multiSelect: true);
              }
            }
          } else {
            service.clearSelection();
          }
        },
      ),
    );
  }

  Widget _buildSelectionCell(ProjectService service, GeoFeature feature, bool isSelected) {
    return Container(
      width: 50,
      alignment: Alignment.center,
      child: Checkbox(
        value: isSelected,
        onChanged: (val) {
          service.selectFeature(widget.layer.id, feature.id, multiSelect: true);
        },
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    final isSorted = _sortKey == label;
    return InkWell(
      onTap: () => setState(() {
        if (_sortKey == label) {
          _sortAscending = !_sortAscending;
        } else {
          _sortKey = label;
          _sortAscending = true;
        }
      }),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey[400]!, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            if (isSorted) 
              Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyCell(GeoFeature f, String key, bool isSelected) {
    final val = _getValue(f, key);
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey[300]!, width: 0.5)),
      ),
      child: Text(
        _formatValue(val),
        style: TextStyle(
          fontSize: 12, 
          color: isSelected ? Colors.blue[900] : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _showColumnConfig(List<String> allCols) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Oszlopok konfigurálása"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allCols.length,
              itemBuilder: (ctx, i) {
                final col = allCols[i];
                return CheckboxListTile(
                  title: Text(col, style: const TextStyle(fontSize: 13)),
                  value: _visibleColumns.contains(col),
                  onChanged: (val) {
                    setDialogState(() {
                      if (val == true) {
                        _visibleColumns.add(col);
                      } else if (_visibleColumns.length > 1) {
                        _visibleColumns.remove(col);
                      }
                    });
                    setState(() {}); // Update main screen
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Bezárás"))],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    // Basic attribute filtering
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Szűrési feltételek"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Tipp: Jelenleg a felső keresősávval tudsz minden mezőben keresni.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            if (_filters.isNotEmpty) ...[
               const SizedBox(height: 10),
               ElevatedButton.icon(
                 icon: const Icon(Icons.filter_alt_off),
                 label: const Text("Szűrők törlése"),
                 onPressed: () {
                   setState(() => _filters.clear());
                   Navigator.pop(ctx);
                 },
               )
            ],
            // TODO: Advanced numeric filter UI
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Bezárás"))],
      ),
    );
  }

  void _handleBulkAction(String action, ProjectService service) {
    if (action == 'clear') {
      service.clearSelection();
    } else if (action == 'delete') {
      _showBulkDeleteConfirm(service);
    } else if (action == 'export') {
      showDialog(
        context: context,
        builder: (ctx) => ExportConfigDialog(
          project: service.activeProject!,
          initialLayer: widget.layer,
          initialSelection: widget.layer.features
              .where((f) => service.selectedFeatureIds.contains(f.id))
              .toList(),
        ),
      );
    }
  }

  void _showBulkDeleteConfirm(ProjectService service) {
    final count = service.selectedFeatureIds.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$count elem törlése?"),
        content: const Text("Biztosan törölni szeretnéd a kijelölt elemeket? Ez a művelet nem vonható vissza."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Mégse")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              final ids = List<String>.from(service.selectedFeatureIds);
              for (var id in ids) {
                service.deleteFeature(id);
              }
              Navigator.pop(ctx);
              setState(() {});
            }, 
            child: const Text("Törlés")
          ),
        ],
      ),
    );
  }

  void _editFeature(BuildContext context, GeoFeature feature) {
    final service = context.read<ProjectService>();
    final nameCtrl = TextEditingController(text: feature.name);
    final descCtrl = TextEditingController(text: feature.description);
    Map<String, dynamic> editData = Map.from(feature.customData);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("${feature.name} szerkesztése"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Név")),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Leírás")),
                const Divider(height: 30),
                ...widget.layer.fields.map((fDef) {
                  return _buildFieldInput(
                    context: context,
                    label: fDef.label,
                    type: fDef.type,
                    choices: fDef.choices,
                    initialValue: editData[fDef.key],
                    onChanged: (val) => setDialogState(() => editData[fDef.key] = val),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Mégse")),
            ElevatedButton(
              onPressed: () async {
                feature.name = nameCtrl.text;
                feature.description = descCtrl.text;
                
                String? error;
                for (var entry in editData.entries) {
                   final res = await service.updateFeatureAttribute(widget.layer.id, feature.id, entry.key, entry.value);
                   if (res != null) error = res;
                }

                if (error != null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red));
                  }
                } else {
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    setState(() {});
                  }
                }
              }, 
              child: const Text("Mentés")
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldInput({
    required BuildContext context,
    required String label,
    required FieldType type,
    List<String>? choices,
    dynamic initialValue,
    required Function(dynamic) onChanged,
  }) {
    if (type == FieldType.bool) {
      return SwitchListTile(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: initialValue ?? false,
        onChanged: onChanged,
      );
    } else if (type == FieldType.choice && choices != null) {
      return DropdownButtonFormField<String>(
        initialValue: initialValue,
        decoration: InputDecoration(labelText: label),
        items: choices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: onChanged,
      );
    } else if (type == FieldType.date || type == FieldType.dateTime) {
      final dt = initialValue is DateTime ? initialValue : (initialValue != null ? DateTime.tryParse(initialValue.toString()) : null);
      final format = type == FieldType.date ? DateFormat('yyyy-MM-dd') : DateFormat('yyyy-MM-dd HH:mm');
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(dt != null ? format.format(dt) : "Nincs kiválasztva", style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.calendar_today, size: 18),
        onTap: () async {
          final date = await showDatePicker(
            context: context, 
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(2000), 
            lastDate: DateTime(2100)
          );
          if (date != null) {
            if (type == FieldType.dateTime) {
              if (!context.mounted) return;
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dt ?? DateTime.now()));
              if (time != null) {
                onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
              }
            } else {
              onChanged(date);
            }
          }
        },
      );
    } else {
      return TextField(
        decoration: InputDecoration(labelText: label),
        keyboardType: (type == FieldType.integer || type == FieldType.decimal) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        controller: TextEditingController(text: initialValue?.toString() ?? ""),
        onChanged: (val) {
          if (type == FieldType.integer) {
            onChanged(int.tryParse(val));
          } else if (type == FieldType.decimal) {
            onChanged(double.tryParse(val.replaceAll(',', '.')));
          } else {
            onChanged(val);
          }
        },
      );
    }
  }
}
