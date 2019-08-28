# MPEG-Dash Generator Script

This script converts MP4 video files to multi-bitrate videos based on MPEG-DASH, is an adaptive bitrate streaming technique that enables high quality streaming of media content over the Internet delivered from conventional HTTP web servers.

## Features
* Generate MPEG-DASH manifest file (MPD)
* Generate multi-bitrate videos
* Generate multiple audio channels
* Generate video thumbnails
* Generate VTT subtitles
* Send processed video info to third-party service by cURL

## Requirement
* ffmpeg
* gpac
* imagemagick (montage)
* sed
* curl

## Convert to MPEG-Dash
**<p>1. First make bash script executable:</p>**
`$ sudo chmod +x dash.sh`

**<p>2. Move your MP4 video files to the root of the project. Note that the file names are without spaces. If your file is not a MP4 video format (e.g. MKV file), convert it using the following command:</p>**
`$ ffmpeg -i file.mkv -map_chapters -1 -map 0:v -map 0:a -c:v copy -c:a copy -sn file.mp4`

**<p>3. Put your SRT subtitle files with the same name as the video file and in the following format next to the video (Optional):</p>**
````
{VIDEO_NAME}_{LANG}.srt
e.g. movie_EN.srt
````

**<p>4. Then run the script: </p>**
`$ ./dash.sh`

### MIME-TYPES Support
**<p>Add the following mime-types to .htaccess:</p>**
`AddType video/mp4 m4s `<br>
`AddType application/dash+xml mpd`
