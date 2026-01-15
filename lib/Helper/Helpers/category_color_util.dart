class CategoryColorUtil {
  // Unified metallic color palette for all category types (Tasks, Habits, Essentials)
  // Dark, sophisticated tones that complement the Slate + Copper theme
  static const List<String> palette = <String>[
    '#C57B57', // Copper (primary accent color, matches theme)
    '#2F4F4F', // Dark Slate Grey (charcoal)
    '#4B0082', // Deep Metallic Purple
    '#006400', // Dark Green
    '#8B4513', // Saddle Brown (metallic bronze)
    '#4682B4', // Steel Blue
    '#800020', // Burgundy
    '#DAA520', // Goldenrod
    '#008080', // Teal
    '#556B2F', // Dark Olive Green
    '#708090', // Slate Grey
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
