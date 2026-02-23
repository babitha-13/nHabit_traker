/**
 * TypeScript type definitions matching Firestore schema
 * These types correspond to the Dart schema classes
 */

import { Timestamp, FieldValue } from 'firebase-admin/firestore';

// Firestore Timestamp helper
export type FirestoreTimestamp = Timestamp | Date | FieldValue;

// Activity Instance types
export interface ActivityInstance {
  templateId: string;
  dueDate?: FirestoreTimestamp;
  dueTime?: string;
  status: 'pending' | 'completed' | 'skipped';
  completedAt?: FirestoreTimestamp;
  skippedAt?: FirestoreTimestamp;
  currentValue?: number | string;
  lastDayValue?: number | string;
  accumulatedTime?: number;
  isTimerActive?: boolean;
  timerStartTime?: FirestoreTimestamp;
  timeLogSessions?: Array<{
    startTime: FirestoreTimestamp;
    endTime?: FirestoreTimestamp;
    durationMilliseconds: number;
  }>;
  currentSessionStartTime?: FirestoreTimestamp;
  isTimeLogging?: boolean;
  totalTimeLogged?: number;
  createdTime?: FirestoreTimestamp;
  lastUpdated?: FirestoreTimestamp;
  isActive?: boolean;
  notes?: string;
  // Template data (denormalized)
  templateName?: string;
  templateCategoryId?: string;
  templateCategoryName?: string;
  templateCategoryType?: 'habit' | 'task' | 'essential';
  templateCategoryColor?: string;
  templatePriority?: number;
  templateTrackingType?: 'binary' | 'quantity' | 'quantitative' | 'time';
  templateTarget?: number | string;
  templateUnit?: string;
  templateDescription?: string;
  templateTimeEstimateMinutes?: number;
  templateDueTime?: string;
  templateShowInFloatingTimer?: boolean;
  templateIsRecurring?: boolean;
  templateEveryXValue?: number;
  templateEveryXPeriodType?: string;
  templateTimesPerPeriod?: number;
  templatePeriodType?: string;
  // Habit-specific fields
  dayState?: 'open' | 'closed';
  belongsToDate?: FirestoreTimestamp;
  closedAt?: FirestoreTimestamp;
  windowEndDate?: FirestoreTimestamp;
  windowDuration?: number;
  snoozedUntil?: FirestoreTimestamp;
  // Order fields
  queueOrder?: number;
  habitsOrder?: number;
  tasksOrder?: number;
}

// Activity Template types
export interface ActivityRecord {
  name: string;
  categoryId: string;
  categoryName: string;
  categoryType: 'habit' | 'task' | 'essential';
  impactLevel?: string;
  priority: number;
  trackingType: 'binary' | 'quantity' | 'time';
  target?: number | string;
  unit?: string;
  description?: string;
  isActive: boolean;
  createdTime?: FirestoreTimestamp;
  lastUpdated?: FirestoreTimestamp;
  userId: string;
  dayEndTime?: number;
  specificDays?: number[];
  frequencyType?: string;
  everyXValue?: number;
  everyXPeriodType?: string;
  timesPerPeriod?: number;
  periodType?: string;
  isTimerActive?: boolean;
  timerStartTime?: FirestoreTimestamp;
  dueTime?: string;
  showInFloatingTimer?: boolean;
  isRecurring?: boolean;
}

// Daily Progress Record types
export interface DailyProgressRecord {
  userId: string;
  date: FirestoreTimestamp;
  targetPoints: number;
  earnedPoints: number;
  completionPercentage: number;
  totalHabits: number;
  completedHabits: number;
  partialHabits: number;
  skippedHabits: number;
  totalTasks: number;
  completedTasks: number;
  partialTasks: number;
  skippedTasks: number;
  taskTargetPoints: number;
  taskEarnedPoints: number;
  categoryBreakdown: Record<string, {
    target: number;
    earned: number;
    completed: number;
    total: number;
  }>;
  habitBreakdown?: Array<Record<string, any>>;
  taskBreakdown?: Array<Record<string, any>>;
  createdAt?: FirestoreTimestamp;
  lastEditedAt?: FirestoreTimestamp;
  cumulativeScoreSnapshot?: number;
  dailyScoreGain?: number;
  effectiveGain?: number;
  dailyPoints?: number;
  consistencyBonus?: number;
  recoveryBonus?: number;
  decayPenalty?: number;
  categoryNeglectPenalty?: number;
  previousDayCumulativeScore?: number;
}

