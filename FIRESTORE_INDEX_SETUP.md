# Firestore Index Setup Guide

This guide provides step-by-step instructions for creating the consolidated Firestore indexes required for the application.

## Prerequisites

- Access to Firebase Console (https://console.firebase.google.com)
- Select your project
- Navigate to Firestore Database → Indexes

## Index Creation Instructions

### Index 1: Template-Based Queries (CRITICAL - Fixes Uncomplete Issue)

**This index must be created first as it fixes the uncomplete/reset operations.**

1. Click "Add index" button
2. Collection ID: `activity_instances`
3. Add fields in this exact order:
   - Field: `templateId`, Order: `Ascending`
   - Field: `status`, Order: `Ascending`
   - Field: `belongsToDate`, Order: `Ascending`
   - Field: `dueDate`, Order: `Ascending`
4. Query scope: `Collection`
5. Click "Create"

**Status:** Wait for index to build (can take minutes to hours depending on collection size)
**Test:** Once built, test uncomplete/reset operations - they should work immediately

---

### Index 2: Category + Status Queries

1. Click "Add index" button
2. Collection ID: `activity_instances`
3. Add fields in this exact order:
   - Field: `templateCategoryType`, Order: `Ascending`
   - Field: `status`, Order: `Ascending`
   - Field: `windowEndDate`, Order: `Ascending`
   - Field: `dueDate`, Order: `Ascending`
4. Query scope: `Collection`
5. Click "Create"

---

### Index 3: Completion Queries

1. Click "Add index" button
2. Collection ID: `activity_instances`
3. Add fields in this exact order:
   - Field: `status`, Order: `Ascending`
   - Field: `completedAt`, Order: `Ascending`
4. Query scope: `Collection`
5. Click "Create"

---

### Index 4: Active Instance Queries

1. Click "Add index" button
2. Collection ID: `activity_instances`
3. Add fields in this exact order:
   - Field: `isActive`, Order: `Ascending`
   - Field: `templateId`, Order: `Ascending`
   - Field: `lastUpdated`, Order: `Descending`
4. Query scope: `Collection`
5. Click "Create"

---

## Index Creation Summary

| Index | Fields | Priority |
|-------|--------|----------|
| Index 1 | `templateId` + `status` + `belongsToDate` + `dueDate` | **CRITICAL** (fixes uncomplete issue) |
| Index 2 | `templateCategoryType` + `status` + `windowEndDate` + `dueDate` | High |
| Index 3 | `status` + `completedAt` | Medium |
| Index 4 | `isActive` + `templateId` + `lastUpdated` (DESC) | Medium |

## Testing Checklist

After Index 1 is built, test:
- [ ] Uncomplete/reset operations (long press → reset)
- [ ] Reset quantity operations
- [ ] Reset timer operations

After all indexes are built, test:
- [ ] Day-end processing
- [ ] Morning catchup
- [ ] Task instance creation
- [ ] Habit instance generation

## Monitoring

- Check Firestore Console → Indexes tab for build status
- Monitor for any index errors in Firebase Console
- Keep old indexes until new ones are verified working (1-2 weeks)

## Cleanup (After 1-2 Weeks)

Once all indexes are stable, you can remove redundant indexes:
- `CICAgNi470MK` (status, templateCategoryType, skippedAt) - if not used
- `CICAgJiUsZIK` (status, dueDate) - if not used
- Other indexes that become redundant

**Note:** Firestore will automatically use the most specific matching index, so old indexes won't interfere.

