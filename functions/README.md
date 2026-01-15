# Firebase Cloud Functions - Day-End Processing

This directory contains Firebase Cloud Functions that automatically process day-end activities for all users at midnight UTC daily.

## Overview

The scheduled function `processDayEndForAllUsers` runs at midnight UTC every day and performs:

1. **Instance Maintenance**:
   - Auto-skips habits where windows expired 2+ days before yesterday
   - Ensures all active habits have pending instances
   - Updates `lastDayValue` for active habits with open windows

2. **Score Persistence**:
   - Creates daily progress records for yesterday (if not already exists)
   - Calculates points, completion percentage, and scores
   - Updates user progress stats
   - Fills gaps for missed days (up to 90 days)

## Prerequisites

- Node.js 18 or higher
- Firebase CLI installed (`npm install -g firebase-tools`)
- Firebase project initialized
- Firestore indexes created (see below)

## Setup

1. **Install dependencies**:
   ```bash
   cd functions
   npm install
   ```

2. **Build TypeScript**:
   ```bash
   npm run build
   ```

3. **Verify Firestore Indexes**:
   
   The following composite indexes are required in Firestore:
   
   - **activity_instances** collection:
     - `templateCategoryType` (ASC) + `status` (ASC) + `windowEndDate` (ASC) + `dueDate` (ASC)
     - `templateId` (ASC) + `status` (ASC) + `belongsToDate` (ASC) + `dueDate` (ASC)
     - `templateCategoryType` (ASC) + `status` (ASC) + `windowEndDate` (ASC)
   
   - **daily_progress** collection:
     - `date` (ASC)
     - `date` (DESC) - for querying last record
   
   These indexes should already exist from app usage, but verify in Firebase Console > Firestore > Indexes.

## Deployment

1. **Login to Firebase** (if not already):
   ```bash
   firebase login
   ```

2. **Select your project**:
   ```bash
   firebase use <your-project-id>
   ```

3. **Deploy the function**:
   ```bash
   firebase deploy --only functions
   ```

   Or deploy from the functions directory:
   ```bash
   cd functions
   npm run deploy
   ```

4. **Verify deployment**:
   - Go to Firebase Console > Functions
   - You should see `processDayEndForAllUsers` listed
   - Check that it's scheduled to run at midnight UTC

## Testing

### Local Testing with Emulator

1. **Start the emulator**:
   ```bash
   firebase emulators:start --only functions
   ```

2. **Manually trigger the function** (in another terminal):
   ```bash
   firebase functions:shell
   ```
   Then in the shell:
   ```javascript
   processDayEndForAllUsers()
   ```

### Manual Trigger via Firebase Console

1. Go to Firebase Console > Functions
2. Click on `processDayEndForAllUsers`
3. Click "Trigger" tab
4. Click "Test function" to run it manually

### Testing with Single User

To test with a single user, you can temporarily modify `index.ts` to filter users:

```typescript
// In index.ts, add after getting users:
const testUserId = 'your-test-user-id';
const users = usersSnapshot.docs.filter(doc => doc.id === testUserId);
```

## Monitoring

### View Logs

```bash
firebase functions:log --only processDayEndForAllUsers
```

Or in Firebase Console:
- Go to Functions > `processDayEndForAllUsers` > Logs

### Check Execution History

- Firebase Console > Functions > `processDayEndForAllUsers` > Usage
- Shows execution count, success rate, and average execution time

## Function Configuration

The function is configured with:
- **Schedule**: `0 0 * * *` (midnight UTC daily)
- **Timeout**: 540 seconds (9 minutes) - maximum for scheduled functions
- **Memory**: Default (256MB)
- **Region**: Default (us-central1)

To modify these settings, edit `functions/src/index.ts`:

```typescript
export const processDayEndForAllUsers = functions
  .region('us-east1') // Change region
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB' // Increase memory if needed
  })
  .pubsub.schedule('0 0 * * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    // ...
  });
```

## Troubleshooting

### Function Timeout

If the function times out with many users:
- Increase the timeout (max 540s for scheduled functions)
- Reduce batch size in `index.ts` (currently 10)
- Consider splitting into multiple functions

### Missing Indexes

If you see index errors in logs:
- Check Firebase Console > Firestore > Indexes
- Create missing indexes using the links provided in error messages
- Wait for indexes to build (can take several minutes)

### High Error Rate

If many users are failing:
- Check logs for specific error patterns
- Verify Firestore security rules allow function access
- Ensure all required collections exist

### Date/Time Issues

The function uses UTC for all date calculations. If you need a different timezone:
- Modify `getYesterdayStart()` in `types.ts`
- Update the schedule cron expression accordingly

## Code Structure

```
functions/
├── src/
│   ├── index.ts              # Main scheduled function
│   ├── instanceMaintenance.ts # Instance handling logic
│   ├── scorePersistence.ts    # Score calculation and persistence
│   └── types.ts              # TypeScript type definitions
├── package.json
├── tsconfig.json
└── README.md
```

## Important Notes

1. **Idempotency**: The function checks if daily progress records already exist before creating them, so it's safe to run multiple times.

2. **Error Handling**: Individual user failures don't stop the entire batch. Errors are logged but processing continues.

3. **Performance**: Users are processed in batches of 10 with 1-second delays between batches to avoid overwhelming Firestore.

4. **Missed Days**: The function creates records for up to 90 days of missed history. For larger gaps, you may need to run a separate backfill script.

5. **Score Calculations**: The score formulas match the Dart implementation in the app. If formulas change in the app, update `scorePersistence.ts` accordingly.

## Support

For issues or questions:
1. Check Firebase Console logs
2. Review function execution history
3. Verify Firestore indexes are created
4. Test with a single user first
