#!/bin/bash
# Mix narration (vo/narration.wav, from build_vo.py --mix) with the synthesized bed (vo/bed.wav, music.py)
# and mux onto the slide video (../demo.mp4 from assemble.sh). Voice ~-16 LUFS; bed ~-34 LUFS alone and
# side-chain ducked ~6-8 dB while the voice speaks (so it sits ~22-26 dB under the narration).
set -e
cd "$(dirname "$0")"
lufs() { ffmpeg -hide_banner -nostats -i "$1" -af ebur128 -f null - 2>&1 | awk '/I:/{v=$2} END{print v}'; }
VI=$(lufs vo/narration.wav); BI=$(lufs vo/bed.wav)
VG=$(python3 -c "print(-16-($VI))"); BG=$(python3 -c "print(-34-($BI))")
echo "narration $VI LUFS (gain $VG dB), bed $BI LUFS (gain $BG dB)"
ffmpeg -v error -y -i vo/narration.wav -i vo/bed.wav -filter_complex "\
[0:a]volume=${VG}dB,aformat=channel_layouts=stereo,asplit=2[v][sc];\
[1:a]volume=${BG}dB[b];\
[b][sc]sidechaincompress=threshold=0.02:ratio=6:attack=80:release=600:makeup=1[bd];\
[v][bd]amix=inputs=2:normalize=0,alimiter=limit=0.89:level=false[out]" -map "[out]" -ar 48000 vo/final_mix.wav
echo "mix $(lufs vo/final_mix.wav) LUFS"
cp ../demo.mp4 vo/video_silent.mp4
ffmpeg -v error -y -i vo/video_silent.mp4 -i vo/final_mix.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 160k \
  -shortest -movflags +faststart ../demo.mp4
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name -of compact ../demo.mp4
