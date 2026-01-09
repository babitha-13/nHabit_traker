# Sound Files for Habit Tracker

This directory should contain the following sound files for user interaction feedback:

## Required Sound Files

1. **completion.mp3** - Plays when:
   - Binary habit is completed (ticked)
   - Binary habit is uncompleted (unticked)
   - Step counter reaches its target

2. **step_counter.mp3** - Plays when:
   - Step counter is incremented or decremented
   - Any quantitative progress is updated

3. **play_button.mp3** - Plays when:
   - Timer is started
   - Timer is resumed

4. **stop_button.mp3** - Plays when:
   - Timer is stopped
   - Timer is paused

## File Format

- Format: MP3
- Recommended: Short, pleasant sounds (0.5-1 second duration)
- Volume: Moderate (not too loud or too quiet)

## Adding Sound Files

1. Place your sound files in this directory (`assets/audios/`)
2. Ensure the files are named exactly as listed above
3. The app will automatically load and play these sounds when the corresponding actions occur

## Note

If sound files are missing, the app will continue to work normally without playing sounds. The sound helper will gracefully handle missing files.

