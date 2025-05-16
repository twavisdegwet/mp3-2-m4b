# mp3-2-m4b.sh - Audiobook Creator Script

## Description

This script converts all `.mp3` files in the current directory into a single chapterized M4B audiobook file. The MP3 files should be sorted by a numerical prefix (e.g., 0001 to 0181). The script automatically derives book title and author from the directory name, with options for manual input if auto-detection fails.

## Features

- Automatically detects book title and author from directory name
- Creates chapter metadata based on each MP3 file's duration
- Combines all MP3 files into a single M4B audiobook
- Maintains proper audio quality (96k AAC encoding)
- Includes comprehensive error checking and reporting

## Requirements

- Bash shell
- FFmpeg with both `ffmpeg` and `ffprobe` commands available in PATH

## Installation

1. Ensure FFmpeg is installed:
   ```bash
   sudo apt-get install ffmpeg  # For Debian/Ubuntu systems
   ```
2. Copy this script to your desired location (e.g., `/usr/local/bin/mp3-2-m4b.sh`)
3. Make it executable:
   ```bash
   chmod +x mp3-2-m4b.sh
   ```

## Usage

1. Place all MP3 files in a directory, sorted numerically (0001.mp3, 0002.mp3, etc.)
2. Navigate to the directory containing your MP3 files
3. Run the script:
   ```bash
   ./mp3-2-m4b.sh
   ```
4. The output M4B file will be named after the book title with a `.m4b` extension

## Example Directory Structure

```
/book-title-by-author/
├── 0001.mp3
├── 0002.mp3
├── ...
└── 0181.mp3
```

When run in this directory, the script will create `book-title-by-author.m4b`.

