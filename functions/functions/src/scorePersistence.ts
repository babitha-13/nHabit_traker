/**
 * Score persistence logic for day-end processing
 * Handles creating daily progress records with points and scores
 */

import * as admin from 'firebase-admin';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import {
  ActivityInstance,
  DailyProgressRecord,
  CategoryRecord,
  UserProgressStats,
  getYesterdayStart,
  normalizeToStartOfDay,
  timestampToDate,
  isSameDay,
  formatDateKeyIST,
} from './types.js';

// Firestore access helper
const getDb = () => admin.firestore();


/**
 * Calculate effective gain (actual change in score, accounting for floor at 0)
 * This is the actual amount the cumulative score changed, not the raw gain
 */
export function calculateEffectiveGain(previousScore: number, actualGain: number, newScore: number): number {
  // Effective gain is simply the actual change in score
  // This automatically accounts for the floor at 0
  return newScore - previousScore;
}

// Score formula constants (matching ScoreFormulas in Dart)
export const BASE_POINTS_PER_DAY = 10.0;
export const CONSISTENCY_THRESHOLD = 80.0;
export const DECAY_THRESHOLD = 50.0;
export const PENALTY_BASE_MULTIPLIER = 0.04;
export const CATEGORY_NEGLECT_PENALTY = 0.4;
export const CONSISTENCY_BONUS_FULL = 5.0;
export const CONSISTENCY_BONUS_PARTIAL = 2.0;

export interface PersistScoreOptions {
  overwrite?: boolean;
  setLastProcessedDate?: boolean;
  throwOnError?: boolean;
}

function resolvePersistOptions(
  optionsOrSetLastProcessedDate: PersistScoreOptions | boolean = false
): Required<PersistScoreOptions> {
  if (typeof optionsOrSetLastProcessedDate === 'boolean') {
    return {
      overwrite: false,
      setLastProcessedDate: optionsOrSetLastProcessedDate,
      throwOnError: false,
    };
  }
  return {
    overwrite: optionsOrSetLastProcessedDate.overwrite ?? false,
    setLastProcessedDate: optionsOrSetLastProcessedDate.setLastProcessedDate ?? false,
    throwOnError: optionsOrSetLastProcessedDate.throwOnError ?? false,
  };
}

/**
 * Persist scores for a specific date
 * Creates daily progress record if it doesn't exist
 * @param setLastProcessedDate If true, sets lastProcessedDate in progress_stats (for cloud function tracking)
 */
export async function persistScoresForDate(
  userId: string,
  targetDate: Date,
  optionsOrSetLastProcessedDate: PersistScoreOptions | boolean = false
): Promise<void> {
  const options = resolvePersistOptions(optionsOrSetLastProcessedDate);
  try {
    const normalizedDate = normalizeToStartOfDay(targetDate);

    // Check if record already exists using date-based document ID (IST)
    const db = getDb();
    const progressRef = db
      .collection('users')
      .doc(userId)
      .collection('daily_progress');

    const dateDocId = formatDateKeyIST(normalizedDate);

    const existingDoc = await progressRef.doc(dateDocId).get();
    if (existingDoc.exists && !options.overwrite) {
      // Record already exists, but still ensure cumulative_score_history is up to date
      const existingData = existingDoc.data() as DailyProgressRecord;
      if (existingData.cumulativeScoreSnapshot !== undefined && existingData.cumulativeScoreSnapshot !== null) {
        // Update cumulative_score_history if effectiveGain or snapshot are available
        const effectiveGain = existingData.effectiveGain ?? existingData.dailyScoreGain ?? 0;
        await updateCumulativeScoreHistory(
          userId,
          normalizedDate,
          existingData.cumulativeScoreSnapshot,
          existingData.previousDayCumulativeScore ?? Math.max(0, existingData.cumulativeScoreSnapshot - (existingData.effectiveGain ?? existingData.dailyScoreGain ?? 0)),
          existingData.dailyScoreGain || 0,
          effectiveGain
        );
      }
      return;
    }

    // Create daily progress record
    await createDailyProgressRecordForDate(userId, normalizedDate, options.setLastProcessedDate);
  } catch (error) {
    console.error(`Error persisting scores for user ${userId}, date ${targetDate}:`, error);
    if (options.throwOnError) {
      throw error;
    }
    // Don't throw in background operation mode.
  }
}

/**
 * Persist scores in an inclusive date range, strictly in ascending day order.
 * This ensures opening/closing cumulative continuity between days.
 */
export async function persistScoresForDateRange(
  userId: string,
  startDate: Date,
  endDate: Date,
  options: PersistScoreOptions = { overwrite: true, setLastProcessedDate: false }
): Promise<void> {
  const normalizedStart = normalizeToStartOfDay(startDate);
  const normalizedEnd = normalizeToStartOfDay(endDate);
  if (normalizedStart.getTime() > normalizedEnd.getTime()) {
    return;
  }

  let current = new Date(normalizedStart.getTime());
  while (current.getTime() <= normalizedEnd.getTime()) {
    await persistScoresForDate(userId, current, options);
    current = new Date(current.getTime() + 24 * 60 * 60 * 1000);
  }
}

