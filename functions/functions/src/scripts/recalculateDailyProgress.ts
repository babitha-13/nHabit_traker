/**
 * Recalculate all daily_progress records with correct scoring logic.
 *
 * This script IMPORTS the canonical scoring formulas from the cloud function's
 * scorePersistence module — no duplicated formula code.
 *
 * Steps:
 * 1. Iterates through all daily_progress records chronologically
 * 2. Recalculates scores using shared formulas
 * 3. Adds effectiveGain, previousDayCumulativeScore, and breakdown fields
 * 4. Updates cumulative score snapshots
 * 5. Resyncs users/{uid}/progress_stats/main slump/cumulative fields
 *
 * Usage:
 *   cd functions/functions
 *   npx tsc
 *   node lib/scripts/recalculateDailyProgress.js <userId>
 */

import * as admin from 'firebase-admin';
import * as path from 'path';

// Initialize Firebase Admin with service account BEFORE imports that might access Firestore.
// Note: scorePersistence.ts now uses lazy initialization (getDb()), so we are safe either way,
// but keeping this order is the most robust practice for standalone scripts.
const serviceAccountPath = path.resolve(__dirname, '../../../../serviceAccountKey.json');
// eslint-disable-next-line @typescript-eslint/no-var-requires
const serviceAccount = require(serviceAccountPath);

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
    });
}

import {
    calculateDailyScore,
    calculateConsistencyBonus,
    calculateRawDecayPenalty,
    calculateCombinedPenalty,
    calculateRecoveryBonus,
    calculateEffectiveGain,
} from '../scorePersistence.js';
import { DailyProgressRecord } from '../types.js';

const db = admin.firestore();

interface RecalcStatsSyncInput {
    userId: string;
    finalCumulativeScore: number;
    lastDailyGain: number;
    consecutiveLowDays: number;
    cumulativeLowStreakPenalty: number;
    totalDaysTracked: number;
    lastCalculationDate: Date;
}

