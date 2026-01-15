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
 * Processes day-end activities for all users:
 * 1. Instance maintenance (auto-skip expired habits, ensure instances exist, update lastDayValue)
 * 2. Score persistence (create daily progress records)
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
    
    const yesterday = getYesterdayStart();
    console.log(`Processing date: ${yesterday.toISOString()}`);
    
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
            
            // Step 2: Persist scores for yesterday
            await persistScoresForDate(userId, yesterday);
            
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
      
      console.log(`Day-end processing completed. Processed: ${processedCount}, Errors: ${errorCount}`);
      
      return;
    } catch (error) {
      console.error('Fatal error in day-end processing:', error);
      throw error;
    }
  }
);
