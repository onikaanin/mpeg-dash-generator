#!/bin/bash

# BASH_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
MOVIE_DIR=$(pwd)
THUMBS_DIR="thumbs"
QUEUE_DIR="queue"
PROCESSED_DIR="processed"
REPORTED_DIR="reported"
SUBTITLES_DIR="subtitles"
DIR_CHUNK=1000
COUNTER_FILE="counter.txt"
REPORTING_URL="http://127.0.0.1:8000/api/v1/video"

# check programs
if [[ -z "$(which ffmpeg)" ]]; then
  echo "Error: ffmpeg is not installed"
  exit 1
fi

if [[ -z "$(which MP4Box)" ]]; then
  echo "Error: MP4Box is not installed"
  exit 1
fi

if [[ -z "$(which montage)" ]]; then
  echo "Error: montage is not installed"
  exit 1
fi

if [[ -z "$(which sed)" ]]; then
  echo "Error: sed is not installed"
  exit 1
fi

if [[ -z "$(which curl)" ]]; then
  echo "Error: curl is not installed"
  exit 1
fi

cd "$MOVIE_DIR" || exit

# check directories
if [[ ! -d "${PROCESSED_DIR}" ]]; then
  mkdir "${PROCESSED_DIR}"
fi

if [[ ! -d "${REPORTED_DIR}" ]]; then
  mkdir "${REPORTED_DIR}"
fi

if [[ ! -d "${QUEUE_DIR}" ]]; then
  mkdir "${QUEUE_DIR}"
fi

if [[ ! -f "${COUNTER_FILE}" ]]; then
  echo 0 >"${COUNTER_FILE}"
  COUNTER=0
  SAVE_DIR="1"
fi

# find mp4 files
TARGET_FILES=$(find ./ -maxdepth 1 -type f \( -name "*.mp4" \))

