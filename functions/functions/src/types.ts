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
  templateTrackingType?: 'binary' | 'quantity' | 'time';
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

// Helper function to normalize date to start of day (UTC)
export function normalizeToStartOfDay(date: Date): Date {
  const normalized = new Date(date);
  normalized.setUTCHours(0, 0, 0, 0);
  return normalized;
}

// Helper function to convert Firestore Timestamp to Date
export function timestampToDate(timestamp: FirestoreTimestamp | undefined): Date | undefined {
  if (!timestamp) return undefined;
  if (timestamp instanceof Date) return timestamp;
  if (timestamp instanceof Timestamp) return timestamp.toDate();
  return undefined; // FieldValue cannot be converted to Date locally
}

// Helper function to check if two dates are the same day
export function isSameDay(date1: Date, date2: Date): boolean {
  return date1.getUTCFullYear() === date2.getUTCFullYear() &&
    date1.getUTCMonth() === date2.getUTCMonth() &&
    date1.getUTCDate() === date2.getUTCDate();
}

// Helper function to get yesterday's date (normalized to start of day)
export function getYesterdayStart(): Date {
  const yesterday = new Date();
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  return normalizeToStartOfDay(yesterday);
}

// Helper function to get today's date (normalized to start of day)
export function getTodayStart(): Date {
  return normalizeToStartOfDay(new Date());
}