async function syncProgressStatsAfterRecalc(input: RecalcStatsSyncInput): Promise<void> {
    const {
        userId,
        finalCumulativeScore,
        lastDailyGain,
        consecutiveLowDays,
        cumulativeLowStreakPenalty,
        totalDaysTracked,
        lastCalculationDate,
    } = input;

    const statsRef = db
        .collection(`users/${userId}/progress_stats`)
        .doc('main');

    const existingSnap = await statsRef.get();
    const existing = existingSnap.data() as Record<string, unknown> | undefined;
    const existingHistoricalHigh = Number(existing?.historicalHighScore || 0);
    const historicalHighScore = Math.max(existingHistoricalHigh, finalCumulativeScore);

    const baseData = {
        userId,
        cumulativeScore: finalCumulativeScore,
        lastDailyGain,
        consecutiveLowDays,
        cumulativeLowStreakPenalty,
        lastCalculationDate: admin.firestore.Timestamp.fromDate(lastCalculationDate),
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        historicalHighScore,
    };

    if (existingSnap.exists) {
        await statsRef.update(baseData);
        return;
    }

    await statsRef.set({
        ...baseData,
        totalDaysTracked,
        currentStreak: 0,
        longestStreak: 0,
        achievedMilestones: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/**
 * Recalculate daily progress for a user
 */
async function recalculateDailyProgress(userId: string) {
    console.log(`\n=== Recalculating daily_progress for user: ${userId} ===\n`);

    // Get all daily_progress records in chronological order
    const progressQuery = await db
        .collection(`users/${userId}/daily_progress`)
        .orderBy('date', 'asc')
        .get();

    if (progressQuery.empty) {
        console.log('No daily_progress records found.');
        return { updateCount: 0, finalCumulativeScore: 0 };
    }

    interface ProgressRecord {
        id: string;
        ref: FirebaseFirestore.DocumentReference;
        completionPercentage: number;
        earnedPoints: number;
        date?: FirebaseFirestore.Timestamp;
        [key: string]: unknown;
    }

    const allRecords: ProgressRecord[] = progressQuery.docs.map((doc) => {
        const data = doc.data() as Record<string, unknown>;
        return {
            id: doc.id,
            ref: doc.ref,
            completionPercentage: Number(data.completionPercentage || 0),
            earnedPoints: Number(data.earnedPoints || 0),
            date: data.date as FirebaseFirestore.Timestamp | undefined,
        };
    });

    console.log(`Found ${allRecords.length} records to recalculate.\n`);

    let cumulativeScore = 0.0;
    let consecutiveLowDays = 0;
    let cumulativeLowStreakPenalty = 0.0;
    let lastDailyGain = 0.0;
    let batch = db.batch();
    let batchCount = 0;
    let updateCount = 0;

    for (let i = 0; i < allRecords.length; i++) {
        const record = allRecords[i];
        const previousCumulativeScore = cumulativeScore;

        // Extract necessary fields (completionPercentage is 0-100 in Firestore)
        const completionPercentage = record.completionPercentage || 0;
        const earnedPoints = record.earnedPoints || 0;
        const categoryNeglectPenalty = Number(record.categoryNeglectPenalty || 0);

        // Calculate daily points using SHARED scoring formula
        const dailyPoints = calculateDailyScore(completionPercentage, earnedPoints);

        // Calculate consistency bonus using SHARED formula (need last 7 days)
        const startIndex = Math.max(0, i - 6);
        const last7Days = allRecords.slice(startIndex, i + 1) as unknown as DailyProgressRecord[];
        const consistencyBonus = calculateConsistencyBonus(last7Days);

        // Calculate decay/recovery using visible cumulative decline streak logic
        const prevDropDays = consecutiveLowDays;
        const prevLossPool = cumulativeLowStreakPenalty;
        const rawDecayPenalty = calculateRawDecayPenalty(completionPercentage);
        const preDiminishGain =
            dailyPoints + consistencyBonus - rawDecayPenalty - categoryNeglectPenalty;
        const penalty = preDiminishGain < 0
            ? calculateCombinedPenalty(completionPercentage, prevDropDays + 1)
            : rawDecayPenalty;

        const gainBeforeRecovery =
            dailyPoints + consistencyBonus - penalty - categoryNeglectPenalty;
        const endBeforeRecovery = Math.max(0, previousCumulativeScore + gainBeforeRecovery);
        const isSlumpDay = endBeforeRecovery < previousCumulativeScore;

        let recoveryBonus = 0.0;
        let newConsecutiveLowDays = prevDropDays;
        let newCumulativeLowStreakPenalty = prevLossPool;

        if (isSlumpDay) {
            const lossToday = previousCumulativeScore - endBeforeRecovery;
            newConsecutiveLowDays = prevDropDays + 1;
            newCumulativeLowStreakPenalty = prevLossPool + lossToday;
        } else {
            if (prevDropDays > 0 && prevLossPool > 0) {
                recoveryBonus = calculateRecoveryBonus(prevLossPool);
            }
            newConsecutiveLowDays = 0;
            newCumulativeLowStreakPenalty = 0.0;
        }

        // Calculate daily gain
        const dailyGain = gainBeforeRecovery + recoveryBonus;

        // Calculate new cumulative score (floor at 0)
        const newCumulativeScore = Math.max(0, previousCumulativeScore + dailyGain);

        // Calculate effective gain using SHARED formula
        const effectiveGain = calculateEffectiveGain(previousCumulativeScore, dailyGain, newCumulativeScore);

        // Update the record with all breakdown fields
        batch.update(record.ref, {
            dailyScoreGain: dailyGain,
            effectiveGain: effectiveGain,
            cumulativeScoreSnapshot: newCumulativeScore,
            dailyPoints: dailyPoints,
            consistencyBonus: consistencyBonus,
            recoveryBonus: recoveryBonus,
            decayPenalty: penalty,
            categoryNeglectPenalty: categoryNeglectPenalty,
            previousDayCumulativeScore: previousCumulativeScore,
        });

        batchCount++;
        updateCount++;

        // Log progress
        if (updateCount % 10 === 0 || updateCount === allRecords.length) {
            const dateStr = record.date?.toDate?.()?.toISOString?.()?.split('T')[0] || 'unknown';
            console.log(
                `[${updateCount}/${allRecords.length}] ${dateStr}: ` +
                `gain=${dailyGain.toFixed(2)}, ` +
                `effectiveGain=${effectiveGain.toFixed(2)}, ` +
                `cumulative=${newCumulativeScore.toFixed(2)}`
            );
        }

        // Commit batch every 500 operations (Firestore limit)
        if (batchCount >= 500) {
            await batch.commit();
            console.log(`  → Committed batch of ${batchCount} updates`);
            batch = db.batch();
            batchCount = 0;
        }

        // Update state for next iteration
        cumulativeScore = newCumulativeScore;
        consecutiveLowDays = newConsecutiveLowDays;
        cumulativeLowStreakPenalty = newCumulativeLowStreakPenalty;
        lastDailyGain = dailyGain;
    }

    // Commit any remaining updates
    if (batchCount > 0) {
        await batch.commit();
        console.log(`  → Committed final batch of ${batchCount} updates`);
    }

    console.log(`\n✅ Recalculation complete! Updated ${updateCount} records.\n`);
    console.log(`Final cumulative score: ${cumulativeScore.toFixed(2)}`);

    const lastCalculationDate = allRecords[allRecords.length - 1].date?.toDate?.() || new Date();
    await syncProgressStatsAfterRecalc({
        userId,
        finalCumulativeScore: cumulativeScore,
        lastDailyGain,
        consecutiveLowDays,
        cumulativeLowStreakPenalty,
        totalDaysTracked: allRecords.length,
        lastCalculationDate,
    });
    console.log('Resynced users/{uid}/progress_stats/main from recalculated history.');

    return { updateCount, finalCumulativeScore: cumulativeScore };
}

/**
 * Main execution
 */
async function main() {
    const userId = process.argv[2];

    if (!userId) {
        console.error('Usage: node lib/scripts/recalculateDailyProgress.js <userId>');
        process.exit(1);
    }

    try {
        const result = await recalculateDailyProgress(userId);
        console.log('\n=== Summary ===');
        console.log(`Records updated: ${result.updateCount}`);
        console.log(`Final cumulative score: ${result.finalCumulativeScore.toFixed(2)}`);
        console.log('\nNext step: Run backfillCumulativeHistory.js to update the cumulative_score_history document.');
    } catch (error) {
        console.error('Error during recalculation:', error);
        process.exit(1);
    } finally {
        process.exit(0);
    }
}

main();
