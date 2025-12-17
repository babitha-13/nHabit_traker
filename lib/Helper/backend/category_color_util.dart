class CategoryColorUtil {
  // Refined palette for habit categories - distinct colors that complement the Slate + Copper theme
  // Removed duplicates (similar greens, purples, oranges, reds) and grey (tasks use charcoal default)
  static const List<String> palette = <String>[
    '#C57B57', // Copper (accent color, matches theme)
    '#2E7D32', // Forest Green
    '#1976D2', // Material Blue
    '#7B1FA2', // Deep Purple
    '#D32F2F', // Deep Red
    '#F57C00', // Dark Orange
    '#5D4037', // Brown
    '#00897B', // Teal (complements slate theme, distinct from blue/green)
    '#F59E0B', // Amber (matches theme warning color, distinct from orange)
    '#E91E63', // Pink/Magenta (distinct from purple/red)
    '#3F51B5', // Indigo (between blue and purple, distinct)
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
