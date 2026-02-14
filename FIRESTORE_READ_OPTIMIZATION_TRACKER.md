# Firestore Read Optimization Tracker

Last updated: 2026-02-14

## Goal
Reduce unnecessary Firestore reads before adding deeper query instrumentation.

## Identified Hotspots

1. Queue full-sync path can trigger broad re-fetches repeatedly.
Status: `Fixed`
Refs: `lib/features/Queue/queue_page.dart`, `lib/features/Progress/backend/progress_page_data_service.dart`

2. Duplicate logic in Queue instance update handler can schedule duplicate work.
Status: `Fixed`
Refs: `lib/features/Queue/queue_page.dart`

3. Global instance cache invalidates on optimistic events, causing cache churn and extra reads.
Status: `Fixed`
Refs: `lib/Helper/backend/cache/firestore_cache_service.dart`

4. Calendar event load performs multiple parallel queries and is triggered frequently by observers.
Status: `Fixed`
Refs: `lib/features/Calendar/calendar_page_main.dart`, `lib/features/Calendar/calendar_event_service.dart`

5. Calendar time-log date load still falls back to broad scans (`totalTimeLogged > 0`) in key paths.
Status: `Fixed`
Refs: `lib/services/Activtity/task_instance_service/task_instance_time_logging_service.dart`

6. Reminder scheduling/snooze flow scans all instances multiple times.
Status: `Fixed`
Refs: `lib/features/Notifications and alarms/reminder_scheduler.dart`, `lib/features/Home/presentation/home_screen.dart`

7. Habit query functions still fetch broad habit sets then filter in memory.
Status: `Fixed`
Refs: `lib/services/Activtity/Activity Instance Service/activity_instance_query_service.dart`

8. Task page can trigger duplicate initial `_loadData()` calls.
Status: `Fixed`
Refs: `lib/features/Task/task_page.dart`

9. IndexedStack pre-initializes heavy tabs together, multiplying startup reads.
Status: `Fixed`
Refs: `lib/features/Home/presentation/home_screen.dart`

10. Cloud Functions day-end scoring reads full habit/task datasets for recompute.
Status: `Fixed`
Refs: `functions/functions/src/scorePersistence.ts`, `functions/functions/src/instanceMaintenance.ts`

## Quick Fixes (Current Batch)

- [x] QF-1: Remove duplicate recalculation/sync branch in Queue `_handleInstanceUpdated`.
- [x] QF-2: Remove duplicate initial load trigger in Task page.
- [x] QF-3: Avoid full cache invalidation for optimistic instance created/updated events.
- [x] QF-4: Replace calendar date-load broad `queryAllInstances` fallbacks with date-scoped bounded fallbacks.
- [x] QF-5: Debounce observer-triggered calendar reloads and gate planned/routine queries when planned view is hidden.
- [x] QF-6: Remove Queue full-sync dependency on broad breakdown re-fetches and fetch only missing breakdown cache components.
- [x] QF-7: Replace reminder broad instance scans with pending/snooze-scoped queries and remove duplicate startup reminder passes.
- [x] QF-8: Scope task/habit instance query paths to Firestore-level category and window/date bounds instead of broad fetch + in-memory filtering.
- [x] QF-9: Lazy-initialize heavy Home tabs instead of building all IndexedStack pages at startup.
- [x] QF-10: Replace cloud day-end full dataset reads with date-scoped input fetches and avoid unconditional most-recent instance prefetch in maintenance.
- [x] QF-11: Add backend query in-flight dedupe and cache-based cross-page habit derivation to prevent duplicate parallel reads.

## Change Log