/**
 * Create daily progress record for a specific date
 * @param setLastProcessedDate If true, sets lastProcessedDate in progress_stats
 */
async function createDailyProgressRecordForDate(
  userId: string,
  targetDate: Date,
  setLastProcessedDate = false
): Promise<void> {
  try {
    const db = getDb();
    // Fetch all instances and categories
    const instancesRef = db
      .collection('users')
      .doc(userId)
      .collection('activity_instances');

    const habitInstancesSnapshot = await instancesRef
      .where('templateCategoryType', '==', 'habit')
      .get();

    const taskInstancesSnapshot = await instancesRef
      .where('templateCategoryType', '==', 'task')
      .get();

    const categoriesRef = db
      .collection('users')
      .doc(userId)
      .collection('categories');

    const categoriesSnapshot = await categoriesRef
      .where('categoryType', '==', 'habit')
      .get();

    // Convert to typed objects
    const habitInstances: ActivityInstance[] = [];
    habitInstancesSnapshot.forEach((doc) => {
      habitInstances.push(doc.data() as ActivityInstance);
    });

    const taskInstances: ActivityInstance[] = [];
    taskInstancesSnapshot.forEach((doc) => {
      taskInstances.push(doc.data() as ActivityInstance);
    });

    const categories: Array<CategoryRecord & { id: string }> = [];
    categoriesSnapshot.forEach((doc) => {
      categories.push({ ...doc.data() as CategoryRecord, id: doc.id });
    });

    // Calculate daily progress
    const calculationResult = await calculateDailyProgress(
      userId,
      targetDate,
      habitInstances,
      taskInstances,
      categories
    );

    // Calculate score
    const scoreData = await calculateScore(
      userId,
      calculationResult.completionPercentage,
      calculationResult.earnedPoints,
      categories,
      calculationResult.allForMath,
      targetDate
    );

    // Get cumulative score at start of target day
    const cumulativeAtStart = await getCumulativeScoreAtStartOfDay(userId, targetDate);
    const actualGain = scoreData.todayScore;
    const cumulativeAtEnd = Math.max(0, cumulativeAtStart + actualGain);

    // Calculate effective gain (actual change in score, accounting for floor at 0)
    const effectiveGain = calculateEffectiveGain(cumulativeAtStart, actualGain, cumulativeAtEnd);

    // Count statistics
    const stats = countStatistics(
      calculationResult.allForMath,
      calculationResult.allTasksForMath,
      targetDate
    );

    // Create category breakdown
    const categoryBreakdown = createCategoryBreakdown(
      categories,
      calculationResult.allForMath,
      calculationResult.completedOnDate,
      targetDate
    );

    // Create daily progress record
    const progressData: Partial<DailyProgressRecord> = {
      userId: userId,
      date: Timestamp.fromDate(targetDate),
      targetPoints: calculationResult.targetPoints,
      earnedPoints: calculationResult.earnedPoints,
      completionPercentage: calculationResult.completionPercentage,
      totalHabits: stats.totalHabits,
      completedHabits: stats.completedHabits,
      partialHabits: stats.partialHabits,
      skippedHabits: stats.skippedHabits,
      totalTasks: stats.totalTasks,
      completedTasks: stats.completedTasks,
      partialTasks: stats.partialTasks,
      skippedTasks: stats.skippedTasks,
      taskTargetPoints: calculationResult.taskTarget,
      taskEarnedPoints: calculationResult.taskEarned,
      categoryBreakdown: categoryBreakdown,
      habitBreakdown: calculationResult.habitBreakdown,
      taskBreakdown: calculationResult.taskBreakdown,
      cumulativeScoreSnapshot: cumulativeAtEnd,
      dailyScoreGain: scoreData.todayScore,
      effectiveGain: effectiveGain,
      dailyPoints: scoreData.dailyPoints,
      consistencyBonus: scoreData.consistencyBonus,
      recoveryBonus: scoreData.recoveryBonus,
      decayPenalty: scoreData.decayPenalty,
      categoryNeglectPenalty: scoreData.categoryNeglectPenalty,
      previousDayCumulativeScore: cumulativeAtStart,
      createdAt: FieldValue.serverTimestamp(),
    };

    const progressRef = db
      .collection('users')
      .doc(userId)
      .collection('daily_progress');

    // Use IST date as document ID for easy tracing: "YYYY-MM-DD"
    const dateDocId = formatDateKeyIST(targetDate);

    await progressRef.doc(dateDocId).set(progressData, { merge: true });

    // Update user progress stats
    await updateUserProgressStats(
      userId,
      cumulativeAtEnd,
      targetDate,
      scoreData.todayScore,
      calculationResult.completionPercentage,
      scoreData.categoryNeglectPenalty,
      setLastProcessedDate
    );

    // Update cumulative score history document
    await updateCumulativeScoreHistory(
      userId,
      targetDate,
      cumulativeAtEnd,
      cumulativeAtStart,
      scoreData.todayScore,
      effectiveGain
    );
  } catch (error) {
    console.error(`Error creating daily progress record for user ${userId}:`, error);
    throw error;
  }
}

