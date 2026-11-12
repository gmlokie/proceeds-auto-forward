#!/bin/bash
set -e
cd "$(dirname "$0")"; rm -rf seg; mkdir seg; : > list.txt
i=0
python3 -c "import json;[print(p,s) for p,s in json.load(open('segments.json'))]" | while read p s; do
  n=$(printf %02d $i)
  # fade only on scene changes (not between typewriter/loop sub-steps)
  b=$(basename $p .png); fi=0.35; fo=0.35
  case $b in *test_[0-5]|*_s2|*_s3) fi=0;; esac
  case $b in *test_a|*test_[0-5]|*_s1|*_s2) fo=0;; esac
  vf="format=yuv420p"
  [ "$fi" != 0 ] && vf="fade=t=in:st=0:d=$fi,$vf"
  [ "$fo" != 0 ] && vf="fade=t=out:st=$(python3 -c "print($s-$fo)"):d=$fo,$vf"
  ffmpeg -nostdin -loglevel error -y -loop 1 -framerate 30 -t $s -i $p -vf "$vf" -c:v libx264 -preset veryfast -crf 20 -r 30 -pix_fmt yuv420p seg/$n.mp4
  echo "file 'seg/$n.mp4'" >> list.txt; i=$((i+1))
done
ffmpeg -loglevel error -y -f concat -safe 0 -i list.txt -f lavfi -i anullsrc=r=48000:cl=stereo -shortest -c:v copy -c:a aac -b:a 64k -movflags +faststart ../demo.mp4
ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height -of compact ../demo.mp4
