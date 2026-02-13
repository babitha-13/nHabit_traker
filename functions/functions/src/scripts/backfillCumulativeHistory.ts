/**
 * Backfill cumulative_score_history document from daily_progress records.
 *
 * This script IMPORTS helpers from the cloud function's shared modules —
 * no duplicated formula code.
 *
 * Steps:
 * 1. Reads daily_progress records chronologically
 * 2. Computes contiguous score history (last N days)
 * 3. Writes to users/{uid}/cumulative_score_history/history
 *
 * Usage:
 *   cd functions/functions
 *   npx tsc
 *   node lib/scripts/backfillCumulativeHistory.js --serviceAccount "path/to/serviceAccount.json"
 *
 * Options:
 *   --serviceAccount  Path to Firebase service account JSON (required)
 *   --projectId       Firebase project ID (optional)
 *   --limitDays       Number of days of history (default: 100)
 *   --userId          Specific user ID (otherwise processes all users)
 */

import * as admin from 'firebase-admin';
import { formatDateKeyIST } from '../types.js';

function getArg(name: string, fallback: string | null = null): string | null {
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

const limitDays = Math.max(1, parseInt(limitDaysRaw!, 10) || 100);

// Initialize Admin SDK
// eslint-disable-next-line @typescript-eslint/no-var-requires
const serviceAccount = require(serviceAccountPath);
if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: projectId || serviceAccount.project_id,
    });
}

import { calculateEffectiveGain } from '../scorePersistence.js';

const db = admin.firestore();

function startOfDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date: Date, days: number): Date {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return startOfDay(d);
}

interface DailyRecord {
    date: Date;
    dailyScoreGain: number;
    cumulativeScoreSnapshot: number;
    effectiveGain: number | null;
    previousDayCumulativeScore: number | null;
}

async function fetchAllUsers(): Promise<string[]> {
    const snapshot = await db.collection('users').get();
    return snapshot.docs.map((doc) => doc.id);
}

async function fetchDailyProgress(userId: string): Promise<DailyRecord[]> {
    const snapshot = await db
        .collection('users')
        .doc(userId)
        .collection('daily_progress')
        .orderBy('date', 'asc')
        .get();

    return snapshot.docs
        .map((doc) => {
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
            } as DailyRecord;
        })
        .filter((r) => r.date);
}

interface HistoryEntry {
    date: Date;
    score: number;
    gain: number;
    effectiveGain: number;
}

function computeHistory(records: DailyRecord[], limitDaysCount: number): HistoryEntry[] {
    if (!records.length) return [];

    // Build map of records by day using IST-aware date key
    const recordByDay = new Map<string, DailyRecord>();
    for (const r of records) {
        const key = formatDateKeyIST(r.date);
        recordByDay.set(key, r);
    }

    const today = startOfDay(new Date());
    const start = addDays(today, -(limitDaysCount - 1));

    // Find baseline score before start date
    let lastKnownScore = 0;

    for (let i = records.length - 1; i >= 0; i--) {
        const r = records[i];
        if (r.date < start && r.cumulativeScoreSnapshot > 0) {
            lastKnownScore = r.cumulativeScoreSnapshot;
            break;
        }
    }

    if (lastKnownScore === 0) {
        const firstInRange = records.find((r) => r.date >= start);
        if (firstInRange && firstInRange.cumulativeScoreSnapshot > 0) {
            lastKnownScore = Math.max(
                0,
                firstInRange.cumulativeScoreSnapshot - firstInRange.dailyScoreGain
            );
        }
    }

    const history: HistoryEntry[] = [];
    let current = new Date(start);
    while (current <= today) {
        const key = formatDateKeyIST(current);
        const record = recordByDay.get(key);

        const previousScore = lastKnownScore;
        let gain = 0;
        let effGain = 0;

        if (record) {
            gain = Number(record.dailyScoreGain || 0);

            // Use stored effectiveGain if available, otherwise calculate using SHARED formula
            if (record.effectiveGain !== null && record.effectiveGain !== undefined) {
                effGain = Number(record.effectiveGain);
            } else {
                const prevScore = record.previousDayCumulativeScore !== null
                    ? Number(record.previousDayCumulativeScore)
                    : previousScore;
                const newScore = record.cumulativeScoreSnapshot > 0
                    ? record.cumulativeScoreSnapshot
                    : Math.max(0, prevScore + gain);
                effGain = calculateEffectiveGain(prevScore, gain, newScore);
            }

            if (record.cumulativeScoreSnapshot > 0) {
                lastKnownScore = record.cumulativeScoreSnapshot;
            } else {
                lastKnownScore = Math.max(0, lastKnownScore + gain);
            }
        }

        history.push({
            date: new Date(current),
            score: lastKnownScore,
            gain,
            effectiveGain: effGain,
        });

        current = addDays(current, 1);
    }

    return history;
}

async function writeHistory(userId: string, history: HistoryEntry[]) {
    const docRef = db
        .collection('users')
        .doc(userId)
        .collection('cumulative_score_history')
        .doc('history');

    const scoresWithTimestamps = history.map((entry) => ({
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
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.error(`[${userId}] Failed:`, msg);
        }
    }
}

main()
    .then(() => {
        console.log('Backfill completed.');
        process.exit(0);
    })
    .catch((err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err);
        console.error('Backfill failed:', msg);
        process.exit(1);
    });