/**
 * Calculate daily progress for a specific date
 */
async function calculateDailyProgress(
  userId: string,
  targetDate: Date,
  allHabitInstances: ActivityInstance[],
  allTaskInstances: ActivityInstance[],
  categories: Array<CategoryRecord & { id: string }>
): Promise<{
  targetPoints: number;
  earnedPoints: number;
  completionPercentage: number;
  taskTarget: number;
  taskEarned: number;
  allForMath: ActivityInstance[];
  allTasksForMath: ActivityInstance[];
  completedOnDate: ActivityInstance[];
  habitBreakdown: Array<Record<string, any>>;
  taskBreakdown: Array<Record<string, any>>;
}> {
  const normalizedDate = normalizeToStartOfDay(targetDate);

  // Filter habits within window for target date
  const inWindowHabits = allHabitInstances.filter((inst) => {
    if (inst.templateCategoryType === 'essential') return false;
    return isWithinWindow(inst, normalizedDate);
  });

  // Filter completed habits (completed on target date)
  const completedOnDate = inWindowHabits.filter((inst) => {
    if (inst.status !== 'completed' || !inst.completedAt) return false;
    const completedDate = timestampToDate(inst.completedAt);
    if (!completedDate) return false;
    return isSameDay(completedDate, normalizedDate);
  });

  // For earned math: include completed on date + non-completed instances
  const earnedSet = inWindowHabits.filter((inst) => {
    if (inst.status === 'completed') {
      return completedOnDate.includes(inst);
    }
    return true; // Include non-completed for differential contribution
  });

  // Filter tasks for target date
  const allTasksForMath = allTaskInstances.filter((task) => {
    if (task.templateCategoryType === 'essential') return false;

    // Include if completed on target date
    if (task.status === 'completed' && task.completedAt) {
      const completedDate = timestampToDate(task.completedAt);
      if (completedDate && isSameDay(completedDate, normalizedDate)) {
        return true;
      }
    }

    // Include if pending and due on/before target date
    if (task.status === 'pending' && task.dueDate) {
      const dueDate = timestampToDate(task.dueDate);
      if (dueDate && dueDate <= normalizedDate) {
        return true;
      }
    }

    return false;
  });

  // Calculate points
  const habitTargetPoints = calculateTotalDailyTarget(inWindowHabits);
  const habitEarnedPoints = await calculateTotalPointsEarned(earnedSet);
  const taskTarget = calculateTaskTarget(allTasksForMath);
  const taskEarned = await calculateTaskPointsEarned(allTasksForMath);

  const totalTargetPoints = habitTargetPoints + taskTarget;
  const totalEarnedPoints = habitEarnedPoints + taskEarned;
  const percentage = totalTargetPoints > 0
    ? (totalEarnedPoints / totalTargetPoints) * 100
    : 0;

  // Create breakdowns
  const habitBreakdown = inWindowHabits.map((habit) => {
    const target = calculateDailyTarget(habit);
    const earned = calculatePointsEarnedSimple(habit);
    const progress = target > 0 ? Math.min(1, earned / target) : 0;

    const entry: Record<string, unknown> = {
      name: habit.templateName || '',
      status: habit.status,
      target: target,
      earned: earned,
      progress: progress,
      trackingType: habit.templateTrackingType,
    };

    if (typeof habit.currentValue === 'number') {
      entry.quantity = habit.currentValue;
    }
    const timeSpent = habit.totalTimeLogged || habit.accumulatedTime;
    if (typeof timeSpent === 'number' && timeSpent > 0) {
      entry.timeSpent = timeSpent;
    }
    if (habit.completedAt !== undefined) {
      entry.completedAt = habit.completedAt;
    }

    return entry;
  });

  const taskBreakdown = allTasksForMath.map((task) => {
    const target = calculateTaskTarget([task]);
    const earned = calculateTaskPointsEarnedSimple(task);
    const progress = target > 0 ? Math.min(1, earned / target) : 0;

    return {
      name: task.templateName || '',
      status: task.status,
      target: target,
      earned: earned,
      progress: progress,
    };
  });

  return {
    targetPoints: totalTargetPoints,
    earnedPoints: totalEarnedPoints,
    completionPercentage: percentage,
    taskTarget: taskTarget,
    taskEarned: taskEarned,
    allForMath: inWindowHabits,
    allTasksForMath: allTasksForMath,
    completedOnDate: completedOnDate,
    habitBreakdown: habitBreakdown,
    taskBreakdown: taskBreakdown,
  };
}

/**
 * Calculate score using formulas
 */
