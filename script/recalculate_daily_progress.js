/**
 * Recalculate all daily_progress records with correct logic
 * This script:
 * 1. Iterates through all daily_progress records chronologically
 * 2. Recalculates scores using the correct formula
 * 3. Adds the effectiveGain field
 * 4. Updates cumulative score snapshots
 */

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Score calculation constants (must match score_formulas.dart exactly)
const SCORE_FORMULAS = {
  basePointsPerDay: 10.0,
  consistencyThreshold: 0.8,
  decayThreshold: 0.5,
  penaltyBaseMultiplier: 0.04,
  categoryNeglectPenalty: 0.4,
  consistencyBonusFull: 5.0,
  consistencyBonusPartial: 2.0,
};

/**
 * Calculate daily score from completion percentage and points earned
 * Matches score_formulas.dart calculateDailyScore()
 */
function calculateDailyScore(completionPercentage, rawPointsEarned) {
  // Percentage component (max 10 points)
  const percentageComponent = (completionPercentage / 100.0) * SCORE_FORMULAS.basePointsPerDay;
  
  // Raw points bonus using square root scaling divided by 2
  const rawPointsBonus = Math.sqrt(rawPointsEarned) / 2.0;
  
  // Combined score (no cap)
  return percentageComponent + rawPointsBonus;
}

/**
 * Calculate consistency bonus based on last 7 days
 * Matches score_formulas.dart calculateConsistencyBonus()
 */
function calculateConsistencyBonus(last7Days) {
  if (last7Days.length < 7) return 0.0;

  // consistencyThreshold is 0.8 (80%), completionPercentage is stored as 0-100
  const highPerformanceDays = last7Days.filter(
    (day) => day.completionPercentage >= SCORE_FORMULAS.consistencyThreshold * 100
  ).length;

  if (highPerformanceDays === 7) {
    return SCORE_FORMULAS.consistencyBonusFull;
  } else if (highPerformanceDays >= 5) {
    return SCORE_FORMULAS.consistencyBonusPartial;
  }
  return 0.0;
}

/**
 * Calculate combined penalty for poor performance with diminishing returns over time
 * Matches score_formulas.dart calculateCombinedPenalty()
 */
function calculateCombinedPenalty(completionPercentage, consecutiveLowDays) {
  if (completionPercentage >= SCORE_FORMULAS.decayThreshold * 100) return 0.0;
  
  // Combined penalty with diminishing returns over time
  // Formula: (50 - completion%) * 0.04 / log(consecutiveDays + 1)
  const pointsBelowThreshold = (SCORE_FORMULAS.decayThreshold * 100) - completionPercentage;
  const penalty = pointsBelowThreshold * 
                  SCORE_FORMULAS.penaltyBaseMultiplier / 
                  Math.log(consecutiveLowDays + 1);
  
  return penalty;
}

/**
 * Calculate recovery bonus when breaking low-completion streak
 * Matches score_formulas.dart calculateRecoveryBonus()
 */
function calculateRecoveryBonus(previousConsecutiveLowDays) {
  if (previousConsecutiveLowDays === 0) return 0.0;
  
  // Recovery bonus when breaking low-completion streak
  // Capped at 5 points to ensure < 50% of typical penalties
  // Formula: min(5, sqrt(consecutiveLowDays) * 1.0)
  const bonus = Math.sqrt(previousConsecutiveLowDays) * 1.0;
  return Math.min(5.0, bonus);
}

/**
 * Calculate effective gain (actual change in cumulative score)
 */
function calculateEffectiveGain(previousScore, actualGain, newScore) {
  return newScore - previousScore;
}

/**
 * Recalculate daily progress for a user
 */
