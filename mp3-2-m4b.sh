      
#!/bin/bash

# Script to convert all .mp3 files in a folder to a single chapterized M4B.
# Files are expected to be sorted by a numerical prefix (e.g., 0001 to 0181).

# --- Configuration ---
CURRENT_DIR_NAME=$(basename "$PWD")
BOOK_TITLE=""
AUTHOR=""

# Attempt to derive Book Title and Author from the current directory name
# First, clean the directory name a bit (remove common audiobook suffixes, underscores to spaces, trim)
CLEANED_DIR_NAME=$(echo "$CURRENT_DIR_NAME" | sed -E 's/ non-?abridged//I; s/ audiobook//I; s/[_]+/ /g; s/(^\s+|\s+$)//g')

# Try "Title - By Author" pattern
if [[ "$CLEANED_DIR_NAME" == *"- By "* ]]; then
    AUTHOR=$(echo "$CLEANED_DIR_NAME" | sed -E 's/.* - By //; s/(^\s+|\s+$)//g')
    BOOK_TITLE=$(echo "$CLEANED_DIR_NAME" | sed -E 's/ - By .*//; s/(^\s+|\s+$)//g')
# Else, try "Title by Author" pattern (greedy match for author part after the last " by ")
elif [[ "$CLEANED_DIR_NAME" == *" by "* ]]; then
    TEMP_AUTHOR=$(echo "$CLEANED_DIR_NAME" | sed -E 's/.* by //; s/(^\s+|\s+$)//g')
    # Check if what we extracted is a plausible author part and not the whole title or part of it.
    if [[ "$CLEANED_DIR_NAME" == *" by $TEMP_AUTHOR" ]]; then
        AUTHOR="$TEMP_AUTHOR"
        BOOK_TITLE=$(echo "$CLEANED_DIR_NAME" | sed -E "s/ by ${TEMP_AUTHOR}$//; s/(^\s+|\s+$)//g")
    else # " by " was likely part of the title, so just use the cleaned name as title
        BOOK_TITLE="$CLEANED_DIR_NAME"
    fi
else # No clear author pattern, use the cleaned directory name as the title
    BOOK_TITLE="$CLEANED_DIR_NAME"
fi

# Fallbacks and Prompts if auto-detection wasn't satisfactory
if [ -z "$BOOK_TITLE" ]; then
    echo "Could not automatically determine Book Title."
    read -p "Enter Book Title: " BOOK_TITLE_INPUT
    BOOK_TITLE=${BOOK_TITLE_INPUT:-"Untitled Audiobook"}
fi

if [ -z "$AUTHOR" ]; then
    echo "Could not automatically determine Author for '$BOOK_TITLE'."
    read -p "Enter Author name (or press Enter for 'Unknown Author'): " AUTHOR_INPUT
    AUTHOR=${AUTHOR_INPUT:-"Unknown Author"}
fi

OUTPUT_M4B_FILENAME="${BOOK_TITLE}.m4b" # Filename for the output M4B

# Temporary filenames (prefixed to avoid clashes)
METADATA_CHAPTER_FILE="makebook_ffmpeg_metadata_chapters.txt"
FFMPEG_INPUT_LIST_FILE="makebook_ffmpeg_input_files.txt"

# --- Sanity Checks & Setup ---
# Ensure ffmpeg and ffprobe are installed
if ! command -v ffmpeg &> /dev/null || ! command -v ffprobe &> /dev/null; then
    echo "Error: ffmpeg and ffprobe are required but not found. Please install them."
    exit 1
fi

# Clean up previous temporary files if they exist
rm -f "$METADATA_CHAPTER_FILE" "$FFMPEG_INPUT_LIST_FILE"

echo "--------------------------------------------------"
echo "Audiobook Creator"
echo "--------------------------------------------------"
echo "Current directory: $CURRENT_DIR_NAME"
echo "Book Title: $BOOK_TITLE"
echo "Author: $AUTHOR"
echo "Output M4B filename: $OUTPUT_M4B_FILENAME"
echo "--------------------------------------------------"

# --- Gather and Sort MP3 Files ---
echo "Looking for MP3 files..."
# Use find for robustness with filenames and sort them numerically. %f prints just the filename.
mapfile -t sorted_mp3_files < <(find . -maxdepth 1 -type f -name '*.mp3' -printf "%f\n" | sort -n)

