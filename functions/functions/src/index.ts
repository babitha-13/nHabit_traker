/**
 * Firebase Cloud Functions - Day-End Processing
 * Scheduled function that runs at midnight IST (18:30 UTC) daily
 * to process day-end activities for all users
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';

admin.initializeApp();

import { runInstanceMaintenanceForDayTransition } from './instanceMaintenance.js';
import { persistScoresForDate, persistScoresForDateRange, backfillRecentScores } from './scorePersistence.js';
import { getYesterdayStart } from './types.js';

/**
 * Scheduled function that runs at midnight IST (18:30 UTC) every day
 * Processes day-end activities for ALL users:
 * 1. Instance maintenance (auto-skip expired habits, ensure instances exist, update lastDayValue)
 * 2. Score persistence (create daily progress records)
 * 3. Updates lastProcessedDate to track execution
 */
export const processDayEndForAllUsers = onSchedule(
  {
    schedule: '30 18 * * *', // Run at 18:30 UTC = midnight IST every day
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (event) => {
    console.log('Starting day-end processing for all users (IST midnight)...');

    const currentUTCTime = new Date();
    const yesterday = getYesterdayStart();
    console.log(`Processing date (yesterday IST): ${yesterday.toISOString()}`);
    console.log(`Current UTC time: ${currentUTCTime.toISOString()}`);

    try {
      // Get all users
      const usersSnapshot = await admin.firestore().collection('users').get();

      if (usersSnapshot.empty) {
        console.log('No users found. Exiting.');
        return;
      }

      console.log(`Found ${usersSnapshot.size} users to process`);

      // Process users in batches to avoid timeout
      const batchSize = 10;
      const users = usersSnapshot.docs;
      let processedCount = 0;
      let errorCount = 0;

      for (let i = 0; i < users.length; i += batchSize) {
        const batch = users.slice(i, i + batchSize);

        // Process batch in parallel
        const batchPromises = batch.map(async (userDoc) => {
          const userId = userDoc.id;

          try {
            console.log(`Processing user: ${userId}`);

            // Step 1: Run instance maintenance
            await runInstanceMaintenanceForDayTransition(userId);

            // Step 2: Persist scores for yesterday (setLastProcessedDate: true to track execution)
            await persistScoresForDate(userId, yesterday, { setLastProcessedDate: true });

            processedCount++;
            console.log(`Completed processing for user: ${userId}`);
          } catch (error) {
            errorCount++;
            console.error(`Error processing user ${userId}:`, error);
            // Continue processing other users even if one fails
          }
        });

        // Wait for batch to complete
        await Promise.all(batchPromises);

        // Small delay between batches to avoid overwhelming Firestore
        if (i + batchSize < users.length) {
          await new Promise((resolve) => setTimeout(resolve, 1000));
        }
      }

      console.log(`Day-end processing completed. Processed: ${processedCount}, Errors: ${errorCount}`);

      return;
    } catch (error) {
      console.error('Fatal error in day-end processing:', error);
      throw error;
    }
  }
);

function parseDateInput(input: unknown, fieldName: string): Date {
  if (typeof input !== 'string') {
    throw new HttpsError('invalid-argument', `${fieldName} must be a YYYY-MM-DD string`);
  }
  const parsed = new Date(input);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpsError('invalid-argument', `${fieldName} is not a valid date`);
  }
  return parsed;
}

function resolveAuthorizedUser(authUid: string | undefined, requestedUserId: unknown): string {
  if (!authUid) {
    throw new HttpsError('unauthenticated', 'Authentication is required');
  }
  if (requestedUserId === undefined || requestedUserId === null || requestedUserId === '') {
    return authUid;
  }
  if (typeof requestedUserId !== 'string') {
    throw new HttpsError('invalid-argument', 'userId must be a string');
  }
  if (requestedUserId !== authUid) {
    throw new HttpsError('permission-denied', 'Cannot process scores for another user');
  }
  return requestedUserId;
}

export const finalizeDay = onCall(
  { timeoutSeconds: 120, memory: '256MiB' },
  async (request) => {
    try {
      const userId = resolveAuthorizedUser(request.auth?.uid, request.data?.userId);
      const date = parseDateInput(request.data?.date, 'date');
      const overwrite = request.data?.overwrite === true;

      await persistScoresForDate(userId, date, {
        overwrite,
        setLastProcessedDate: false,
        throwOnError: true,
      });

      return {
        ok: true,
        userId,
        date: date.toISOString(),
        overwrite,
      };
    } catch (error) {
      console.error('finalizeDay failed:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'finalizeDay failed', {
        error: String(error),
      });
    }
  }
);

export const runDayTransitionForUser = onCall(
  { timeoutSeconds: 180, memory: '256MiB' },
  async (request) => {
    try {
      const userId = resolveAuthorizedUser(request.auth?.uid, request.data?.userId);
      const date = parseDateInput(request.data?.date, 'date');

      await runInstanceMaintenanceForDayTransition(userId);
      await persistScoresForDate(userId, date, {
        overwrite: false,
        setLastProcessedDate: true,
        throwOnError: true,
      });

      return {
        ok: true,
        userId,
        date: date.toISOString(),
        processed: true,
      };
    } catch (error) {
      console.error('runDayTransitionForUser failed:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'runDayTransitionForUser failed', {
        error: String(error),
      });
    }
  }
);

export const recalculateRange = onCall(
  { timeoutSeconds: 540, memory: '512MiB' },
  async (request) => {
    try {
      const userId = resolveAuthorizedUser(request.auth?.uid, request.data?.userId);
      const fromDate = parseDateInput(request.data?.fromDate, 'fromDate');
      const toDate = parseDateInput(request.data?.toDate, 'toDate');

      await persistScoresForDateRange(userId, fromDate, toDate, {
        overwrite: true,
        setLastProcessedDate: false,
        throwOnError: true,
      });

      return {
        ok: true,
        userId,
        fromDate: fromDate.toISOString(),
        toDate: toDate.toISOString(),
      };
    } catch (error) {
      console.error('recalculateRange failed:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'recalculateRange failed', {
        error: String(error),
      });
    }
  }
);

export const backfillRecent = onCall(
  { timeoutSeconds: 540, memory: '512MiB' },
  async (request) => {
    try {
      const userId = resolveAuthorizedUser(request.auth?.uid, request.data?.userId);
      const requestedDays = Number(request.data?.days ?? 90);
      const days = Number.isFinite(requestedDays) ? requestedDays : 90;

      await backfillRecentScores(userId, days);

      return {
        ok: true,
        userId,
        days: Math.max(1, Math.min(365, Math.floor(days))),
      };
    } catch (error) {
      console.error('backfillRecent failed:', error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', 'backfillRecent failed', {
        error: String(error),
      });
    }
  }
);
