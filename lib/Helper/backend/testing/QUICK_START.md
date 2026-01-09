# Quick Start: Day Simulator Testing

## 🚀 How to Access Testing Tools

### Option 1: From Navigation Drawer
1. Open the app
2. Tap the hamburger menu (☰) in the top-left
3. Look for **"Testing Tools"** in the drawer (only visible in debug mode)
4. Tap to open the testing interface

### Option 2: From Progress Page
1. Navigate to the Progress page
2. Look for the **science icon (🧪)** in the top-right
3. Tap to open testing tools

## 🧪 Basic Testing Workflow

### Step 1: Start Simulation
1. Open Testing Tools
2. Click **"Start Simulation"** button
3. You'll see "SIMULATION MODE" indicator

### Step 2: Create Test Data
1. Go back to your app (don't close testing page)
2. Create some habits with different frequencies:
   - Daily habits (every day)
   - Weekly habits (every 2 days, every week)
   - Different categories and priorities
3. Create some tasks with various due dates

### Step 3: Simulate Day Completion
**Option A: Use Scenario Buttons**
- **Perfect Day** → All habits completed
- **Good Day** → Most completed, some partial
- **Mixed Day** → Some completed, some partial, some skipped
- **Bad Day** → Mostly partial or skipped
- **Lazy Day** → Everything skipped

**Option B: Manual Completion**
- Go to Queue page and manually complete habits
- Use the habit tracking interface normally

### Step 4: Advance to Next Day
1. In Testing Tools, click **"Next Day"**
2. This triggers day-end processing
3. All open habits are auto-closed
4. DailyProgressRecord is generated

### Step 5: Check Results
1. Go to **Progress page** to see:
   - Calendar heatmap with new data
   - 7-day trend chart
   - Daily history with completion percentages
2. Go to **Queue page** to see:
   - Only today's habits (yesterday's are closed)
   - Day-end countdown for habits
   - Recent completions section

## 🔄 Advanced Testing

### Simulate Multiple Days
1. **Advance 7 Days** → Fast forward a week
2. **Simulate Week** → Run a complete week with varied patterns
3. **Custom Scenarios** → Create specific completion patterns

### Test Different Patterns
```dart
// Perfect week
Day 1: Perfect Day
Day 2: Perfect Day  
Day 3: Perfect Day
Day 4: Perfect Day
Day 5: Perfect Day
Day 6: Perfect Day
Day 7: Perfect Day

// Realistic week
Day 1: Perfect Day
Day 2: Good Day
Day 3: Mixed Day
Day 4: Bad Day
Day 5: Lazy Day
Day 6: Good Day
Day 7: Perfect Day
```

## 📊 What to Verify

### ✅ Day-End Processing
- [ ] Habits auto-close at day-end
- [ ] Incomplete habits marked as 'skipped'
- [ ] Partial progress preserved (e.g., 6/8 glasses)
- [ ] DailyProgressRecord generated correctly

### ✅ Queue Page Behavior
- [ ] Habits only show for today
- [ ] Tasks show in Overdue when past due
- [ ] Day-end countdown works
- [ ] Recent completions populated

### ✅ Progress Page Analytics
- [ ] Calendar heatmap shows data
- [ ] 7-day trend chart displays
- [ ] Average calculations accurate
- [ ] Historical data immutable

### ✅ Historical Editing
- [ ] Can edit past 30 days
- [ ] Completion status changes work
- [ ] Progress value updates work
- [ ] DailyProgressRecord recalculates

## 🐛 Troubleshooting

### "No authenticated user" error
- Make sure you're logged in
- Check that user authentication is working

### Simulation not advancing
- Ensure you're in simulation mode
- Check that habits exist for current day
- Verify day-end processing completed

### Progress data not showing
- Run day-end processing for the dates
- Ensure habits were created before simulation
- Check that DailyProgressRecord was generated

### Reset Everything
- Click **"Reset Simulation"** to return to real time
- Or restart the app to clear simulation state

## 🎯 Testing Checklist

- [ ] Start simulation mode
- [ ] Create test habits and tasks
- [ ] Simulate different completion scenarios
- [ ] Advance multiple days
- [ ] Check Progress page analytics
- [ ] Verify Queue page behavior
- [ ] Test historical editing
- [ ] Reset simulation when done

## 💡 Pro Tips

1. **Start Simple** → Test with 2-3 habits first
2. **Use Scenarios** → Quick way to test different patterns
3. **Check Both Pages** → Queue and Progress show different aspects
4. **Test Edge Cases** → Partial completions, late completions, etc.
5. **Reset Often** → Clean slate for each test session

The Day Simulator gives you complete control over time progression, allowing you to thoroughly test the dual boundary system without waiting for actual day changes!
