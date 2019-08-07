#!/bin/bash

MOVIE_DIR=$(pwd)
THUMBS_DIR="thumbs"
QUEUE_DIR="queue"
PROCESSED_DIR="processed"
REPORTED_DIR="reported"
SUBTITLES_DIR="subtitles"
DIR_CHUNK=1000
COUNTER_FILE="counter.txt"
REPORTING_URL="http://127.0.0.1:8000"
QUALITY=(1080 720 480 360)
Q1080=('1080' '9000k' '4500k')
Q720=('720' '5000k' '2500k')
Q480=('480' '2500k' '1250k')
Q360=('360' '1500k' '700k')

# check programs
if [[ -z "$(which ffmpeg)" ]]; then
  echo "Exception: ffmpeg is not installed"
  exit 1
fi

if [[ -z "$(which MP4Box)" ]]; then
  echo "Exception: MP4Box is not installed"
  exit 1
fi

if [[ -z "$(which montage)" ]]; then
  echo "Exception: montage is not installed"
  exit 1
fi

if [[ -z "$(which sed)" ]]; then
  echo "Exception: sed is not installed"
  exit 1
fi

if [[ -z "$(which curl)" ]]; then
  echo "Exception: curl is not installed"
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

  # if DASH directory does not exist then convert
  if [[ ! -d "${DASH_DIR}" ]]; then
    mkdir "${DASH_DIR}"

    # save original video file info
    ffmpeg -i "${ORIGINAL_FILE_FULL_NAME}" -hide_banner >"${DASH_DIR}/info.txt" 2>&1

    # move current mp4 file to queue directory
    mv "${f}" "${QUEUE_DIR}/${FILE_NAME}.mp4"
    echo "Converting \"$f\" to multi-bitrate video in MPEG-DASH"

    # audio channels count
    AUDIO_CHANNELS=$(ffmpeg -i "${MP4}" 2>&1 | grep Audio | wc -l)
    AUDIO_FILES=""

    for ((i = 1; i <= AUDIO_CHANNELS; i++)); do
      ffmpeg -y -i "${MP4}" -map "0:${i}" -c:a aac -ar 48000 -b:a 128k -vn "${FILE_NAME}_audio_$i.m4a"
      AUDIO_FILES+="${FILE_NAME}_audio_$i.m4a "
    done

    HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 ${MP4})
    VIDEO_FILES=""

    for q in "${QUALITY[@]}"; do
      if [[ ! HEIGHT > q ]]; then
        SCALE=Q$q[0]
        SCALE=${!SCALE}
        BUFFER=Q$q[1]
        BUFFER=${!BUFFER}
        BITRATE=Q$q[2]
        BITRATE=${!BITRATE}

        ffmpeg -hide_banner -y -i "${MP4}" \
          -preset ultrafast -tune film -vsync passthrough -write_tmcd 0 -an -c:v libx264 -profile:v main \
          -x264opts 'keyint=25:min-keyint=25:no-scenecut' -crf 23 \
          -maxrate ${BITRATE} -bufsize ${BUFFER} -pix_fmt yuv420p -vf "scale=-2:${SCALE}" -f mp4 "${FILE_NAME}_${SCALE}.mp4"

        VIDEO_FILES+="${FILE_NAME}_${SCALE}.mp4 "
      fi
    done

    MP4Box -dash 2000 -rap -frag-rap -bs-switching no -profile "dashavc264:live" ${VIDEO_FILES} ${AUDIO_FILES} -out "${DASH_DIR}/${FILE_NAME}.mpd"
    rm ${VIDEO_FILES} ${AUDIO_FILES}
  fi

  # if thumbs directory does not exist then make thumbs
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
    # get last two char of srt file as subtitle language (based on default convention, e.g. movie_EN.srt)
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
    rm "${MP4}"
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

    # if response header code is 200, move to reported directory
    if [[ "$STATUS" -eq 200 ]]; then
      mv "${PROCESSED_DIR}/${FILE_NAME}" "${REPORTED_DIR}/${SAVE_DIR}"
      mv "${PROCESSED_DIR}/${FILE_NAME}.mp4" "${REPORTED_DIR}/${SAVE_DIR}"
    fi
  fi
done