if [ ${#sorted_mp3_files[@]} -eq 0 ]; then
    echo "No .mp3 files found in the current directory."
    rm -f "$METADATA_CHAPTER_FILE" "$FFMPEG_INPUT_LIST_FILE" # Clean up even if exiting early
    exit 1
fi

echo "Found ${#sorted_mp3_files[@]} MP3 files to process."

# --- Create FFmpeg Input File List ---
# This file tells ffmpeg which files to concatenate and in what order.
echo "ffconcat version 1.0" > "$FFMPEG_INPUT_LIST_FILE"
for mp3_file in "${sorted_mp3_files[@]}"; do
    # Add 'file' directive. Quote filenames for ffmpeg's concat demuxer.
    echo "file '$mp3_file'" >> "$FFMPEG_INPUT_LIST_FILE"
done
echo "FFmpeg input file list created: $FFMPEG_INPUT_LIST_FILE"

# --- Generate Chapter Metadata ---
echo "Generating chapter metadata..."
# Start the metadata file with global M4B tags
echo ";FFMETADATA1" > "$METADATA_CHAPTER_FILE"
echo "title=$BOOK_TITLE" >> "$METADATA_CHAPTER_FILE"
echo "artist=$AUTHOR" >> "$METADATA_CHAPTER_FILE"
echo "album_artist=$AUTHOR" >> "$METADATA_CHAPTER_FILE" # Often used for audiobooks
echo "genre=Audiobook" >> "$METADATA_CHAPTER_FILE"
echo "comment=Converted from MP3s using makebook.sh on $(date)" >> "$METADATA_CHAPTER_FILE"

# Initialize timing and chapter count for chapter generation
current_total_duration_ms=0
chapter_counter=1

for mp3_file in "${sorted_mp3_files[@]}"; do
    echo "Processing for chapter metadata: $mp3_file"

    file_duration_seconds=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mp3_file")

    if [ -z "$file_duration_seconds" ] || ! [[ "$file_duration_seconds" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Error: Could not get a valid duration for '$mp3_file'."
        echo "ffprobe output was: '$file_duration_seconds'"
        echo "Please check if the file is a valid MP3 and ffprobe is working correctly."
        rm -f "$METADATA_CHAPTER_FILE" "$FFMPEG_INPUT_LIST_FILE"
        exit 1
    fi

    file_duration_ms=$(awk -v dur_sec="$file_duration_seconds" 'BEGIN {printf "%.0f", dur_sec * 1000}')
    start_time_ms=$current_total_duration_ms
    end_time_ms=$(awk -v current_total_ms="$current_total_duration_ms" -v file_dur_ms="$file_duration_ms" 'BEGIN {printf "%.0f", current_total_ms + file_dur_ms}')
    current_chapter_title="Chapter $chapter_counter"

    echo "" >> "$METADATA_CHAPTER_FILE"
    echo "[CHAPTER]" >> "$METADATA_CHAPTER_FILE"
    echo "TIMEBASE=1/1000" >> "$METADATA_CHAPTER_FILE" # Timebase in milliseconds
    echo "START=$start_time_ms" >> "$METADATA_CHAPTER_FILE"
    echo "END=$end_time_ms" >> "$METADATA_CHAPTER_FILE"
    echo "title=$current_chapter_title" >> "$METADATA_CHAPTER_FILE"

    current_total_duration_ms=$end_time_ms
    chapter_counter=$((chapter_counter + 1))
done
echo "Chapter metadata generated: $METADATA_CHAPTER_FILE"

# --- Execute FFmpeg Conversion ---
echo "Starting M4B conversion. This may take a while..."
echo "Output file will be: $OUTPUT_M4B_FILENAME"

ffmpeg -y -f concat -safe 0 -i "$FFMPEG_INPUT_LIST_FILE" -i "$METADATA_CHAPTER_FILE" \
       -map_metadata 1 -c:a aac -b:a 96k -ar 44100 -ac 2 -vn "$OUTPUT_M4B_FILENAME"

# --- Finalization ---
if [ $? -eq 0 ]; then
    echo "--------------------------------------------------"
    echo "Successfully created M4B audiobook: $OUTPUT_M4B_FILENAME"
    echo "Cleaning up temporary files..."
    rm -f "$METADATA_CHAPTER_FILE" "$FFMPEG_INPUT_LIST_FILE"
    echo "Done."
else
    echo "--------------------------------------------------"
    echo "Error during M4B conversion. FFmpeg command failed."
    echo "Temporary files ($METADATA_CHAPTER_FILE, $FFMPEG_INPUT_LIST_FILE) were kept for inspection."
    exit 1
fi

echo "Script finished."

    