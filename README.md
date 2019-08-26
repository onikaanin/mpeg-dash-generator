# MPEG-Dash Stream Generator Service

This script converts every mp4 (in the current) to a multi-bitrate video in mp4-dash
For each file "videoname.mp4", rename it based on file counter and creates a folder containing a dash manifest file "stream.mpd" and subfolders containing video segments.
Also, make thumbnails for every mp4 files that previously converted to dash playlist

# Requirement
* ffmpeg
* gpac
* imagemagick
* sed
* curl

**Install requirements:**

`sudo apt install ffmpeg gpac montage sed curl`

# Convert to MPEG-Dash
**<p>First make bash script executable:</p>**
`$ sudo chmod +x dash.sh`

**<p>Then run the script: </p>**
`$ ./dash.sh`

# Convert video file to MP4
**<p>Run this command:</p>**
`$ ffmpeg -i file.mkv -map_chapters -1 -map 0:v -map 0:a -c:v copy -c:a copy -sn file.mp4`

# MIME-TYPES Support
**<p>Add the following mime-types to .htaccess:</p>**
`AddType video/mp4 m4s `<br>
`AddType application/dash+xml mpd`