for f in ${TARGET_FILES}; do
  COUNTER=$(<"${COUNTER_FILE}")
  SAVE_DIR=$(($((COUNTER / DIR_CHUNK)) + 1))

  if [[ ! -d "${REPORTED_DIR}/${SAVE_DIR}" ]]; then
    mkdir "${REPORTED_DIR}/${SAVE_DIR}"
  fi

  ORIGINAL_FILE_FULL_NAME=$(basename "$f")           # full ame of the file
  ORIGINAL_FILE_NAME="${ORIGINAL_FILE_FULL_NAME%.*}" # name without extension

  FILE_NAME=$((COUNTER + 1))
  MP4="${QUEUE_DIR}/${FILE_NAME}.mp4"
  DASH_DIR="${QUEUE_DIR}/${FILE_NAME}"

  # if DASH directory does not exist, convert
  if [[ ! -d "${DASH_DIR}" ]]; then
    mkdir "${DASH_DIR}"

    # save original video file info
    ffmpeg -i "${ORIGINAL_FILE_FULL_NAME}" -hide_banner >"${DASH_DIR}/info.txt" 2>&1

    # move current mp4 file to queue directory
    mv "${f}" "${QUEUE_DIR}/${FILE_NAME}.mp4"
    echo "Converting \"$f\" to multi-bitrate video in MPEG-DASH"

    # count audio channels
    AUDIO_CHANNELS=$(ffmpeg -i "${MP4}" 2>&1 | grep Audio | wc -l)
    AUDIO_FILES=""

    for ((i = 1; i <= AUDIO_CHANNELS; i++)); do
      ffmpeg -y -i "${MP4}" -map "0:${i}" -c:a aac -ar 48000 -b:a 128k -vn "${FILE_NAME}_audio_$i.m4a"
      AUDIO_FILES+="${FILE_NAME}_audio_$i.m4a "
    done

    ffmpeg -hide_banner -y -i "${MP4}" \
      -vf "scale=-2:360" -an -c:v h264 -profile:v main -crf 20 -sc_threshold 0 -g 48 -keyint_min 48 -b:v 800k -maxrate 856k -bufsize 1200k -f mp4 "${FILE_NAME}_360.mp4" \
      -vf "scale=-2:480" -an -c:v h264 -profile:v main -crf 20 -sc_threshold 0 -g 48 -keyint_min 48 -b:v 1400k -maxrate 1498k -bufsize 2100k -f mp4 "${FILE_NAME}_480.mp4" \
      -vf "scale=-2:720" -an -c:v h264 -profile:v main -crf 20 -sc_threshold 0 -g 48 -keyint_min 48 -b:v 2800k -maxrate 2996k -bufsize 4200k -f mp4 "${FILE_NAME}_720.mp4" \
      -vf "scale=-2:1080" -an -c:v h264 -profile:v main -crf 20 -sc_threshold 0 -g 48 -keyint_min 48 -b:v 5000k -maxrate 5350k -bufsize 7500k -f mp4 "${FILE_NAME}_1080.mp4"

    MP4Box -dash 2000 -bs-switching multi -profile "dashavc264:live" "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4" "${FILE_NAME}_360.mp4" ${AUDIO_FILES} -out "${DASH_DIR}/${FILE_NAME}.mpd"
    rm "${FILE_NAME}_1080.mp4" "${FILE_NAME}_720.mp4" "${FILE_NAME}_480.mp4" "${FILE_NAME}_360.mp4" ${AUDIO_FILES}
  fi

  # TODO: CHECK THAT LAST CHUNK HAS MORE THAN 0 BYTE

  # if thumbs directory does not exist, make thumbs
  if [[ ! -d "${DASH_DIR}/${THUMBS_DIR}" ]]; then
    mkdir "${DASH_DIR}/${THUMBS_DIR}"
    echo "Making thumbnails for \"$f\""
    ffmpeg -i "${MP4}" -s 160x90 -vf fps=1/10 "${DASH_DIR}/${THUMBS_DIR}/thumb-%04d.jpg"
    montage -tile 10x -mode concatenate "${DASH_DIR}/${THUMBS_DIR}/*.jpg" "${DASH_DIR}/${THUMBS_DIR}/preview.jpg"
  fi

  # find all srt files that have same name of original video
  SUB_FILES=$(find ./ -maxdepth 1 -type f \( -name "${ORIGINAL_FILE_NAME}_*.srt" \))

  if [[ ! -d "${DASH_DIR}/${SUBTITLES_DIR}" ]]; then
    mkdir "${DASH_DIR}/${SUBTITLES_DIR}"
  fi

  for subtitle in ${SUB_FILES}; do
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
  if [[ -f "${DASH_DIR}/${THUMBS_DIR}/preview.jpg" ]]; then
    mv "${DASH_DIR}" "${PROCESSED_DIR}"
    mv "${MP4}" "${PROCESSED_DIR}"
    #    rm "${MP4}"
    COUNTER=$((COUNTER + 1))
    echo ${COUNTER} >"${COUNTER_FILE}"

    # curl service to insert movie into database
    STATUS=$(curl -i -X POST \
      -F "name=${FILE_NAME}" \
      -F "manifest=${SAVE_DIR}/${FILE_NAME}/${FILE_NAME}.mpd" \
      -F "preview=${SAVE_DIR}/${FILE_NAME}/${THUMBS_DIR}/preview.jpg" \
      -F "info=@${PROCESSED_DIR}/${FILE_NAME}/info.txt" \
      --url ${REPORTING_URL} \
      --output "${PROCESSED_DIR}/${FILE_NAME}/response.txt" -w "%{http_code}")

    # if response header code is 201, move to reported directory
    if [[ "$STATUS" -eq 201 ]]; then
      mv "${PROCESSED_DIR}/${FILE_NAME}" "${REPORTED_DIR}/${SAVE_DIR}"
      mv "${PROCESSED_DIR}/${FILE_NAME}.mp4" "${REPORTED_DIR}/${SAVE_DIR}"
    fi
  fi
done
