/**
 * Instance maintenance logic for day-end processing
 * Handles auto-skipping expired habits, ensuring instances exist, and updating lastDayValue
 */

import * as admin from 'firebase-admin';
import {
  ActivityInstance,
  ActivityRecord,
  getYesterdayStart,
  getTodayStart,
  normalizeToStartOfDay,
  timestampToDate,
  isSameDay,
} from './types.js';
import { logFirestoreIndexHint } from './firestoreIndexLogger.js';

const db = admin.firestore();

type PendingInstanceEntry = {
  instance: ActivityInstance;
  ref: admin.firestore.DocumentReference;
};

function stripUndefined<T extends Record<string, unknown>>(obj: T): Partial<T> {
  return Object.fromEntries(
    Object.entries(obj).filter(([, v]) => v !== undefined)
  ) as Partial<T>;
}

function dateKey(date: Date | null | undefined): string {
  if (!date) return 'null';
  const normalized = normalizeToStartOfDay(date);
  const year = normalized.getUTCFullYear().toString().padStart(4, '0');
  const month = (normalized.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = normalized.getUTCDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function buildHabitPendingDocId(templateId: string, belongsToDate: Date): string {
  const normalized = normalizeToStartOfDay(belongsToDate);
  const year = normalized.getUTCFullYear().toString().padStart(4, '0');
  const month = (normalized.getUTCMonth() + 1).toString().padStart(2, '0');
  const day = normalized.getUTCDate().toString().padStart(2, '0');
  return `habit_${templateId}_${year}${month}${day}`;
}

function pendingDedupKey(instance: ActivityInstance): string {
  return [
    instance.templateId,
    instance.status ?? 'pending',
    dateKey(timestampToDate(instance.dueDate)),
    dateKey(timestampToDate(instance.belongsToDate)),
    dateKey(timestampToDate(instance.windowEndDate)),
  ].join('|');
}

function asNumber(value: unknown): number {
  if (typeof value === 'number') return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function compareDateNullable(
  a: Date | null | undefined,
  b: Date | null | undefined
): number {
  if (!a && !b) return 0;
  if (!a) return -1;
  if (!b) return 1;
  return a.getTime() - b.getTime();
}

function shouldPreferPendingCandidate(
  candidate: PendingInstanceEntry,
  existing: PendingInstanceEntry
): boolean {
  const candidateProgress = asNumber(candidate.instance.currentValue);
  const existingProgress = asNumber(existing.instance.currentValue);
  if (candidateProgress !== existingProgress) {
    return candidateProgress > existingProgress;
  }

  const candidateTime = candidate.instance.totalTimeLogged ?? 0;
  const existingTime = existing.instance.totalTimeLogged ?? 0;
  if (candidateTime !== existingTime) {
    return candidateTime > existingTime;
  }

  const candidateUpdated = timestampToDate(candidate.instance.lastUpdated);
  const existingUpdated = timestampToDate(existing.instance.lastUpdated);
  const updatedCompare = compareDateNullable(candidateUpdated, existingUpdated);
  if (updatedCompare !== 0) {
    return updatedCompare > 0;
  }

  const candidateCreated = timestampToDate(candidate.instance.createdTime);
  const existingCreated = timestampToDate(existing.instance.createdTime);
  const createdCompare = compareDateNullable(candidateCreated, existingCreated);
  if (createdCompare !== 0) {
    return createdCompare > 0;
  }

  return candidate.ref.id > existing.ref.id;
}

async function cleanupDuplicatePendingEntries(
  entries: PendingInstanceEntry[]
): Promise<PendingInstanceEntry[]> {
  if (entries.length < 2) {
    return entries;
  }

  const grouped = new Map<string, PendingInstanceEntry[]>();
  for (const entry of entries) {
    const key = pendingDedupKey(entry.instance);
    const list = grouped.get(key) ?? [];
    list.push(entry);
    grouped.set(key, list);
  }

  const deduped: PendingInstanceEntry[] = [];
  const refsToDelete: admin.firestore.DocumentReference[] = [];

  for (const group of grouped.values()) {
    if (group.length === 1) {
      deduped.push(group[0]);
      continue;
    }

    let keep = group[0];
    for (let i = 1; i < group.length; i++) {
      const candidate = group[i];
      if (shouldPreferPendingCandidate(candidate, keep)) {
        keep = candidate;
      }
    }

    deduped.push(keep);
    for (const entry of group) {
      if (entry.ref.path !== keep.ref.path) {
        refsToDelete.push(entry.ref);
      }
    }
  }

  if (refsToDelete.length > 0) {
    let batch = db.batch();
    let opCount = 0;
    for (const ref of refsToDelete) {
      batch.delete(ref);
      opCount++;
      if (opCount >= 450) {
        await batch.commit();
        batch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      await batch.commit();
    }
  }

  return deduped;
}

/**
 * Run instance maintenance for day transition
 * This matches the logic from MorningCatchUpService.runInstanceMaintenanceForDayTransition
 */
export async function runInstanceMaintenanceForDayTransition(
  userId: string
): Promise<void> {
  const yesterday = getYesterdayStart();
  
  // Step 1: Auto-skip expired habits (2+ days before yesterday)
  await autoSkipExpiredHabitsBeforeYesterday(userId, yesterday);
  
  // Step 2: Ensure pending instances exist
  await ensurePendingInstancesExist(userId, yesterday);
  
  // Step 3: Update lastDayValue for active habits
  await updateLastDayValuesOnly(userId, yesterday);
}

/**
 * Auto-skip habits where window expired 2+ days before yesterday
 * If today is Thursday, yesterday is Wednesday, skip habits expired on Tuesday or earlier
 */
async function autoSkipExpiredHabitsBeforeYesterday(
  userId: string,
  yesterday: Date
): Promise<void> {
  try {
    // Calculate cutoff: 2 days before yesterday
    const cutoffDate = new Date(yesterday);
    // Removed erroneous -2 day offset
    const cutoffNormalized = normalizeToStartOfDay(cutoffDate);
    
    // Query habit instances where windowEndDate < cutoff (2+ days expired)
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');
    
    const expiredQuery = instancesRef
      .where('templateCategoryType', '==', 'habit')
      .where('status', '==', 'pending')
      .where('windowEndDate', '<', admin.firestore.Timestamp.fromDate(cutoffNormalized));
    
    const expiredSnapshot = await expiredQuery.get();
    
    if (expiredSnapshot.empty) {
      return;
    }
    
    // Process in batches
    let batch = db.batch();
    let batchCount = 0;
    const maxBatchSize = 249; // Each habit = 1 skip + 1 generate = 2 ops; stay under 500 limit

    for (const doc of expiredSnapshot.docs) {
      const instance = doc.data() as ActivityInstance;
      const windowEndDate = timestampToDate(instance.windowEndDate);

      if (!windowEndDate) continue;

      const windowEndNormalized = normalizeToStartOfDay(windowEndDate);

      // Only skip if window ended before cutoff (2+ days ago)
      if (windowEndNormalized < cutoffNormalized) {
        // Commit before adding if we're at the limit (skip+generate = 2 ops per habit)
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }

        // Mark as skipped
        batch.update(doc.ref, {
          status: 'skipped',
          skippedAt: admin.firestore.Timestamp.fromDate(windowEndNormalized),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });
        batchCount++;

        // Generate next instance (adds one more op to the batch)
        await generateNextInstance(instance, userId, batch);
        batchCount++;
      }
    }
    
    // Commit remaining updates
    if (batchCount > 0) {
      await batch.commit();
    }
  } catch (error) {
    logFirestoreIndexHint('instanceMaintenance.autoSkipExpiredHabitsBeforeYesterday', error);
    console.error(`Error auto-skipping expired habits for user ${userId}:`, error);
    // Don't throw - continue with other maintenance tasks
  }
}

/**
 * Ensure all active habits have at least one pending instance
 * Similar to DayEndProcessor.ensurePendingInstancesExist
 */
async function ensurePendingInstancesExist(
  userId: string,
  yesterday: Date
): Promise<void> {
  try {
    const today = getTodayStart();
    
    // Get all active habit templates
    const templatesRef = db
      .collection('users')
      .doc(userId)
      .collection('activities');
    
    const activeHabitsQuery = templatesRef
      .where('categoryType', '==', 'habit')
      .where('isActive', '==', true);
    
    const activeHabitsSnapshot = await activeHabitsQuery.get();
    
    if (activeHabitsSnapshot.empty) {
      return;
    }
    
    // Collect all template data and IDs
    const templates: Array<{ id: string; data: ActivityRecord }> = [];
    const templateIds: string[] = [];
    
    activeHabitsSnapshot.forEach((doc) => {
      templates.push({ id: doc.id, data: doc.data() as ActivityRecord });
      templateIds.push(doc.id);
    });
    
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');
    
    // Batch fetch pending instances for all templates using whereIn
    // Firestore whereIn limit is 10, so batch in groups of 10
    const pendingInstancesByTemplate = new Map<string, PendingInstanceEntry[]>();
    const mostRecentInstancesByTemplate = new Map<
      string,
      { instance: ActivityInstance; ref: admin.firestore.DocumentReference } | null
    >();
    
    const whereInBatchSize = 10;
    for (let i = 0; i < templateIds.length; i += whereInBatchSize) {
      const batchTemplateIds = templateIds.slice(i, i + whereInBatchSize);
      
      // Batch fetch pending instances for this group of templates
      const pendingQuery = instancesRef
        .where('templateId', 'in', batchTemplateIds)
        .where('status', '==', 'pending');
      
      const pendingSnapshot = await pendingQuery.get();
      
      // Group instances by templateId
      pendingSnapshot.forEach((doc) => {
        const instance = doc.data() as ActivityInstance;
        const templateId = instance.templateId;
        if (!pendingInstancesByTemplate.has(templateId)) {
          pendingInstancesByTemplate.set(templateId, []);
        }
        pendingInstancesByTemplate.get(templateId)!.push({
          instance,
          ref: doc.ref,
        });
      });
    }

    const getMostRecentInstanceForTemplate = async (
      templateId: string
    ): Promise<{ instance: ActivityInstance; ref: admin.firestore.DocumentReference } | null> => {
      if (mostRecentInstancesByTemplate.has(templateId)) {
        return mostRecentInstancesByTemplate.get(templateId) ?? null;
      }

      const allInstancesQuery = instancesRef
        .where('templateId', '==', templateId)
        .orderBy('windowEndDate', 'desc')
        .limit(1);
      const snapshot = await allInstancesQuery.get();

      if (snapshot.empty) {
        mostRecentInstancesByTemplate.set(templateId, null);
        return null;
      }

      const doc = snapshot.docs[0];
      const result = {
        instance: doc.data() as ActivityInstance,
        ref: doc.ref,
      };
      mostRecentInstancesByTemplate.set(templateId, result);
      return result;
    };
    
    // Process each template with pre-fetched instance data
    for (const { id: templateId, data: template } of templates) {
      const pendingEntries =
        await cleanupDuplicatePendingEntries(
          pendingInstancesByTemplate.get(templateId) || []
        );
      const pendingInstances = pendingEntries.map((entry) => entry.instance);
      
      // Filter to check if any belong to yesterday
      let hasYesterdayPending = false;
      for (const instance of pendingInstances) {
        const belongsToDate = timestampToDate(instance.belongsToDate);
        const windowEndDate = timestampToDate(instance.windowEndDate);
        
        if (belongsToDate && isSameDay(belongsToDate, yesterday)) {
          hasYesterdayPending = true;
          break;
        }
        if (windowEndDate && isSameDay(windowEndDate, yesterday)) {
          hasYesterdayPending = true;
          break;
        }
      }
      
      // If there's a pending instance for yesterday, don't generate today's instance
      if (hasYesterdayPending) {
        continue;
      }
      
      // Check if there's already a pending instance for today or future
      let hasTodayOrFuturePending = false;
      for (const instance of pendingInstances) {
        const belongsToDate = timestampToDate(instance.belongsToDate);
        const windowEndDate = timestampToDate(instance.windowEndDate);
        
        if (belongsToDate) {
          if (isSameDay(belongsToDate, today) || belongsToDate > today) {
            hasTodayOrFuturePending = true;
            break;
          }
        }
        if (windowEndDate) {
          if (isSameDay(windowEndDate, today) || windowEndDate > today) {
            hasTodayOrFuturePending = true;
            break;
          }
        }
      }
      
      // If there's already a pending instance for today/future, skip creation
      if (hasTodayOrFuturePending) {
        continue;
      }
      
      // No pending instance found - need to generate one
      const mostRecentData = await getMostRecentInstanceForTemplate(templateId);
      
      if (mostRecentData) {
        const mostRecentInstance = mostRecentData.instance;
        if (mostRecentInstance.windowEndDate) {
          const windowEndDate = timestampToDate(mostRecentInstance.windowEndDate);
          if (windowEndDate && windowEndDate < yesterday) {
            // Window ended before yesterday - skip the instance and generate next
            // Use pre-fetched document reference to avoid extra query
            await skipInstanceAndGenerateNext(
              mostRecentData.ref,
              mostRecentInstance,
              userId,
              windowEndDate
            );
          }
        }
      } else {
        // No instances at all - create initial instance
        await createInitialInstance(template, templateId, userId);
      }
    }
  } catch (error) {
    logFirestoreIndexHint('instanceMaintenance.ensurePendingInstancesExist', error);
    console.error(`Error ensuring pending instances for user ${userId}:`, error);
    // Don't throw - continue with other maintenance tasks
  }
}

/**
 * Update lastDayValue for active habits with open windows
 * Similar to DayEndProcessor.updateLastDayValuesOnly
 */
async function updateLastDayValuesOnly(
  userId: string,
  targetDate: Date
): Promise<void> {
  try {
    const normalizedDate = normalizeToStartOfDay(targetDate);
    
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');
    
    // Query active habit instances with windows that are still open
    const openWindowsQuery = instancesRef
      .where('templateCategoryType', '==', 'habit')
      .where('status', '==', 'pending')
      .where('windowEndDate', '>', admin.firestore.Timestamp.fromDate(normalizedDate));
    
    const openWindowsSnapshot = await openWindowsQuery.get();
    
    if (openWindowsSnapshot.empty) {
      return;
    }
    
    let batch = db.batch();
    let batchCount = 0;
    const maxBatchSize = 500;
    
    for (const doc of openWindowsSnapshot.docs) {
      const instance = doc.data() as ActivityInstance;
      
      // Update lastDayValue to current value for next day's differential calculation
      batch.update(doc.ref, {
        lastDayValue: instance.currentValue ?? 0,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      batchCount++;
      
      // Commit batch when it reaches max size and create a new one
      if (batchCount >= maxBatchSize) {
        await batch.commit();
        batch = db.batch(); // Create new batch after commit
        batchCount = 0;
      }
    }
    
    // Commit remaining updates
    if (batchCount > 0) {
      await batch.commit();
    }
  } catch (error) {
    logFirestoreIndexHint('instanceMaintenance.updateLastDayValuesOnly', error);
    console.error(`Error updating lastDayValue for user ${userId}:`, error);
    // Don't throw - this is a background operation
  }
}

/**
 * Generate next instance for a habit after skip
 */
async function generateNextInstance(
  instance: ActivityInstance,
  userId: string,
  batch: admin.firestore.WriteBatch
): Promise<void> {
  try {
    if (!instance.windowEndDate) return;
    
    const windowEndDate = timestampToDate(instance.windowEndDate);
    if (!windowEndDate) return;
    
    // Calculate next window start = current windowEndDate + 1
    const nextBelongsToDate = new Date(windowEndDate);
    nextBelongsToDate.setUTCDate(nextBelongsToDate.getUTCDate() + 1);
    const nextBelongsToDateNormalized = normalizeToStartOfDay(nextBelongsToDate);
    
    const windowDuration = instance.windowDuration ?? 1;
    const nextWindowEndDate = new Date(nextBelongsToDateNormalized);
    nextWindowEndDate.setUTCDate(nextWindowEndDate.getUTCDate() + windowDuration - 1);
    const nextWindowEndDateNormalized = normalizeToStartOfDay(nextWindowEndDate);
    
    // Check if instance already exists
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');
    
    const existingQuery = instancesRef
      .where('templateId', '==', instance.templateId)
      .where('belongsToDate', '==', admin.firestore.Timestamp.fromDate(nextBelongsToDateNormalized))
      .where('status', '==', 'pending');
    
    const existingSnapshot = await existingQuery.get();
    if (!existingSnapshot.empty) {
      return; // Instance already exists
    }
    
    // Create next instance data
    const nextInstanceData: Partial<ActivityInstance> = {
      templateId: instance.templateId,
      dueDate: admin.firestore.Timestamp.fromDate(nextBelongsToDateNormalized),
      dueTime: instance.templateDueTime,
      status: 'pending',
      createdTime: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      isActive: true,
      templateName: instance.templateName,
      templateCategoryId: instance.templateCategoryId,
      templateCategoryName: instance.templateCategoryName,
      templateCategoryType: instance.templateCategoryType,
      templatePriority: instance.templatePriority,
      templateTrackingType: instance.templateTrackingType,
      templateTarget: instance.templateTarget,
      templateUnit: instance.templateUnit,
      templateDescription: instance.templateDescription,
      templateTimeEstimateMinutes: instance.templateTimeEstimateMinutes,
      templateShowInFloatingTimer: instance.templateShowInFloatingTimer,
      templateIsRecurring: instance.templateIsRecurring,
      templateEveryXValue: instance.templateEveryXValue,
      templateEveryXPeriodType: instance.templateEveryXPeriodType,
      templateTimesPerPeriod: instance.templateTimesPerPeriod,
      templatePeriodType: instance.templatePeriodType,
      dayState: 'open',
      belongsToDate: admin.firestore.Timestamp.fromDate(nextBelongsToDateNormalized),
      windowEndDate: admin.firestore.Timestamp.fromDate(nextWindowEndDateNormalized),
      windowDuration: windowDuration,
      lastDayValue: 0,
    };
    
    // Add to batch using deterministic doc id to prevent duplicate pending docs
    const nextInstanceRef = instancesRef.doc(
      buildHabitPendingDocId(instance.templateId, nextBelongsToDateNormalized)
    );
    batch.set(nextInstanceRef, stripUndefined(nextInstanceData as Record<string, unknown>));
  } catch (error) {
    logFirestoreIndexHint('instanceMaintenance.generateNextInstance', error);
    console.error(`Error generating next instance:`, error);
    // Don't rethrow - don't want to fail the entire batch
  }
}

/**
 * Skip instance and generate next one
 */
async function skipInstanceAndGenerateNext(
  instanceRef: admin.firestore.DocumentReference,
  instance: ActivityInstance,
  userId: string,
  skippedAt: Date
): Promise<void> {
  const batch = db.batch();
  
  // Mark as skipped
  batch.update(instanceRef, {
    status: 'skipped',
    skippedAt: admin.firestore.Timestamp.fromDate(skippedAt),
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  });
  
  // Generate next instance
  await generateNextInstance(instance, userId, batch);
  
  await batch.commit();
}

/**
 * Create initial instance for a habit template
 */
async function createInitialInstance(
  template: ActivityRecord,
  templateId: string,
  userId: string
): Promise<void> {
  try {
    const today = getTodayStart();
    const windowDuration = 1; // Default to 1 day
    
    const windowEndDate = new Date(today);
    windowEndDate.setUTCDate(windowEndDate.getUTCDate() + windowDuration - 1);
    const windowEndDateNormalized = normalizeToStartOfDay(windowEndDate);
    
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');
    
    const instanceData: Partial<ActivityInstance> = {
      templateId: templateId,
      dueDate: admin.firestore.Timestamp.fromDate(today),
      dueTime: template.dueTime,
      status: 'pending',
      createdTime: admin.firestore.FieldValue.serverTimestamp(),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      isActive: true,
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: template.categoryType,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateTarget: template.target,
      templateUnit: template.unit,
      templateDescription: template.description,
      templateTimeEstimateMinutes: undefined,
      templateShowInFloatingTimer: template.showInFloatingTimer,
      templateIsRecurring: template.isRecurring,
      templateEveryXValue: template.everyXValue,
      templateEveryXPeriodType: template.everyXPeriodType,
      templateTimesPerPeriod: template.timesPerPeriod,
      templatePeriodType: template.periodType,
      dayState: 'open',
      belongsToDate: admin.firestore.Timestamp.fromDate(today),
      windowEndDate: admin.firestore.Timestamp.fromDate(windowEndDateNormalized),
      windowDuration: windowDuration,
      lastDayValue: 0,
    };
    
    const initialRef = instancesRef.doc(buildHabitPendingDocId(templateId, today));
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(initialRef);
      if (!existing.exists) {
        tx.set(initialRef, stripUndefined(instanceData as Record<string, unknown>));
      }
    });
  } catch (error) {
    console.error(`Error creating initial instance for template ${templateId}:`, error);
  }
}

/**
 * For each active habit, project what instances SHOULD have existed in [fromDate, toDate]
 * and write synthetic 'skipped' records for any that are missing.
 * Used to recover historical data after a system failure wiped pending instances.
 */
export async function createSyntheticSkippedInstances(
  userId: string,
  fromDate: Date,
  toDate: Date
): Promise<{ created: number; skipped: number }> {
  const normalizedFrom = normalizeToStartOfDay(fromDate);
  const normalizedTo = normalizeToStartOfDay(toDate);

  const templatesRef = db.collection('users').doc(userId).collection('activities');
  const instancesRef = db.collection('users').doc(userId).collection('activity_instances');

  const templatesSnapshot = await templatesRef
    .where('categoryType', '==', 'habit')
    .where('isActive', '==', true)
    .get();

  if (templatesSnapshot.empty) return { created: 0, skipped: 0 };

  let totalCreated = 0;
  let totalSkipped = 0;
  let batch = db.batch();
  let batchCount = 0;
  const maxBatchSize = 249;

  const commitBatch = async () => {
    if (batchCount > 0) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  };

  for (const templateDoc of templatesSnapshot.docs) {
    const template = templateDoc.data() as ActivityRecord;
    const templateId = templateDoc.id;

    // Find the most recent instance that ended BEFORE the recovery window starts.
    // This is the last instance before the gap — it gives us the correct windowDuration
    // and the right starting date to project forward from.
    const anchorQuery = instancesRef
      .where('templateId', '==', templateId)
      .where('windowEndDate', '<', admin.firestore.Timestamp.fromDate(normalizedFrom))
      .orderBy('windowEndDate', 'desc')
      .limit(1);

    const anchorSnapshot = await anchorQuery.get();

    let currentWindowEnd: Date;
    let windowDuration: number;

    if (!anchorSnapshot.empty) {
      const anchor = anchorSnapshot.docs[0].data() as ActivityInstance;
      const wEnd = timestampToDate(anchor.windowEndDate);
      if (!wEnd) continue;
      currentWindowEnd = normalizeToStartOfDay(wEnd);
      windowDuration = anchor.windowDuration ?? 1;
    } else {
      // No prior instance at all — start one day before the recovery window
      currentWindowEnd = new Date(normalizedFrom.getTime() - 24 * 60 * 60 * 1000);
      windowDuration = 1;
    }

    // Walk forward from the anchor, generating one window at a time
    let nextBelongsTo = normalizeToStartOfDay(
      new Date(currentWindowEnd.getTime() + 24 * 60 * 60 * 1000)
    );

    while (nextBelongsTo.getTime() <= normalizedTo.getTime()) {
      const nextWindowEnd = normalizeToStartOfDay(
        new Date(nextBelongsTo.getTime() + (windowDuration - 1) * 24 * 60 * 60 * 1000)
      );

      // Only create if this window overlaps the recovery range
      if (nextWindowEnd.getTime() >= normalizedFrom.getTime()) {
        const docId = `habit_recovery_${templateId}_${dateKey(nextBelongsTo)}`;
        const docRef = instancesRef.doc(docId);

        const existing = await docRef.get();
        if (existing.exists) {
          totalSkipped++;
        } else {
          const instanceData = stripUndefined({
            templateId,
            dueDate: admin.firestore.Timestamp.fromDate(nextBelongsTo),
            dueTime: template.dueTime,
            status: 'skipped',
            skippedAt: admin.firestore.Timestamp.fromDate(nextWindowEnd),
            createdTime: admin.firestore.FieldValue.serverTimestamp(),
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
            isActive: true,
            belongsToDate: admin.firestore.Timestamp.fromDate(nextBelongsTo),
            windowEndDate: admin.firestore.Timestamp.fromDate(nextWindowEnd),
            windowDuration,
            currentValue: 0,
            lastDayValue: 0,
            templateName: template.name,
            templateCategoryId: template.categoryId,
            templateCategoryName: template.categoryName,
            templateCategoryType: template.categoryType,
            templatePriority: template.priority,
            templateTrackingType: template.trackingType,
            templateTarget: template.target,
            templateUnit: template.unit,
            templateDescription: template.description,
            templateTimeEstimateMinutes: undefined,
            templateShowInFloatingTimer: template.showInFloatingTimer,
            templateIsRecurring: template.isRecurring,
            templateEveryXValue: template.everyXValue,
            templateEveryXPeriodType: template.everyXPeriodType,
            templateTimesPerPeriod: template.timesPerPeriod,
            templatePeriodType: template.periodType,
          } as Record<string, unknown>);

          batch.set(docRef, instanceData);
          batchCount++;
          totalCreated++;

          if (batchCount >= maxBatchSize) {
            await commitBatch();
          }
        }
      }

      // Advance to next window
      nextBelongsTo = normalizeToStartOfDay(
        new Date(nextWindowEnd.getTime() + 24 * 60 * 60 * 1000)
      );
    }
  }

  await commitBatch();
  return { created: totalCreated, skipped: totalSkipped };
}
