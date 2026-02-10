# Cloud Functions Performance Optimization Plan

## Overview
Optimize Firebase Cloud Functions to reduce Firestore reads, improve execution time, and fix bugs. Focus on batching queries, parallelizing sequential operations, and fixing async/await issues.

## Current Issues Identified

1. **Sequential Processing in `persistScoresForMissedDaysIfNeeded`**: Loops through missed days sequentially (line 898-902 in `scorePersistence.ts`)
2. **Individual Queries in `ensurePendingInstancesExist`**: Makes separate queries for each template (line 146-235 in `instanceMaintenance.ts`)
3. **Bug in `updateLastDayValuesOnly`**: `batch.commit()` not awaited inside forEach loop (line 286)
4. **Sequential Template Processing**: Processes templates one-by-one instead of batching

## Optimization Areas

### 1. Parallelize Missed Days Processing

**Location**: `functions/functions/src/scorePersistence.ts` (lines 854-909)

**Current Issue**: 
- Sequential loop: `for (let i = 1; i <= daysToProcess; i++)` calls `persistScoresForDate` one by one
- If 30 days are missed, makes 30 sequential calls

**Solution**:
- Process missed days in parallel batches (e.g., 5-10 at a time)
- Use `Promise.all()` to parallelize batches
- Add concurrency limit to avoid overwhelming Firestore

**Benefits**:
- 5-10x faster processing for multiple missed days
- Better resource utilization
- Reduces total execution time

**Files to Modify**:
- `functions/functions/src/scorePersistence.ts` - Update `persistScoresForMissedDaysIfNeeded()`

### 2. Batch Instance Queries in `ensurePendingInstancesExist`

**Location**: `functions/functions/src/instanceMaintenance.ts` (lines 118-240)

**Current Issue**:
- Loops through templates sequentially (line 146)
- Makes individual query for each template's pending instances (line 151-155)
- If user has 50 habits, makes 50+ individual queries

**Solution**:
- Collect all template IDs first
- Use `whereIn` query to batch fetch pending instances for all templates at once (Firestore limit: 10 templateIds per query, so batch in groups of 10)
- Process templates with pre-fetched instance data

**Benefits**:
- Reduces 50 queries to ~5 queries (90% reduction)
- Faster execution
- Lower Firestore read costs

**Files to Modify**:
- `functions/functions/src/instanceMaintenance.ts` - Update `ensurePendingInstancesExist()`

### 3. Fix Batch Commit Bug in `updateLastDayValuesOnly`

**Location**: `functions/functions/src/instanceMaintenance.ts` (lines 246-298)

**Current Issue**:
- Line 286: `batch.commit()` is called but not awaited inside `forEach` loop
- This causes race conditions and potential data loss
- Multiple batches may commit simultaneously, causing errors

**Solution**:
- Fix the batch commit logic to properly await commits
- Create new batch after each commit
- Ensure sequential batch commits

**Benefits**:
- Fixes critical bug preventing proper batch commits
- Ensures data consistency
- Prevents potential data loss

**Files to Modify**:
- `functions/functions/src/instanceMaintenance.ts` - Fix `updateLastDayValuesOnly()`

### 4. Optimize Instance Queries with whereIn

**Location**: `functions/functions/src/instanceMaintenance.ts` (lines 150-155, 208-213)

**Current Issue**:
- Individual queries for each template: `where('templateId', '==', templateId)`
- Can be batched using `whereIn` with up to 10 templateIds

**Solution**:
- Group template IDs into batches of 10
- Use `whereIn` queries to fetch instances for multiple templates at once
- Process results in memory to match templates to instances

**Benefits**:
- Reduces query count significantly
- Faster execution
- Lower Firestore costs

**Files to Modify**:
- `functions/functions/src/instanceMaintenance.ts` - Add batching helper and update queries

## Implementation Priority

1. **Critical Priority** (Bug Fix):
   - Fix batch commit bug in `updateLastDayValuesOnly()` (#3)

2. **High Priority** (Major Performance Impact):
   - Batch instance queries in `ensurePendingInstancesExist()` (#2)
   - Parallelize missed days processing (#1)

3. **Medium Priority** (Good Optimization):
   - Optimize instance queries with whereIn (#4)

## Expected Performance Improvements

- **Firestore Reads**: 70-85% reduction for users with many habits/templates
- **Execution Time**: 50-70% faster for users with missed days or many habits
- **Cost**: Significant reduction in Firestore read operations
- **Reliability**: Fixes critical batch commit bug

## Testing Considerations

- Test with users having 50+ active habits
- Test with users having 30+ missed days
- Test batch commit fix with large numbers of instances
- Verify whereIn queries work correctly (Firestore limit: 10 items)
- Ensure parallel processing doesn't cause race conditions
- Test error handling when batches fail

## Implementation Notes

- Firestore `whereIn` limit is 10 items - must batch accordingly
- Use `Promise.all()` for parallelization but limit concurrency
- Ensure proper error handling so one failure doesn't break entire batch
- Maintain idempotency - operations should be safe to retry
