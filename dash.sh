#!/bin/bash

# THIS SCRIPT CONVERTS EVERY MP4 (IN THE CURRENT) TO A MULTI-BITRATE VIDEO IN MP4-DASH
# For each file "videoname.mp4", rename it based on file counter and creates a folder containing a dash manifest file "stream.mpd" and subfolders containing video segments.
# ALSO, MAKE THUMNAILS FOR EVERY MP4 FILES THAT PREVIOSLEY CONVERTED TO DASH PLAYLIST

# Add the following mime-types (uncommented) to .htaccess:
# AddType video/mp4 m4s
# AddType application/dash+xml mpd

MYDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
THUMBS_DIR="thumbs"
QUEUE_DIR="queue"
PROCESSED_DIR="processed"
DIR_CHUNK=1000
COUNTER_FILE="counter.txt"
SUBTITLES_DIR="subtitles"

# check programs
if [ -z "$(which ffmpeg)" ]; then
  echo "Error: ffmpeg is not installed"
  exit 1
fi

if [ -z "$(which MP4Box)" ]; then
  echo "Error: MP4Box is not installed"
  exit 1
fi

if [ -z "$(which montage)" ]; then
  echo "Error: montage is not installed"
  exit 1
fi

if [ -z "$(which xmlstarlet)" ]; then
  echo "Error: xmlstarlet is not installed"
  exit 1
fi

cd "$MYDIR" || exit

# check directories
if [ ! -d "${PROCESSED_DIR}" ]; then
  mkdir "${PROCESSED_DIR}"
fi

if [ ! -d "${QUEUE_DIR}" ]; then
  mkdir "${QUEUE_DIR}"
fi

if [ -f "${COUNTER_FILE}" ]; then
  COUNTER=$(<"${COUNTER_FILE}")
  SAVE_DIR=$(($((COUNTER / DIR_CHUNK)) + 1))
else
  echo 0 >"${COUNTER_FILE}"
  COUNTER=0
  SAVE_DIR="1"
fi

if [ ! -d "${PROCESSED_DIR}/${SAVE_DIR}" ]; then
  mkdir "${PROCESSED_DIR}/${SAVE_DIR}"
fi

# find mp4 files
TARGET_FILES=$(find ./ -maxdepth 1 -type f \( -name "*.mp4" \))

