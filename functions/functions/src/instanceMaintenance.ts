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
    cutoffDate.setUTCDate(cutoffDate.getUTCDate() - 2);
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
    const maxBatchSize = 500;
    
    for (const doc of expiredSnapshot.docs) {
      const instance = doc.data() as ActivityInstance;
      const windowEndDate = timestampToDate(instance.windowEndDate);
      
      if (!windowEndDate) continue;
      
      const windowEndNormalized = normalizeToStartOfDay(windowEndDate);
      
      // Only skip if window ended before cutoff (2+ days ago)
      if (windowEndNormalized < cutoffNormalized) {
        // Mark as skipped
        batch.update(doc.ref, {
          status: 'skipped',
          skippedAt: admin.firestore.Timestamp.fromDate(windowEndNormalized),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        batchCount++;
        
        // Generate next instance
        await generateNextInstance(instance, userId, batch);
        
        // Commit batch if it reaches max size and create a new one
        if (batchCount >= maxBatchSize) {
          await batch.commit();
          batch = db.batch(); // Create new batch after commit
          batchCount = 0;
        }
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
    const pendingInstancesByTemplate = new Map<string, ActivityInstance[]>();
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
        pendingInstancesByTemplate.get(templateId)!.push(instance);
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
    }
    
    // Process each template with pre-fetched instance data
    for (const { id: templateId, data: template } of templates) {
      const pendingInstances = pendingInstancesByTemplate.get(templateId) || [];
      
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
    
    // Add to batch
    const nextInstanceRef = instancesRef.doc();
    batch.set(nextInstanceRef, nextInstanceData);
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
    
    await instancesRef.add(instanceData);
  } catch (error) {
    console.error(`Error creating initial instance for template ${templateId}:`, error);
  }
}