async function calculateScore(
  userId: string,
  completionPercentage: number,
  pointsEarned: number,
  categories: Array<CategoryRecord & { id: string }>,
  habitInstances: ActivityInstance[],
  targetDate: Date
): Promise<{
  todayScore: number;
  dailyPoints: number;
  consistencyBonus: number;
  recoveryBonus: number;
  decayPenalty: number;
  categoryNeglectPenalty: number;
}> {
  const last7Days = await getLastNDays(userId, 7);

  // Base daily points
  const dailyPoints = calculateDailyScore(completionPercentage, pointsEarned);

  // Consistency bonus
  const consistencyBonus = calculateConsistencyBonus(last7Days);

  // Get user stats for consecutive low days
  const userStats = await getUserStats(userId);
  const consecutiveLowDays = userStats?.consecutiveLowDays ?? 0;

  // Calculate penalty/recovery bonus
  let decayPenalty = 0.0;
  let recoveryBonus = 0.0;

  if (completionPercentage < DECAY_THRESHOLD) {
    const projectedConsecutiveDays = consecutiveLowDays + 1;
    decayPenalty = calculateCombinedPenalty(completionPercentage, projectedConsecutiveDays);
  } else if (consecutiveLowDays > 0) {
    recoveryBonus = calculateRecoveryBonus(consecutiveLowDays);
  }

  // Category neglect penalty
  const categoryNeglectPenalty = calculateCategoryNeglectPenalty(
    categories,
    habitInstances,
    targetDate
  );

  // Today's total score
  const todayScore = dailyPoints + consistencyBonus + recoveryBonus - decayPenalty - categoryNeglectPenalty;

  return {
    todayScore,
    dailyPoints,
    consistencyBonus,
    recoveryBonus,
    decayPenalty,
    categoryNeglectPenalty,
  };
}

/**
 * Score calculation formulas (matching ScoreFormulas in Dart)
 */
export function calculateDailyScore(completionPercentage: number, rawPointsEarned: number): number {
  const percentageComponent = (completionPercentage / 100.0) * BASE_POINTS_PER_DAY;
  const rawPointsBonus = Math.sqrt(rawPointsEarned) / 2.0;
  return percentageComponent + rawPointsBonus;
}

export function calculateConsistencyBonus(last7Days: DailyProgressRecord[]): number {
  if (last7Days.length < 7) return 0.0;

  const highPerformanceDays = last7Days.filter(
    (day) => day.completionPercentage >= CONSISTENCY_THRESHOLD
  ).length;

  if (highPerformanceDays === 7) {
    return CONSISTENCY_BONUS_FULL;
  } else if (highPerformanceDays >= 5) {
    return CONSISTENCY_BONUS_PARTIAL;
  }
  return 0.0;
}

export function calculateCombinedPenalty(dailyCompletion: number, consecutiveLowDays: number): number {
  if (dailyCompletion >= DECAY_THRESHOLD) return 0.0;

  const pointsBelowThreshold = DECAY_THRESHOLD - dailyCompletion;
  const penalty = pointsBelowThreshold * PENALTY_BASE_MULTIPLIER / Math.log(consecutiveLowDays + 1);
  return penalty;
}

export function calculateRecoveryBonus(consecutiveLowDays: number): number {
  if (consecutiveLowDays === 0) return 0.0;
  const bonus = Math.sqrt(consecutiveLowDays) * 1.0;
  return Math.min(5.0, bonus);
}

function calculateCategoryNeglectPenalty(
  categories: Array<CategoryRecord & { id: string }>,
  habitInstances: ActivityInstance[],
  targetDate: Date
): number {
  if (categories.length === 0 || habitInstances.length === 0) return 0.0;

  const normalizedDate = normalizeToStartOfDay(targetDate);
  let totalPenalty = 0.0;

  for (const category of categories) {
    if (category.categoryType !== 'habit') continue;

    const categoryHabits = habitInstances.filter(
      (inst) => inst.templateCategoryId === category.id
    );

    if (categoryHabits.length <= 1) continue;

    // Check if category has any activity
    let hasActivity = false;
    for (const habit of categoryHabits) {
      if (habit.status === 'completed' && habit.completedAt) {
        const completedDate = timestampToDate(habit.completedAt);
        if (completedDate && isSameDay(completedDate, normalizedDate)) {
          hasActivity = true;
          break;
        }
      }
      if (typeof habit.currentValue === 'number' && habit.currentValue > 0) {
        hasActivity = true;
        break;
      }
      if ((habit.totalTimeLogged || 0) > 0 || (habit.accumulatedTime || 0) > 0) {
        hasActivity = true;
        break;
      }
    }

    if (!hasActivity) {
      totalPenalty += CATEGORY_NEGLECT_PENALTY;
    }
  }

  return totalPenalty;
}

/**
 * Points calculation helpers (simplified versions)
 */
function calculateTotalDailyTarget(instances: ActivityInstance[]): number {
  let total = 0.0;
  for (const instance of instances) {
    if (instance.templateCategoryType === 'essential') continue;
    total += calculateDailyTarget(instance);
  }
  return total;
}

function calculateDailyTarget(instance: ActivityInstance): number {
  if (instance.templateCategoryType === 'essential') return 0.0;

  const priority = instance.templatePriority || 1;
  const dailyFrequency = calculateDailyFrequency(instance);

  if (instance.templateTrackingType === 'time') {
    const targetMinutes = typeof instance.templateTarget === 'number'
      ? instance.templateTarget
      : 0;
    const durationMultiplier = calculateDurationMultiplier(targetMinutes);
    return dailyFrequency * priority * durationMultiplier;
  }

  return dailyFrequency * priority;
}