for f in $TARGET_FILES; do
  ORIGINAL_FILE_FULL_NAME=$(basename "$f") # fullname of the file
  ORIGINAL_FILE_NAME="${ORIGINAL_FILE_FULL_NAME%.*}" # name without extension

  FILE_NAME=$((COUNTER + 1))
  MP4="${QUEUE_DIR}/${FILE_NAME}.mp4"
  DASH_DIR="${QUEUE_DIR}/${FILE_NAME}"

  # if DASH directory does not exist, convert
  if [ ! -d "${DASH_DIR}" ]; then
    mkdir "${DASH_DIR}"

    # save original video file info
    ffmpeg -i "${ORIGINAL_FILE_FULL_NAME}" -hide_banner >"${DASH_DIR}/info.txt" 2>&1

    # move current mp4 file to queue directory
    mv "${f}" "${QUEUE_DIR}/${FILE_NAME}.mp4"
    echo "Converting \"$f\" to multi-bitrate video in MPEG-DASH"

    ffmpeg -y -i "${MP4}" -c:a aac -b:a 192k -vn "${DASH_DIR}/${FILE_NAME}_audio.m4a"
    ffmpeg -y -i "${MP4}" -preset ultrafast -tune film -vsync passthrough -write_tmcd 0 -an -c:v libx264 -x264opts 'keyint=25:min-keyint=25:no-scenecut' -crf 23 -maxrate 1500k -bufsize 3000k -pix_fmt yuv420p -vf "scale=-2:1080" -f mp4 "${FILE_NAME}_1080.mp4"
    ffmpeg -y -i "${MP4}" -preset ultrafast -tune film -vsync passthrough -write_tmcd 0 -an -c:v libx264 -x264opts 'keyint=25:min-keyint=25:no-scenecut' -crf 23 -maxrate 800k -bufsize 2000k -pix_fmt yuv420p -vf "scale=-2:720" -f mp4 "${FILE_NAME}_720.mp4"
    ffmpeg -y -i "${MP4}" -preset ultrafast -tune film -vsync passthrough -write_tmcd 0 -an -c:v libx264 -x264opts 'keyint=25:min-keyint=25:no-scenecut' -crf 23 -maxrate 400k -bufsize 1000k -pix_fmt yuv420p -vf "scale=-2:480" -f mp4 "${FILE_NAME}_480.mp4"
    # static file for ios and old browsers and mobile safari
    # ffmpeg -y -i "${MP4}" -preset ultrafast -tune film -movflags +faststart -vsync passthrough -write_tmcd 0 -c:a aac -b:a 160k -c:v libx264 -crf 23 -maxrate 2000k -bufsize 4000k -pix_fmt yuv420p -f mp4 "${DASH_DIR}/${FILE_NAME}.mp4"

    # if audio stream does not exist, ignore it
    if [ -e "${FILE_NAME}_audio.m4a" ]; then
      MP4Box -dash 2000 -rap -frag-rap -bs-switching no -profile "dashavc264:live" "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4" "${FILE_NAME}_audio.m4a" -out "${DASH_DIR}/${FILE_NAME}.mpd"
      rm "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4" "${FILE_NAME}_audio.m4a"
    else
      MP4Box -dash 2000 -rap -frag-rap -bs-switching no -profile "dashavc264:live" "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4" -out "${DASH_DIR}/${FILE_NAME}.mpd"
      rm "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4"
    fi
  fi

  # TODO: CHECK THAT LAST CHUNK HAS MORE THAN 0 BYTE

  # if thumbs directory does not exist, make thumbs
  if [ ! -d "${DASH_DIR}/${THUMBS_DIR}" ]; then
    mkdir "${DASH_DIR}/${THUMBS_DIR}"
    echo "Making thumbnails for \"$f\""
    ffmpeg -i "${MP4}" -s 160x90 -vf fps=1/10 "${DASH_DIR}/${THUMBS_DIR}/thumb-%04d.jpg"
    montage -tile 10x -mode concatenate "${DASH_DIR}/${THUMBS_DIR}/*.jpg" "${DASH_DIR}/${THUMBS_DIR}/preview.jpg"
  fi

  # find all srt files that have same name of original video
  SUB_FILES=$(find ./ -maxdepth 1 -type f \( -name "${ORIGINAL_FILE_NAME}_*.srt" \))

  if [ ! -d "${DASH_DIR}/${SUBTITLES_DIR}" ]; then
    mkdir "${DASH_DIR}/${SUBTITLES_DIR}"
  fi

  for subtitle in $SUB_FILES; do
    SUBTITLE_NAME="${subtitle%.*}" # name without extension
    # get last two char of srt file as subtitle language (based on default condition)
    SUB_LANG=${SUBTITLE_NAME:(-2)}
    # convert srt to vtt
    ffmpeg -i "${subtitle}" "${FILE_NAME}_${SUB_LANG}.vtt"

    # move vtt file to subtitles directory
    mv "${FILE_NAME}_${SUB_LANG}.vtt" "${DASH_DIR}/${SUBTITLES_DIR}/${FILE_NAME}_${SUB_LANG}.vtt"
    rm "${subtitle}"

    # append subtitle node to DASH mpd file
    APPEND="<AdaptationSet mimeType=\"text\/vtt\" lang=\"${SUB_LANG}\"><Representation id=\"caption_${SUB_LANG}\" bandwidth=\"256\"><BaseURL>${SUBTITLES_DIR}/${FILE_NAME}_${SUB_LANG}.vtt<\/BaseURL><\/Representation><\/AdaptationSet>"
    sed -i "/<\/Period>/i $APPEND" "${DASH_DIR}/${FILE_NAME}.mpd"
  done

  # if preview sprite generated, move DASH to processed directory and increase counter
  #if [ -f "${DASH_DIR}/${THUMBS_DIR}/preview.jpg" ]; then
    mv "${DASH_DIR}" "${PROCESSED_DIR}/${SAVE_DIR}"
    mv "${MP4}" "${PROCESSED_DIR}/${SAVE_DIR}"
    COUNTER=$((COUNTER + 1))
    echo ${COUNTER} >"${COUNTER_FILE}"
  #fi
done
