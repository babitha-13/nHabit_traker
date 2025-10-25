class CategoryColorUtil {
  // Sophisticated vibrant palette for habit categories - distinct and professional
  static const List<String> palette = <String>[
    '#C57B57', // Copper (your accent - keep this)
    '#2E7D32', // Forest Green
    '#1976D2', // Material Blue
    '#7B1FA2', // Deep Purple
    '#D32F2F', // Deep Red
    '#F57C00', // Dark Orange
    '#5D4037', // Brown
    '#455A64', // Blue Grey
    '#6A1B9A', // Purple
    '#E65100', // Deep Orange
    '#1B5E20', // Dark Green
    '#BF360C', // Deep Red Orange
  ];
  // Deterministic mapping from category name to a color in the palette
  static String hexForName(String name) {
    if (name.trim().isEmpty) {
      return palette.first;
    }
    final lower = name.toLowerCase();
    final sum = lower.codeUnits.fold<int>(0, (acc, u) => acc + u);
    final index = sum % palette.length;
    return palette[index];
  }
}