- 2026-02-14: Tracker created. Initial hotspot inventory documented.
- 2026-02-14: QF-1 fixed in `lib/features/Queue/queue_page.dart` by removing duplicate update/recalc branch.
- 2026-02-14: QF-2 fixed in `lib/features/Task/task_page.dart` by removing duplicate initial `_loadData()` trigger from `initState`.
- 2026-02-14: QF-3 fixed in `lib/Helper/backend/cache/firestore_cache_service.dart` by applying targeted optimistic cache patching instead of full invalidation for optimistic create/update events.
- 2026-02-14: QF-4 fixed in `lib/features/Calendar/Helpers/calendar_activity_data_service.dart` by replacing `queryAllInstances` fallbacks with date-scoped fallback candidate queries.
- 2026-02-14: QF-4 fixed in `lib/services/Activtity/task_instance_service/task_instance_time_logging_service.dart` by removing always-on broad session scan/merge and using date-scoped queries with capped final fallback.
- 2026-02-14: QF-5 fixed in `lib/features/Calendar/calendar_page_main.dart` by debouncing observer-driven refreshes and replacing immediate silent reload spam with scheduled/coalesced refreshes.
- 2026-02-14: QF-5 fixed in `lib/features/Calendar/calendar_event_service.dart` by adding planned-query mode gating (`includePlanned`) and variant-based calendar cache reuse for completed-only loads.
- 2026-02-14: QF-5 fixed in `lib/Helper/backend/cache/firestore_cache_service.dart` by skipping calendar cache invalidation for optimistic create/update events and supporting date+variant calendar cache keys.
- 2026-02-14: QF-6 fixed in `lib/features/Queue/queue_page.dart` by replacing full-sync calls to `fetchInstancesForBreakdown` with local queue-state partitions for non-optimistic progress/score recalculation.
- 2026-02-14: QF-6 fixed in `lib/features/Progress/backend/progress_page_data_service.dart` by fetching only missing datasets (habits/tasks/categories) on partial cache misses instead of broad 3-query reloads.
- 2026-02-14: QF-7 fixed in `lib/features/Notifications and alarms/reminder_scheduler.dart` by replacing `queryAllInstances` reminder scans with scoped pending/snooze candidate queries, batching template fetches, and resolving snooze targets without full instance scans.
- 2026-02-14: QF-7 fixed in `lib/features/Home/presentation/home_screen.dart` by removing duplicate reminder startup pass (`checkExpiredSnoozes`) after pending reminder scheduling.
- 2026-02-14: QF-8 fixed in `lib/services/Activtity/Activity Instance Service/activity_instance_query_service.dart` by adding category-scoped querySafe fetches for task/habit callers, pushing status/date filters into Firestore queries, and bounding habit window loaders with `windowEndDate` fallbacks.
- 2026-02-14: QF-9 fixed in `lib/features/Home/presentation/home_screen.dart` by replacing eager `IndexedStack` page construction with first-visit lazy tab initialization.
- 2026-02-14: QF-10 fixed in `functions/functions/src/scorePersistence.ts` by replacing per-day full habit/task scans with date-scoped day-end input queries (`windowEndDate`, same-day `dueDate`, `pending`, same-day `completedAt`) plus broad-query fallback for compatibility.
- 2026-02-14: QF-10 fixed in `functions/functions/src/instanceMaintenance.ts` by removing unconditional per-template latest-instance prefetch and switching to on-demand cached latest-instance lookups only for templates that actually need generation.
- 2026-02-14: Post-fix hardening in `lib/services/Activtity/Activity Instance Service/activity_instance_query_service.dart` to log scoped-query failures (including missing-index links) before fallback paths execute.
- 2026-02-14: Added Cloud Functions missing-index link surfacing via `functions/functions/src/firestoreIndexLogger.ts` and wired calls in `functions/functions/src/scorePersistence.ts` and `functions/functions/src/instanceMaintenance.ts`.
- 2026-02-14: Added versioned Firestore composite index config at `functions/firestore.indexes.json` and wired deployment path in `functions/firebase.json`.
- 2026-02-14: QF-11 fixed in `lib/Helper/backend/backend.dart` by adding in-flight query dedupe for shared backend fetches (`queryCategoriesRecordOnce`, `queryAllInstances`, `queryAllTaskInstances`, `queryCurrentHabitInstances`, `queryAllHabitInstances`, `queryLatestHabitInstances`) and deriving pending habit snapshots from cached all-instances to avoid redundant habit reads after Queue loads.

## Firestore Index Deployment

- Index definitions are now versioned in `functions/firestore.indexes.json`.
- Firebase CLI config now points to that file via `functions/firebase.json`.
- Deploy indexes with:
  - `cd functions`
  - `firebase deploy --only firestore:indexes`
- Missing-index errors now surface explicit console links in:
  - App logs: `lib/services/Activtity/Activity Instance Service/activity_instance_query_service.dart`
  - Cloud Function logs: `functions/functions/src/firestoreIndexLogger.ts`
