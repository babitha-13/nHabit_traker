/**
 * Firebase Cloud Functions - Day-End Processing
 * Scheduled function that runs at midnight daily to process day-end activities for all users
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';

admin.initializeApp();

import { runInstanceMaintenanceForDayTransition } from './instanceMaintenance.js';
import { persistScoresForDate, persistScoresForMissedDaysIfNeeded } from './scorePersistence.js';
import { getYesterdayStart } from './types.js';

/**
 * Scheduled function that runs at midnight UTC every day
 * Processes day-end activities for users where it's midnight in their timezone:
 * 1. Instance maintenance (auto-skip expired habits, ensure instances exist, update lastDayValue)
 * 2. Score persistence (create daily progress records)
 * 3. Updates lastProcessedDate to track execution
 */
export const processDayEndForAllUsers = onSchedule(
  {
    schedule: '0 0 * * *', // Run at midnight UTC every day
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (event) => {
    console.log('Starting day-end processing for all users...');
    
    const currentUTCTime = new Date();
    const yesterday = getYesterdayStart();
    console.log(`Processing date: ${yesterday.toISOString()}`);
    console.log(`Current UTC time: ${currentUTCTime.toISOString()}`);
    
    try {
      // Get all users
      const usersSnapshot = await admin.firestore().collection('users').get();
      
      if (usersSnapshot.empty) {
        console.log('No users found. Exiting.');
        return;
      }
      
      console.log(`Found ${usersSnapshot.size} users to check`);
      
      // Process users in batches to avoid timeout
      const batchSize = 10;
      const users = usersSnapshot.docs;
      let processedCount = 0;
      let skippedCount = 0;
      let errorCount = 0;
      
      for (let i = 0; i < users.length; i += batchSize) {
        const batch = users.slice(i, i + batchSize);
        
        // Process batch in parallel
        const batchPromises = batch.map(async (userDoc) => {
          const userId = userDoc.id;
          const userData = userDoc.data();
          
          try {
            // Check if it's midnight in user's timezone
            const timezoneOffset = userData.timezone_offset as number | undefined;
            
            if (timezoneOffset === undefined || timezoneOffset === null) {
              // User timezone not set - skip (will be processed by UI fallback)
              skippedCount++;
              console.log(`Skipping user ${userId}: timezone not set`);
              return;
            }
            
            if (!isMidnightInUserTimezone(currentUTCTime, timezoneOffset)) {
              // Not midnight in user's timezone - skip
              skippedCount++;
              console.log(`Skipping user ${userId}: not midnight in timezone (offset: ${timezoneOffset})`);
              return;
            }
            
            console.log(`Processing user: ${userId} (timezone offset: ${timezoneOffset})`);
            
            // Step 1: Run instance maintenance
            await runInstanceMaintenanceForDayTransition(userId);
            
            // Step 2: Persist scores for yesterday (setLastProcessedDate: true to track execution)
            await persistScoresForDate(userId, yesterday, true);
            
            // Step 3: Create records for any missed days
            await persistScoresForMissedDaysIfNeeded(userId);
            
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
      
      console.log(`Day-end processing completed. Processed: ${processedCount}, Skipped: ${skippedCount}, Errors: ${errorCount}`);
      
      return;
    } catch (error) {
      console.error('Fatal error in day-end processing:', error);
      throw error;
    }
  }
);

/**
 * Check if current UTC time corresponds to midnight (00:00) in user's timezone
 * @param currentUTCTime Current UTC time
 * @param timezoneOffset Timezone offset in hours from UTC (e.g., 5.5 for IST, -5 for EST)
 * @returns true if it's midnight in user's timezone, false otherwise
 */
function isMidnightInUserTimezone(currentUTCTime: Date, timezoneOffset: number): boolean {
  // Convert UTC time to user's local time
  const userLocalTime = new Date(currentUTCTime.getTime() + (timezoneOffset * 60 * 60 * 1000));
  
  // Check if it's midnight (00:00) in user's local time
  const hours = userLocalTime.getUTCHours();
  const minutes = userLocalTime.getUTCMinutes();
  
  // Consider it midnight if hours is 0 and minutes is 0-5 (5 minute window for processing)
  return hours === 0 && minutes >= 0 && minutes <= 5;
}
