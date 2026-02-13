/**
 * Migration script: Convert daily_progress records to use date-based document IDs.
 *
 * This script IMPORTS formatDateKeyIST from the cloud function's shared types module
 * to ensure IST-consistent YYYY-MM-DD document IDs.
 *
 * Steps:
 * 1. Reads all existing daily_progress records
 * 2. Creates new documents with date-based IDs (YYYY-MM-DD in IST)
 * 3. Copies all data to the new documents
 * 4. Optionally deletes old documents
 *
 * Usage:
 *   cd functions/functions
 *   npx tsc
 *   node lib/scripts/migrateDailyProgressToDateIds.js <userId> [--delete-old]
 */

import * as admin from 'firebase-admin';
import * as path from 'path';

// Initialize Firebase Admin with service account
const serviceAccountPath = path.resolve(__dirname, '../../../../serviceAccountKey.json');
// eslint-disable-next-line @typescript-eslint/no-var-requires
const serviceAccount = require(serviceAccountPath);

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
    });
}

import { formatDateKeyIST } from '../types.js';

const db = admin.firestore();

// Configuration
const DELETE_OLD_DOCUMENTS = process.argv.includes('--delete-old');

/**
 * Format date as YYYY-MM-DD for document ID using IST-aware shared function
 */
function formatDateAsDocId(date: unknown): string | null {
    if (!date) return null;

    let jsDate: Date;
    if (date && typeof date === 'object' && 'toDate' in date && typeof (date as { toDate: () => Date }).toDate === 'function') {
        jsDate = (date as { toDate: () => Date }).toDate();
    } else if (date instanceof Date) {
        jsDate = date;
    } else {
        return null;
    }

    // Use shared IST-aware formatting
    return formatDateKeyIST(jsDate);
}

/**
 * Check if document ID is date-based (YYYY-MM-DD format)
 */
function isDateBasedId(docId: string): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(docId);
}

/**
 * Migrate daily_progress records for a user
 */
