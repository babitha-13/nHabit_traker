# Simple Day Advancer - Testing Guide

## 🎯 What This Does

The Simple Day Advancer is a straightforward testing tool that:
1. **Advances the date** by one day
2. **Triggers day-end processing** for the current date
3. **Generates progress data** that shows up in your Progress page

## 🚀 How to Use

### Step 1: Access Testing Tools
- **Option A:** Tap hamburger menu (☰) → "Testing Tools"
- **Option B:** Go to Progress page → Tap science icon (🧪)

### Step 2: Create Test Data
1. Go to your app and create some habits
2. Set different frequencies (daily, every 2 days, weekly)
3. Complete or partially complete the habits manually

### Step 3: Advance Day
1. In Testing Tools, click **"Advance Day"**
2. This will:
   - Process day-end for the current date
   - Close all open habits (mark incomplete as 'skipped')
   - Generate a DailyProgressRecord
   - Advance to the next day

### Step 4: Check Results
1. Go to **Progress page** to see:
   - New historical data point
   - Updated calendar heatmap
   - Progress statistics
2. Go to **Queue page** to see:
   - Only today's habits (yesterday's are closed)
   - Day-end countdown

## 🔄 Testing Workflow

```
1. Create habits → 2. Complete manually → 3. Advance day → 4. Check results
```

### Example Test Session:
1. **Create 3 habits:** "Workout", "Drink 8 glasses", "Meditation"
2. **Complete 2 fully:** Workout ✓, Meditation ✓
3. **Partial complete 1:** Drink 6/8 glasses
4. **Advance day** → Click "Advance Day"
5. **Check Progress page** → Should show ~67% completion for that day
6. **Repeat** → Create new habits for next day, complete them, advance again

## 📊 What You'll See

### Progress Page Results:
- **Calendar heatmap** → Color-coded squares showing daily completion %
- **7-day trend** → Bar chart showing target vs earned points
- **Daily history** → List of days with completion percentages
- **Average statistics** → 7-day and 30-day averages

### Queue Page Changes:
- **Today section** → Only shows current day's habits
- **Recent completions** → Shows yesterday's completed habits
- **Day-end countdown** → Shows time until day ends

## 🛠️ Troubleshooting

### "No authenticated user" error
- Make sure you're logged in to the app

### Progress data not showing
- Ensure you completed some habits before advancing
- Check that habits were created for the current date
- Try refreshing the Progress page

### Date not advancing
- Check the console for error messages
- Make sure you have an active internet connection
- Try the "Reset" button to start fresh

## 💡 Pro Tips

1. **Start Simple** → Test with 2-3 habits first
2. **Mix Completion Types** → Some full, some partial, some skipped
3. **Check Both Pages** → Queue shows current state, Progress shows history
4. **Reset When Done** → Use "Reset" button to return to real time
5. **Test Multiple Days** → Advance several days to see trends

## 🎯 What to Verify

- [ ] Habits auto-close at day-end
- [ ] Incomplete habits marked as 'skipped'
- [ ] Partial progress preserved (e.g., 6/8 glasses)
- [ ] DailyProgressRecord generated correctly
- [ ] Progress page shows new data
- [ ] Queue page shows only today's habits
- [ ] Historical data is accurate

The Simple Day Advancer gives you direct control over day-end processing without any complex simulation modes. Just create habits, complete them, and advance the day to see the results!