function calculateDailyFrequency(instance: ActivityInstance): number {
  // Handle "every X days/weeks" pattern
  if ((instance.templateEveryXValue || 0) > 1 && instance.templateEveryXPeriodType) {
    const periodDays = periodTypeToDays(instance.templateEveryXPeriodType);
    const frequency = (1.0 / instance.templateEveryXValue!) * (periodDays / 1);
    return frequency;
  }

  // Handle "times per period" pattern
  if ((instance.templateTimesPerPeriod || 0) > 0 && instance.templatePeriodType) {
    const periodDays = periodTypeToDays(instance.templatePeriodType);
    const frequency = (instance.templateTimesPerPeriod! / periodDays);
    return frequency;
  }

  // Default: daily habit (1 time per day)
  return 1.0;
}

function periodTypeToDays(periodType: string): number {
  switch (periodType.toLowerCase()) {
    case 'daily':
    case 'days':
      return 1;
    case 'weekly':
    case 'weeks':
      return 7;
    case 'monthly':
    case 'months':
      return 30;
    default:
      return 7;
  }
}

function calculateDurationMultiplier(targetMinutes: number): number {
  // Match Dart: max(1, round(targetMinutes / 30))
  if (targetMinutes <= 0) return 1;
  return Math.max(1, Math.round(targetMinutes / 30));
}

async function calculateTotalPointsEarned(instances: ActivityInstance[]): Promise<number> {
  let total = 0.0;
  for (const instance of instances) {
    if (instance.templateCategoryType === 'essential') continue;
    total += calculatePointsEarnedSimple(instance);
  }
  return total;
}

// --- Value helper functions matching Dart PointsValueHelper ---
function getInstanceCurrentValue(instance: ActivityInstance): number {
  const value = instance.currentValue;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return parseFloat(value) || 0.0;
  return 0.0;
}

function getInstanceTargetValue(instance: ActivityInstance): number {
  const target = instance.templateTarget;
  if (typeof target === 'number') return target;
  if (typeof target === 'string') return parseFloat(target) || 0.0;
  return 0.0;
}

function getInstanceLastDayValue(instance: ActivityInstance): number {
  const value = (instance as any).lastDayValue;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return parseFloat(value) || 0.0;
  return 0.0;
}

function normalizeValue(instance: ActivityInstance, value: number): number {
  if (value <= 0) return 0.0;
  // Heuristic: if value matches accumulatedTime or totalTimeLogged, it's likely MS
  const accumulatedTime = instance.accumulatedTime || 0;
  const totalTimeLogged = instance.totalTimeLogged || 0;
  const isLikelyMS = value > 1000 && (value === accumulatedTime || value === totalTimeLogged);
  if (isLikelyMS) {
    return value / 60000.0;
  }
  return value;
}

function normalizedCurrentValue(instance: ActivityInstance): number {
  return normalizeValue(instance, getInstanceCurrentValue(instance));
}

function isTimeLikeUnit(unitRaw: string | undefined | null): boolean {
  if (!unitRaw) return false;
  const unit = unitRaw.toLowerCase();
  return unit === 'minute' || unit === 'minutes' || unit === 'min' ||
    unit === 'ms' || unit === 'millisecond' || unit === 'milliseconds';
}

function loggedTimeMinutes(instance: ActivityInstance): number | null {
  const accumulatedTime = instance.accumulatedTime || 0;
  const totalTimeLogged = instance.totalTimeLogged || 0;
  const loggedMs = accumulatedTime > 0 ? accumulatedTime : totalTimeLogged;
  if (loggedMs > 0) {
    return loggedMs / 60000.0;
  }
  return null;
}

/**
 * Comprehensive points calculation matching Dart PointsService.calculatePointsEarnedSync
 * Handles binary, quantitative, and time tracking types with full formula parity
 */