async function migrateDailyProgress(userId: string) {
    console.log(`\n=== Migrating daily_progress records for user: ${userId} ===\n`);
    console.log(`Delete old documents: ${DELETE_OLD_DOCUMENTS ? 'YES' : 'NO (dry-run mode)'}\n`);

    const progressRef = db
        .collection('users')
        .doc(userId)
        .collection('daily_progress');

    const snapshot = await progressRef.get();

    if (snapshot.empty) {
        console.log('No daily_progress records found.');
        return { migrated: 0, skipped: 0, errors: 0, deleted: 0 };
    }

    console.log(`Found ${snapshot.size} records to process.\n`);

    let migrated = 0;
    let skipped = 0;
    let errors = 0;
    let deleted = 0;
    let batch = db.batch();
    let batchCount = 0;
    const oldDocRefs: FirebaseFirestore.DocumentReference[] = [];

    for (const doc of snapshot.docs) {
        try {
            const data = doc.data();
            const date = data.date;

            if (!date) {
                console.log(`⚠️  Skipping document ${doc.id}: missing date field`);
                skipped++;
                continue;
            }

            const dateDocId = formatDateAsDocId(date);

            if (!dateDocId) {
                console.log(`⚠️  Skipping document ${doc.id}: invalid date format`);
                skipped++;
                continue;
            }

            // Already has correct date-based ID
            if (doc.id === dateDocId) {
                skipped++;
                continue;
            }

            // Check if target document already exists
            const targetDocRef = progressRef.doc(dateDocId);
            const targetDoc = await targetDocRef.get();

            if (targetDoc.exists) {
                if (!isDateBasedId(doc.id)) {
                    if (DELETE_OLD_DOCUMENTS) {
                        oldDocRefs.push(doc.ref);
                        if (oldDocRefs.length % 50 === 0 || oldDocRefs.length === 1) {
                            console.log(`🗑️  Marked ${oldDocRefs.length} old documents for deletion...`);
                        }
                    } else {
                        if (skipped < 10) {
                            console.log(`⚠️  Target ${dateDocId} exists, old doc ${doc.id} would be deleted`);
                        }
                    }
                }
                skipped++;
                continue;
            }

            // Create new document with date-based ID
            batch.set(targetDocRef, data, { merge: true });
            batchCount++;
            migrated++;

            if (DELETE_OLD_DOCUMENTS) {
                oldDocRefs.push(doc.ref);
            }

            if (migrated % 10 === 0) {
                console.log(`  [${migrated} migrated] ${doc.id} → ${dateDocId}`);
            }

            // Commit batch every 500 operations
            if (batchCount >= 500) {
                await batch.commit();
                console.log(`  → Committed batch of ${batchCount} migrations`);
                batch = db.batch();
                batchCount = 0;
            }
        } catch (error: unknown) {
            const msg = error instanceof Error ? error.message : String(error);
            console.error(`❌ Error migrating document ${doc.id}:`, msg);
            errors++;
        }
    }

    // Commit remaining migrations
    if (batchCount > 0) {
        await batch.commit();
        console.log(`  → Committed final batch of ${batchCount} migrations`);
    }

    // Delete old documents if requested
    if (DELETE_OLD_DOCUMENTS && oldDocRefs.length > 0) {
        console.log(`\n🗑️  Deleting ${oldDocRefs.length} old documents...`);
        let batchNum = 1;
        while (oldDocRefs.length > 0) {
            const deleteBatch = db.batch();
            const toDelete = oldDocRefs.splice(0, 500);
            for (const oldRef of toDelete) {
                deleteBatch.delete(oldRef);
            }
            await deleteBatch.commit();
            deleted += toDelete.length;
            console.log(`  → Batch ${batchNum}: Deleted ${toDelete.length} old documents (${deleted} total)`);
            batchNum++;
        }
        console.log(`✅ Successfully deleted ${deleted} old documents`);
    }

    console.log(`\n=== Migration Complete ===`);
    console.log(`✓  Migrated: ${migrated} records`);
    console.log(`⊘  Skipped: ${skipped} records`);
    console.log(`❌ Errors: ${errors} records`);
    if (DELETE_OLD_DOCUMENTS) {
        console.log(`🗑️  Deleted: ${deleted} old documents`);
    } else {
        console.log(`\n⚠️  Old documents NOT deleted (dry-run mode)`);
        console.log(`   Run with --delete-old flag to delete old documents`);
    }

    return { migrated, skipped, errors, deleted };
}

/**
 * Main execution
 */
async function main() {
    const userId = process.argv[2];

    if (!userId || userId.startsWith('--')) {
        console.error('Usage: node lib/scripts/migrateDailyProgressToDateIds.js <userId> [--delete-old]');
        console.error('');
        console.error('Options:');
        console.error('  --delete-old    Delete old documents after migration');
        process.exit(1);
    }

    try {
        if (!DELETE_OLD_DOCUMENTS) {
            console.log('⚠️  DRY-RUN MODE: Old documents will NOT be deleted');
            console.log('   Add --delete-old flag to actually delete old documents\n');
        }

        const result = await migrateDailyProgress(userId);

        console.log('\n=== Summary ===');
        console.log(`Records migrated: ${result.migrated}`);
        console.log(`Records skipped: ${result.skipped}`);
        console.log(`Errors: ${result.errors}`);
        if (DELETE_OLD_DOCUMENTS) {
            console.log(`Old documents deleted: ${result.deleted}`);
        }

        if (result.migrated > 0) {
            console.log('\n✅ Migration successful!');
            if (!DELETE_OLD_DOCUMENTS) {
                console.log('\n💡 Tip: Review the migrated records, then run again with --delete-old to clean up.');
            }
        } else if (result.skipped > 0) {
            console.log('\n✅ All records already migrated or skipped.');
        }
    } catch (error) {
        console.error('❌ Error during migration:', error);
        process.exit(1);
    } finally {
        process.exit(0);
    }
}

main();
