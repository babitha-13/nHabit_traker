import sys
import re

file_path = r'c:\Projects\nHabit_traker-main\lib\services\Activtity\Activity Instance Service\activity_instance_utility_service.dart'
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace first occurrence (getInstancesForTemplate)
    content = re.sub(
        r"\.where\('templateId', isEqualTo: templateId\)\s*\.orderBy\('dueDate', descending: false\);\s*final result = await query\.get\(\);\s*return result\.docs\s*\.map\(\(doc\) => ActivityInstanceRecord\.fromSnapshot\((doc)\)\)\s*\.toList\(\);",
        r".where('templateId', isEqualTo: templateId);\n      final result = await query.get();\n      final instances = result.docs\n          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))\n          .toList();\n      instances.sort((a, b) {\n        if (a.dueDate == null && b.dueDate == null) return 0;\n        if (a.dueDate == null) return -1;\n        if (b.dueDate == null) return 1;\n        return a.dueDate!.compareTo(b.dueDate!);\n      });\n      return instances;",
        content
    )

    # Replace second occurrence (getAllInstances)
    content = re.sub(
        r"\.orderBy\('dueDate', descending: false\);\s*final result = await query\.get\(\);\s*return result\.docs\s*\.map\(\(doc\) => ActivityInstanceRecord\.fromSnapshot\((doc)\)\)\s*\.toList\(\);",
        r";\n      final result = await query.get();\n      final instances = result.docs\n          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))\n          .toList();\n      instances.sort((a, b) {\n        if (a.dueDate == null && b.dueDate == null) return 0;\n        if (a.dueDate == null) return -1;\n        if (b.dueDate == null) return 1;\n        return a.dueDate!.compareTo(b.dueDate!);\n      });\n      return instances;",
        content
    )

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Done")
except Exception as e:
    print(e)