function calculatePointsEarnedSimple(instance: ActivityInstance): number {
  if (instance.templateCategoryType === 'essential') return 0.0;

  const priority = instance.templatePriority || 1;
  let earnedPoints = 0.0;
  const trackingType = instance.templateTrackingType || 'binary';

  switch (trackingType) {
    case 'binary': {
      const countValue = getInstanceCurrentValue(instance);
      const unitIsTimeLike = isTimeLikeUnit((instance as any).templateUnit);

      // A "timer task" is one where currentValue matches the logged time (in MS)
      const accumulatedTime = instance.accumulatedTime || 0;
      const totalTimeLogged = instance.totalTimeLogged || 0;
      const isTimerTaskValue = countValue > 0 &&
        (countValue === accumulatedTime || countValue === totalTimeLogged);

      if (!unitIsTimeLike && !isTimerTaskValue && countValue > 0) {
        // Has counter: proportional points (counter / target)
        const target = getInstanceTargetValue(instance) || 1;
        earnedPoints = (countValue / target) * priority;
      } else if (instance.status === 'completed') {
        earnedPoints = priority;
      } else {
        earnedPoints = 0.0;
      }

      // Add time bonus if time is logged and earned > 0
      // Note: timeBonusEnabled from app state is not available in cloud function
      // Default to false for cloud function (goal mode)
      const timeMinutes = loggedTimeMinutes(instance);
      if (timeMinutes != null && earnedPoints > 0 && timeMinutes >= 30.0) {
        // Award bonus for every 30-minute block beyond the first 30 minutes
        const excessMinutes = timeMinutes - 30.0;
        const bonusBlocks = Math.floor(excessMinutes / 30.0);
        earnedPoints += bonusBlocks * priority;
      }
      return earnedPoints;
    }
    case 'quantity':
    case 'quantitative': {
      const currentValue = normalizedCurrentValue(instance);
      const target = getInstanceTargetValue(instance);
      if (target <= 0) {
        return 0.0;
      }

      // For windowed habits, use differential progress (today's contribution)
      const windowDuration = (instance as any).windowDuration || 0;
      if (instance.templateCategoryType === 'habit' && windowDuration > 1) {
        const lastDayValue = getInstanceLastDayValue(instance);
        const normalizedLastDayVal = normalizeValue(instance, lastDayValue);
        const todayContribution = currentValue - normalizedLastDayVal;
        const progressFraction = todayContribution / target;
        earnedPoints = progressFraction * priority;
      } else {
        const completionFraction = currentValue / target;
        earnedPoints = completionFraction * priority;
      }
      return earnedPoints;
    }
    case 'time': {
      const accTime = instance.accumulatedTime || 0;

      // Goal/progress mode (default for cloud function)
      const targetMinutes = getInstanceTargetValue(instance);
      const targetMs = targetMinutes * 60000;
      if (targetMs <= 0) {
        return 0.0;
      }

      // For windowed habits, use differential progress
      const windowDuration = (instance as any).windowDuration || 0;
      if (instance.templateCategoryType === 'habit' && windowDuration > 1) {
        const lastDayValue = getInstanceLastDayValue(instance);
        const todayContribution = accTime - lastDayValue;
        const progressFraction = todayContribution / targetMs;
        earnedPoints = progressFraction * priority;
      } else {
        const completionFraction = accTime / targetMs;
        earnedPoints = completionFraction * priority;
      }
      return earnedPoints;
    }
    default:
      return 0.0;
  }
}

function calculateTaskTarget(instances: ActivityInstance[]): number {
  // Tasks typically have priority-based targets
  let total = 0.0;
  for (const instance of instances) {
    total += instance.templatePriority || 1;
  }
  return total;
}

async function calculateTaskPointsEarned(instances: ActivityInstance[]): Promise<number> {
  let total = 0.0;
  for (const instance of instances) {
    total += calculateTaskPointsEarnedSimple(instance);
  }
  return total;
}

function calculateTaskPointsEarnedSimple(instance: ActivityInstance): number {
  const priority = instance.templatePriority || 1;
  if (instance.status === 'completed') {
    return priority;
  }
  return 0.0;
}

/**
 * Helper functions
 */
function isWithinWindow(instance: ActivityInstance, targetDate: Date): boolean {
  const dueDate = timestampToDate(instance.dueDate);
  if (!dueDate) return true;

  const windowEnd = timestampToDate(instance.windowEndDate);
  if (windowEnd) {
    const windowEndNormalized = normalizeToStartOfDay(windowEnd);
    const dueDateNormalized = normalizeToStartOfDay(dueDate);
    return targetDate >= dueDateNormalized &&
      targetDate <= windowEndNormalized;
  }

  return isSameDay(dueDate, targetDate);
}

function countStatistics(
  habitInstances: ActivityInstance[],
  taskInstances: ActivityInstance[],
  targetDate: Date
): {
  totalHabits: number;
  completedHabits: number;
  partialHabits: number;
  skippedHabits: number;
  totalTasks: number;
  completedTasks: number;
  partialTasks: number;
  skippedTasks: number;
} {
  const normalizedDate = normalizeToStartOfDay(targetDate);

  // Count habits
  const totalHabits = habitInstances.length;
  const completedHabits = habitInstances.filter((inst) => {
    if (inst.status !== 'completed' || !inst.completedAt) return false;
    const completedDate = timestampToDate(inst.completedAt);
    return completedDate && isSameDay(completedDate, normalizedDate);
  }).length;

  const partialHabits = habitInstances.filter((inst) => {
    if (inst.status === 'completed') return false;
    const value = typeof inst.currentValue === 'number' ? inst.currentValue : 0;
    return value > 0;
  }).length;

  const skippedHabits = habitInstances.filter((inst) => inst.status === 'skipped').length;

  // Count tasks
  const totalTasks = taskInstances.length;
  const completedTasks = taskInstances.filter((task) => {
    if (task.status !== 'completed' || !task.completedAt) return false;
    const completedDate = timestampToDate(task.completedAt);
    return completedDate && isSameDay(completedDate, normalizedDate);
  }).length;

  const partialTasks = taskInstances.filter((task) => {
    if (task.status === 'completed') return false;
    const value = typeof task.currentValue === 'number' ? task.currentValue : 0;
    return value > 0;
  }).length;

  const skippedTasks = taskInstances.filter((task) => task.status === 'skipped').length;

  return {
    totalHabits,
    completedHabits,
    partialHabits,
    skippedHabits,
    totalTasks,
    completedTasks,
    partialTasks,
    skippedTasks,
  };
}

