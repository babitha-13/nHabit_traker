// One-time backfill for users/{uid}/cumulative_score_history/history
// Usage:
//   node script/backfill_cumulative_history.js --serviceAccount "C:\path\to\serviceAccount.json"
// Optional:
//   --projectId "your-project-id"
//   --limitDays 100
//   --userId "specificUserId" (otherwise processes all users)
//
// Notes:
// - Writes last N days (default 100) of contiguous daily history
// - Uses daily_progress records to compute score + gain per day

const admin = require('firebase-admin');

function getArg(name, fallback = null) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1 || index + 1 >= process.argv.length) return fallback;
  return process.argv[index + 1];
}

const serviceAccountPath = getArg('serviceAccount');
const projectId = getArg('projectId');
const limitDaysRaw = getArg('limitDays', '100');
const userIdFilter = getArg('userId');

if (!serviceAccountPath) {
  console.error('Missing --serviceAccount "path/to/serviceAccount.json"');
  process.exit(1);
}

const limitDays = Math.max(1, parseInt(limitDaysRaw, 10) || 100);

// Initialize Admin SDK
const serviceAccount = require(serviceAccountPath);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: projectId || serviceAccount.project_id,
});

const db = admin.firestore();

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return startOfDay(d);
}

function toDateKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function calculateEffectiveGain(previousScore, actualGain, newScore) {
  // Effective gain is simply the actual change in score
  // This automatically accounts for the floor at 0
  return newScore - previousScore;
}

async function fetchAllUsers() {
  const snapshot = await db.collection('users').get();
  return snapshot.docs.map((doc) => doc.id);
}

async function fetchDailyProgress(userId) {
  const snapshot = await db
    .collection('users')
    .doc(userId)
    .collection('daily_progress')
    .orderBy('date', 'asc')
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const date = data.date && data.date.toDate ? data.date.toDate() : null;
    return {
      date,
      dailyScoreGain: Number(data.dailyScoreGain || 0),
      cumulativeScoreSnapshot: Number(data.cumulativeScoreSnapshot || 0),
      effectiveGain: data.effectiveGain !== undefined ? Number(data.effectiveGain) : null,
      previousDayCumulativeScore: data.previousDayCumulativeScore !== undefined 
        ? Number(data.previousDayCumulativeScore) 
        : null,
    };
  }).filter((r) => r.date);
}

function computeHistory(records, limitDaysCount) {
  if (!records.length) return [];

  // Build map of records by day
  const recordByDay = new Map();
  for (const r of records) {
    const day = startOfDay(r.date);
    recordByDay.set(toDateKey(day), r);
  }

  const today = startOfDay(new Date());
  const start = addDays(today, -(limitDaysCount - 1));

  // Find baseline score before start date
  let lastKnownScore = 0;

  // Try to find the latest record before start date with snapshot
  for (let i = records.length - 1; i >= 0; i--) {
    const r = records[i];
    if (r.date < start && r.cumulativeScoreSnapshot > 0) {
      lastKnownScore = r.cumulativeScoreSnapshot;
      break;
    }
  }

  // If still zero, use first record in range if it has snapshot
  if (lastKnownScore === 0) {
    const firstInRange = records.find((r) => r.date >= start);
    if (firstInRange && firstInRange.cumulativeScoreSnapshot > 0) {
      lastKnownScore = Math.max(
        0,
        firstInRange.cumulativeScoreSnapshot - firstInRange.dailyScoreGain
      );
    }
  }

  const history = [];
  let current = new Date(start);
  while (current <= today) {
    const key = toDateKey(current);
    const record = recordByDay.get(key);

    const previousScore = lastKnownScore;
    let gain = 0;
    let effectiveGain = 0;
    
    if (record) {
      gain = Number(record.dailyScoreGain || 0);
      
      // Use stored effectiveGain if available, otherwise calculate it
      if (record.effectiveGain !== null && record.effectiveGain !== undefined) {
        effectiveGain = Number(record.effectiveGain);
      } else {
        // Calculate effective gain from cumulative scores
        // Use previousDayCumulativeScore if available, otherwise use our tracked lastKnownScore
        const prevScore = record.previousDayCumulativeScore !== null 
          ? Number(record.previousDayCumulativeScore)
          : previousScore;
        const newScore = record.cumulativeScoreSnapshot > 0 
          ? record.cumulativeScoreSnapshot
          : Math.max(0, prevScore + gain);
        effectiveGain = calculateEffectiveGain(prevScore, gain, newScore);
      }
      
      if (record.cumulativeScoreSnapshot > 0) {
        lastKnownScore = record.cumulativeScoreSnapshot;
      } else {
        lastKnownScore = Math.max(0, lastKnownScore + gain);
      }
    } else {
      // No record for this day; carry forward score with 0 gain
      gain = 0;
      effectiveGain = 0;
    }

    history.push({
      date: new Date(current),
      score: lastKnownScore,
      gain,
      effectiveGain,
    });

    current = addDays(current, 1);
  }

  return history;
}

async function writeHistory(userId, history) {
  const docRef = db
    .collection('users')
    .doc(userId)
    .collection('cumulative_score_history')
    .doc('history');
  
  // Convert date objects to Firestore Timestamps
  const scoresWithTimestamps = history.map(entry => ({
    date: admin.firestore.Timestamp.fromDate(entry.date),
    score: entry.score,
    gain: entry.gain,
    effectiveGain: entry.effectiveGain,
  }));
  
  await docRef.set(
    {
      scores: scoresWithTimestamps,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function main() {
  const userIds = userIdFilter ? [userIdFilter] : await fetchAllUsers();
  console.log(`Processing ${userIds.length} user(s)...`);

  for (const userId of userIds) {
    try {
      const records = await fetchDailyProgress(userId);
      if (!records.length) {
        console.log(`[${userId}] No daily_progress records. Skipping.`);
        continue;
      }

      const history = computeHistory(records, limitDays);
      await writeHistory(userId, history);
      console.log(
        `[${userId}] Wrote ${history.length} day(s) to cumulative_score_history.`
      );
    } catch (err) {
      console.error(`[${userId}] Failed:`, err.message || err);
    }
  }
}

main()
  .then(() => {
    console.log('Backfill completed.');
    process.exit(0);
  })
  .catch((err) => {
    console.error('Backfill failed:', err.message || err);
    process.exit(1);
  });
