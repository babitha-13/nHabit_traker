class CategoryColorUtil {
  // Enhanced palette with more variety - darker, distinct colors
  static const List<String> palette = <String>[
    '#8B4513', // Saddle Brown (dark brown)
    '#035929', // Dark Green
    '#0c4b80', // Dark Blue
    '#8B0000', // Dark Red (maroon)
    '#4B0082', // Indigo (dark purple)
    '#6f2e00', // Dark Brown
    '#2F4F4F', // Dark Slate Gray (charcoal)
    '#590059', // Dark Magenta (purple)
    '#6f5922', // Dark grey Brown
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