function createCategoryBreakdown(
  categories: Array<CategoryRecord & { id: string }>,
  allHabits: ActivityInstance[],
  completedHabits: ActivityInstance[],
  targetDate: Date
): Record<string, { target: number; earned: number; completed: number; total: number }> {
  const breakdown: Record<string, { target: number; earned: number; completed: number; total: number }> = {};

  for (const category of categories) {
    const categoryHabits = allHabits.filter(
      (inst) => inst.templateCategoryId === category.id
    );

    if (categoryHabits.length === 0) continue;

    const categoryCompleted = completedHabits.filter(
      (inst) => inst.templateCategoryId === category.id
    );

    const categoryTarget = calculateTotalDailyTarget(categoryHabits);
    const categoryEarned = categoryCompleted.reduce((sum, inst) => {
      return sum + calculatePointsEarnedSimple(inst);
    }, 0);

    breakdown[category.id] = {
      target: categoryTarget,
      earned: categoryEarned,
      completed: categoryCompleted.length,
      total: categoryHabits.length,
    };
  }

  return breakdown;
}

async function getLastNDays(userId: string, n: number): Promise<DailyProgressRecord[]> {
  const db = getDb();
  const progressRef = db
    .collection('users')
    .doc(userId)
    .collection('daily_progress');

  const snapshot = await progressRef
    .orderBy('date', 'desc')
    .limit(n)
    .get();

  const records: DailyProgressRecord[] = [];
  snapshot.forEach((doc) => {
    records.push(doc.data() as DailyProgressRecord);
  });

  return records.reverse(); // Return in chronological order
}

async function getCumulativeScoreAtStartOfDay(
  userId: string,
  targetDate: Date
): Promise<number> {
  try {
    // Get the day before target date
    const dayBefore = new Date(targetDate.getTime() - 24 * 60 * 60 * 1000);
    const dayBeforeNormalized = normalizeToStartOfDay(dayBefore);

    const db = getDb();
    const progressRef = db
      .collection('users')
      .doc(userId)
      .collection('daily_progress');

    // Use date-based doc ID lookup instead of Timestamp equality query
    // This avoids UTC vs IST mismatch issues
    const dayBeforeDocId = formatDateKeyIST(dayBeforeNormalized);
    const dayBeforeDoc = await progressRef.doc(dayBeforeDocId).get();

    if (dayBeforeDoc.exists) {
      const record = dayBeforeDoc.data() as DailyProgressRecord;
      if (record.cumulativeScoreSnapshot !== undefined && record.cumulativeScoreSnapshot !== null) {
        return record.cumulativeScoreSnapshot;
      }
    }

    // Fallback: get from user stats
    const userStats = await getUserStats(userId);
    if (userStats && userStats.cumulativeScore !== undefined && userStats.cumulativeScore !== null) {
      return Math.max(0, userStats.cumulativeScore - (userStats.lastDailyGain || 0));
    }

    return 0.0;
  } catch (error) {
    console.error(`Error getting cumulative score for user ${userId}:`, error);
    return 0.0;
  }
}

async function getUserStats(userId: string): Promise<UserProgressStats | null> {
  try {
    const db = getDb();
    const statsRef = db
      .collection('users')
      .doc(userId)
      .collection('progress_stats')
      .doc('main');

    const statsDoc = await statsRef.get();
    if (statsDoc.exists) {
      return statsDoc.data() as UserProgressStats;
    }
    return null;
  } catch (error) {
    console.error(`Error getting user stats for ${userId}:`, error);
    return null;
  }
}