// User Progress Stats types
export interface UserProgressStats {
  userId: string;
  cumulativeScore: number;
  lastCalculationDate: FirestoreTimestamp;
  historicalHighScore: number;
  totalDaysTracked: number;
  currentStreak: number;
  longestStreak: number;
  lastDailyGain: number;
  consecutiveLowDays: number;
  cumulativeLowStreakPenalty?: number;
  achievedMilestones: number;
  createdAt?: FirestoreTimestamp;
  lastUpdatedAt?: FirestoreTimestamp;
  // New field names (preferred)
  averageDailyGain7Day?: number;
  averageDailyGain30Day?: number;
  bestDailyGain?: number;
  worstDailyGain?: number;
  negativeDaysCount7Day?: number;
  negativeDaysCount30Day?: number;
  // Old field names (backward compatibility)
  averageDailyScore7Day?: number;
  averageDailyScore30Day?: number;
  bestDailyScoreGain?: number;
  worstDailyScoreGain?: number;
  positiveDaysCount7Day?: number;
  positiveDaysCount30Day?: number;
  scoreGrowthRate7Day?: number;
  scoreGrowthRate30Day?: number;
  averageCumulativeScore7Day?: number;
  averageCumulativeScore30Day?: number;
  lastAggregateStatsCalculationDate?: FirestoreTimestamp;
  lastProcessedDate?: FirestoreTimestamp;
}

// Category Record types
export interface CategoryRecord {
  name: string;
  categoryType: 'habit' | 'task';
  color?: string;
  userId: string;
  createdTime?: FirestoreTimestamp;
  lastUpdated?: FirestoreTimestamp;
}

// IST offset: UTC + 5 hours 30 minutes
const IST_OFFSET_HOURS = 5;
const IST_OFFSET_MINUTES = 30;
const IST_OFFSET_MS = (IST_OFFSET_HOURS * 60 + IST_OFFSET_MINUTES) * 60 * 1000;

// Helper function to get current time in IST
function getISTDate(date: Date = new Date()): Date {
  // Convert to IST by adding offset to UTC
  return new Date(date.getTime() + IST_OFFSET_MS);
}

// Helper function to normalize date to start of day in IST
// Returns a Date whose UTC time represents midnight IST
export function normalizeToStartOfDay(date: Date): Date {
  // Convert to IST to get the correct IST date components
  const istDate = getISTDate(date);
  // Extract IST date components (they appear as UTC components since we added the offset)
  const year = istDate.getUTCFullYear();
  const month = istDate.getUTCMonth();
  const day = istDate.getUTCDate();
  // Create midnight IST = 18:30 UTC previous day
  // midnight IST in UTC = year/month/day 00:00 IST = year/month/day 00:00 - 5:30 = previous day 18:30 UTC
  const midnightIST = new Date(Date.UTC(year, month, day) - IST_OFFSET_MS);
  return midnightIST;
}

// Helper function to convert Firestore Timestamp to Date
export function timestampToDate(timestamp: FirestoreTimestamp | undefined): Date | undefined {
  if (!timestamp) return undefined;
  if (timestamp instanceof Date) return timestamp;
  if (timestamp instanceof Timestamp) return timestamp.toDate();
  return undefined; // FieldValue cannot be converted to Date locally
}

// Helper function to check if two dates are the same day (in IST)
export function isSameDay(date1: Date, date2: Date): boolean {
  // Convert both to IST to compare IST day boundaries
  const ist1 = getISTDate(date1);
  const ist2 = getISTDate(date2);
  return ist1.getUTCFullYear() === ist2.getUTCFullYear() &&
    ist1.getUTCMonth() === ist2.getUTCMonth() &&
    ist1.getUTCDate() === ist2.getUTCDate();
}

// Helper function to get yesterday's date (normalized to start of day in IST)
export function getYesterdayStart(): Date {
  const now = new Date();
  // Subtract 1 day from current time, then normalize to IST start of day
  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  return normalizeToStartOfDay(yesterday);
}

// Helper function to get today's date (normalized to start of day in IST)
export function getTodayStart(): Date {
  return normalizeToStartOfDay(new Date());
}

// Format date as YYYY-MM-DD using IST date components
export function formatDateKeyIST(date: Date): string {
  const istDate = getISTDate(date);
  const year = istDate.getUTCFullYear();
  const month = String(istDate.getUTCMonth() + 1).padStart(2, '0');
  const day = String(istDate.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}