async function recalculateDailyProgress(userId) {
  console.log(`\n=== Recalculating daily_progress for user: ${userId} ===\n`);

  // Get all daily_progress records in chronological order
  const progressQuery = await db
    .collection(`users/${userId}/daily_progress`)
    .orderBy('date', 'asc')
    .get();

  if (progressQuery.empty) {
    console.log('No daily_progress records found.');
    return;
  }

  const allRecords = progressQuery.docs.map((doc) => ({
    id: doc.id,
    ref: doc.ref,
    ...doc.data(),
  }));

  console.log(`Found ${allRecords.length} records to recalculate.\n`);

  let cumulativeScore = 0.0;
  let consecutiveLowDays = 0;
  const batch = db.batch();
  let batchCount = 0;
  let updateCount = 0;

  for (let i = 0; i < allRecords.length; i++) {
    const record = allRecords[i];
    const previousCumulativeScore = cumulativeScore;

    // Extract necessary fields
    // completionPercentage is stored as 0-100 in Firestore
    const completionPercentage = record.completionPercentage || 0;
    const earnedPoints = record.earnedPoints || 0;
    const categoryNeglectPenalty = 0; // Not stored in daily_progress, assume 0 for recalc

    // Calculate daily points (base score)
    const dailyPoints = calculateDailyScore(completionPercentage, earnedPoints);

    // Calculate consistency bonus (need last 7 days)
    const startIndex = Math.max(0, i - 6);
    const last7Days = allRecords.slice(startIndex, i + 1);
    const consistencyBonus = calculateConsistencyBonus(last7Days);

    // Calculate penalty/recovery bonus based on completion
    let penalty = 0.0;
    let recoveryBonus = 0.0;
    let newConsecutiveLowDays = consecutiveLowDays;

    // Compare with threshold (50% = 50.0)
    if (completionPercentage < SCORE_FORMULAS.decayThreshold * 100) {
      // Completion < 50%: increment counter and apply penalty
      newConsecutiveLowDays = consecutiveLowDays + 1;
      penalty = calculateCombinedPenalty(completionPercentage, newConsecutiveLowDays);
    } else {
      // Completion >= 50%: calculate recovery bonus and reset counter
      if (consecutiveLowDays > 0) {
        recoveryBonus = calculateRecoveryBonus(consecutiveLowDays);
      }
      newConsecutiveLowDays = 0;
    }

    // Calculate daily gain
    const dailyGain = dailyPoints + consistencyBonus + recoveryBonus - penalty - categoryNeglectPenalty;

    // Calculate new cumulative score (floor at 0)
    const newCumulativeScore = Math.max(0, previousCumulativeScore + dailyGain);

    // Calculate effective gain
    const effectiveGain = calculateEffectiveGain(previousCumulativeScore, dailyGain, newCumulativeScore);

    // Update the record with all breakdown fields
    batch.update(record.ref, {
      dailyScoreGain: dailyGain,
      effectiveGain: effectiveGain,
      cumulativeScoreSnapshot: newCumulativeScore,
      // Add breakdown fields
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
      batchCount = 0;
    }

    // Update state for next iteration
    cumulativeScore = newCumulativeScore;
    consecutiveLowDays = newConsecutiveLowDays;
  }

  // Commit any remaining updates
  if (batchCount > 0) {
    await batch.commit();
    console.log(`  → Committed final batch of ${batchCount} updates`);
  }

  console.log(`\n✅ Recalculation complete! Updated ${updateCount} records.\n`);
  console.log(`Final cumulative score: ${cumulativeScore.toFixed(2)}`);

  return { updateCount, finalCumulativeScore: cumulativeScore };
}

/**
 * Main execution
 */
async function main() {
  const userId = process.argv[2];

  if (!userId) {
    console.error('Usage: node recalculate_daily_progress.js <userId>');
    process.exit(1);
  }

  try {
    const result = await recalculateDailyProgress(userId);
    console.log('\n=== Summary ===');
    console.log(`Records updated: ${result.updateCount}`);
    console.log(`Final cumulative score: ${result.finalCumulativeScore.toFixed(2)}`);
    console.log('\nNext step: Run backfill_cumulative_history.js to update the cumulative_score_history document.');
  } catch (error) {
    console.error('Error during recalculation:', error);
    process.exit(1);
  } finally {
    process.exit(0);
  }
}

main();