async function updateUserProgressStats(
  userId: string,
  cumulativeScore: number,
  calculationDate: Date,
  dailyGain: number,
  completionPercentage: number,
  categoryNeglectPenalty: number,
  setLastProcessedDate = false
): Promise<void> {
  try {
    const db = getDb();
    const statsRef = db
      .collection('users')
      .doc(userId)
      .collection('progress_stats')
      .doc('main');

    const existingStats = await getUserStats(userId);

    // Update consecutive low days
    let consecutiveLowDays = existingStats?.consecutiveLowDays ?? 0;
    if (completionPercentage < DECAY_THRESHOLD) {
      consecutiveLowDays++;
    } else {
      consecutiveLowDays = 0;
    }

    const statsData: Partial<UserProgressStats> = {
      userId: userId,
      cumulativeScore: cumulativeScore,
      lastCalculationDate: Timestamp.fromDate(calculationDate),
      lastDailyGain: dailyGain,
      consecutiveLowDays: consecutiveLowDays,
      lastUpdatedAt: FieldValue.serverTimestamp(),
    };

    // Set lastProcessedDate if requested (when called from cloud function)
    if (setLastProcessedDate) {
      // Set to yesterday's date (normalized to start of day)
      const yesterday = normalizeToStartOfDay(calculationDate);
      statsData.lastProcessedDate = Timestamp.fromDate(yesterday);
    }

    if (existingStats) {
      await statsRef.update(statsData);
    } else {
      await statsRef.set({
        ...statsData,
        historicalHighScore: cumulativeScore,
        totalDaysTracked: 1,
        currentStreak: completionPercentage >= CONSISTENCY_THRESHOLD ? 1 : 0,
        longestStreak: completionPercentage >= CONSISTENCY_THRESHOLD ? 1 : 0,
        achievedMilestones: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  } catch (error) {
    console.error(`Error updating user stats for ${userId}:`, error);
    // Don't throw - stats update is not critical
  }
}

/**
 * Update cumulative score history document with today's entry
 * Keeps last 100 days of history
 */
async function updateCumulativeScoreHistory(
  userId: string,
  date: Date,
  closingScore: number,
  openingScore: number,
  gain: number,
  effectiveGain: number
): Promise<void> {
  try {
    const db = getDb();
    const historyRef = db
      .collection('users')
      .doc(userId)
      .collection('cumulative_score_history')
      .doc('history');

    const historyDoc = await historyRef.get();
    let scores: Array<{
      date: Timestamp;
      closingScore?: number;
      openingScore?: number;
      score?: number; // backward compatibility
      gain: number;
      effectiveGain: number;
    }> = [];

    if (historyDoc.exists) {
      const data = historyDoc.data();
      if (data && data.scores) {
        scores = data.scores;
      }
    }

    // Remove existing entry for this date (if any)
    const dateKey = formatDateKey(date);
    scores = scores.filter((s) => formatDateKey(s.date.toDate()) !== dateKey);

    // Add new entry
    scores.push({
      date: Timestamp.fromDate(date),
      closingScore,
      openingScore,
      // Keep `score` for backward compatibility with existing reads.
      score: closingScore,
      gain,
      effectiveGain,
    });

    // Keep last 100 days
    scores.sort((a, b) => a.date.toMillis() - b.date.toMillis());
    if (scores.length > 100) {
      scores = scores.slice(-100);
    }

    await historyRef.set({
      scores,
      lastUpdated: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error(`Error updating cumulative score history for ${userId}:`, error);
    // Don't throw - history update is non-critical, can be recalculated from daily_progress
  }
}

/**
 * Format date as YYYY-MM-DD key for comparison (IST-aware)
 */
function formatDateKey(date: Date): string {
  return formatDateKeyIST(date);
}

/**
 * Recalculate and overwrite recent finalized days (default 90 days), sequentially.
 * Also rebuilds cumulative history entries as each day is rewritten.
 */
export async function backfillRecentScores(
  userId: string,
  days = 90
): Promise<void> {
  const safeDays = Math.max(1, Math.min(365, Math.floor(days)));
  const yesterday = getYesterdayStart();
  const startDate = normalizeToStartOfDay(
    new Date(yesterday.getTime() - ((safeDays - 1) * 24 * 60 * 60 * 1000))
  );
  await persistScoresForDateRange(userId, startDate, yesterday, {
    overwrite: true,
    setLastProcessedDate: false,
    throwOnError: true,
  });
}

/**
 * Persist scores for missed days up to yesterday
 * Creates records for any gaps between last record and yesterday
 */
export async function persistScoresForMissedDaysIfNeeded(userId: string): Promise<void> {
  try {
    const yesterday = getYesterdayStart();
    const db = getDb();

    // Find the last daily progress record
    const progressRef = db
      .collection('users')
      .doc(userId)
      .collection('daily_progress');

    const lastRecordQuery = progressRef
      .orderBy('date', 'desc')
      .limit(1);

    const lastRecordSnapshot = await lastRecordQuery.get();

    if (lastRecordSnapshot.empty) {
      // No records exist - create for yesterday only
      await persistScoresForDate(userId, yesterday);
      return;
    }

    const lastRecord = lastRecordSnapshot.docs[0].data() as DailyProgressRecord;
    const lastRecordDate = timestampToDate(lastRecord.date);

    if (!lastRecordDate) {
      await persistScoresForDate(userId, yesterday);
      return;
    }

    // Check if there's a gap between last record and yesterday
    const lastRecordNormalized = normalizeToStartOfDay(lastRecordDate);
    const yesterdayNormalized = normalizeToStartOfDay(yesterday);

    // If last record is before yesterday, create records for missed days
    if (lastRecordNormalized < yesterdayNormalized) {
      const startDate = normalizeToStartOfDay(
        new Date(lastRecordNormalized.getTime() + 24 * 60 * 60 * 1000)
      );
      const maxRangeStart = normalizeToStartOfDay(
        new Date(yesterdayNormalized.getTime() - (89 * 24 * 60 * 60 * 1000))
      );
      const boundedStart = startDate.getTime() < maxRangeStart.getTime()
        ? maxRangeStart
        : startDate;

      // Sequential date progression is intentional to keep opening/closing
      // cumulative values deterministic across the range.
      await persistScoresForDateRange(userId, boundedStart, yesterdayNormalized, {
        overwrite: false,
        setLastProcessedDate: false,
      });
    }
  } catch (error) {
    console.error(`Error creating records for missed days for user ${userId}:`, error);
    // Don't throw - this is a background operation
  }
}
