/**
 * Migration script: Convert daily_progress records to use date-based document IDs
 * 
 * This script:
 * 1. Reads all existing daily_progress records (with auto-generated IDs)
 * 2. Creates new documents with date-based IDs (YYYY-MM-DD format)
 * 3. Copies all data to the new documents
 * 4. Optionally deletes old documents (controlled by DELETE_OLD flag)
 * 
 * Usage: node migrate_daily_progress_to_date_ids.js <userId> [--delete-old]
 */

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Configuration
const DELETE_OLD_DOCUMENTS = process.argv.includes('--delete-old');

/**
 * Format date as YYYY-MM-DD for document ID
 */
function formatDateAsDocId(date) {
  if (!date) return null;
  
  // Handle Firestore Timestamp
  let jsDate;
  if (date.toDate) {
    jsDate = date.toDate();
  } else if (date instanceof Date) {
    jsDate = date;
  } else {
    return null;
  }
  
  const year = jsDate.getFullYear();
  const month = String(jsDate.getMonth() + 1).padStart(2, '0');
  const day = String(jsDate.getDate()).padStart(2, '0');
  
  return `${year}-${month}-${day}`;
}

/**
 * Check if document ID is date-based (YYYY-MM-DD format)
 */
function isDateBasedId(docId) {
  // Check if it matches YYYY-MM-DD pattern
  const datePattern = /^\d{4}-\d{2}-\d{2}$/;
  return datePattern.test(docId);
}

/**
 * Migrate daily_progress records for a user
 */
async function migrateDailyProgress(userId) {
  console.log(`\n=== Migrating daily_progress records for user: ${userId} ===\n`);
  console.log(`Delete old documents: ${DELETE_OLD_DOCUMENTS ? 'YES' : 'NO (dry-run mode)'}\n`);

  // Get all daily_progress records
  const progressRef = db
    .collection('users')
    .doc(userId)
    .collection('daily_progress');
  
  const snapshot = await progressRef.get();
  
  if (snapshot.empty) {
    console.log('No daily_progress records found.');
    return { migrated: 0, skipped: 0, errors: 0, deleted: 0 };
  }

  console.log(`Found ${snapshot.size} records to migrate.\n`);

  let migrated = 0;
  let skipped = 0;
  let errors = 0;
  let deleted = 0;
  const batch = db.batch();
  let batchCount = 0;
  const oldDocRefs = [];

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

      // Check if document already has date-based ID
      if (doc.id === dateDocId) {
        console.log(`✓  Document ${doc.id} already has correct ID, skipping`);
        skipped++;
        continue;
      }

      // Check if target document already exists
      const targetDocRef = progressRef.doc(dateDocId);
      const targetDoc = await targetDocRef.get();
      
      // If target exists and current doc has auto-generated ID, mark old doc for deletion
      if (targetDoc.exists) {
        if (!isDateBasedId(doc.id)) {
          // Old document has auto-generated ID, mark for deletion
          if (DELETE_OLD_DOCUMENTS) {
            oldDocRefs.push(doc.ref);
            // Log progress every 50 documents to avoid spam
            if (oldDocRefs.length % 50 === 0 || oldDocRefs.length === 1) {
              console.log(`🗑️  Marked ${oldDocRefs.length} old documents for deletion...`);
            }
          } else {
            if (skipped < 10) { // Only show first 10 in dry-run
              console.log(`⚠️  Target ${dateDocId} exists, old doc ${doc.id} would be deleted`);
            }
          }
        } else {
          // Both have date-based IDs (duplicate), skip silently
        }
        skipped++;
        continue;
      }

      // Add to batch: create new document with date-based ID
      batch.set(targetDocRef, data, { merge: true });
      batchCount++;
      migrated++;

      // Track old document for deletion
      if (DELETE_OLD_DOCUMENTS) {
        oldDocRefs.push(doc.ref);
      }

      // Log progress
      if (migrated % 10 === 0) {
        const dateStr = dateDocId;
        console.log(`  [${migrated} migrated] ${doc.id} → ${dateDocId}`);
      }

      // Delete old documents periodically if we have enough
      if (DELETE_OLD_DOCUMENTS && oldDocRefs.length >= 500) {
        const deleteBatch = db.batch();
        const toDelete = oldDocRefs.splice(0, 500); // Take first 500
        for (const oldRef of toDelete) {
          deleteBatch.delete(oldRef);
        }
        await deleteBatch.commit();
        deleted += toDelete.length;
        console.log(`  → Deleted batch of ${toDelete.length} old documents`);
      }

      // Commit batch every 500 operations (Firestore limit)
      if (batchCount >= 500) {
        await batch.commit();
        console.log(`  → Committed batch of ${batchCount} migrations`);
        batchCount = 0;
      }
    } catch (error) {
      console.error(`❌ Error migrating document ${doc.id}:`, error.message);
      errors++;
    }
  }

  // Commit any remaining migrations
  if (batchCount > 0) {
    await batch.commit();
    console.log(`  → Committed final batch of ${batchCount} migrations`);
  }

  // Delete remaining old documents if requested
  if (DELETE_OLD_DOCUMENTS && oldDocRefs.length > 0) {
    console.log(`\n🗑️  Found ${oldDocRefs.length} old documents to delete...`);
    let batchNum = 1;
    while (oldDocRefs.length > 0) {
      const deleteBatch = db.batch();
      const toDelete = oldDocRefs.splice(0, 500); // Take up to 500
      for (const oldRef of toDelete) {
        deleteBatch.delete(oldRef);
      }
      await deleteBatch.commit();
      deleted += toDelete.length;
      console.log(`  → Batch ${batchNum}: Deleted ${toDelete.length} old documents (${deleted} total)`);
      batchNum++;
    }
    console.log(`✅ Successfully deleted ${deleted} old documents`);
  } else if (DELETE_OLD_DOCUMENTS && oldDocRefs.length === 0) {
    console.log(`\nℹ️  No old documents found to delete (all records already use date-based IDs)`);
  }

  console.log(`\n=== Migration Complete ===`);
  console.log(`✓  Migrated: ${migrated} records`);
  console.log(`⊘  Skipped: ${skipped} records`);
  console.log(`❌ Errors: ${errors} records`);
  if (DELETE_OLD_DOCUMENTS) {
    console.log(`🗑️  Deleted: ${deleted} old documents`);
  } else {
    console.log(`\n⚠️  Old documents NOT deleted (dry-run mode)`);
    console.log(`   Run with --delete-old flag to delete old documents after migration`);
  }

  return { migrated, skipped, errors, deleted };
}

/**
 * Main execution
 */
async function main() {
  const userId = process.argv[2];

  if (!userId) {
    console.error('Usage: node migrate_daily_progress_to_date_ids.js <userId> [--delete-old]');
    console.error('');
    console.error('Options:');
    console.error('  --delete-old    Delete old documents after migration (default: dry-run mode)');
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
        console.log('\n💡 Tip: Review the migrated records, then run again with --delete-old to clean up old documents.');
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
