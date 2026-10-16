#!/bin/bash
# Assemble the promo video from the rendered scenes.
#   bash scripts/promo/build-video.sh <scenes dir> <out.mp4>
# Each scene: 5 s with a slow zoom; 0.8 s crossfades; fade in/out; silent stereo track.
set -euo pipefail
scenes="$1"; out="$2"
fps=30; dur=5; xfade=0.8
files=("$scenes"/0*.png)
n=${#files[@]}
inputs=(); filter=""
for i in "${!files[@]}"; do
  inputs+=(-loop 1 -framerate "$fps" -t "$dur" -i "${files[$i]}")
  # Upscale first so the zoom has sub-pixel headroom, then zoom 1.00 -> 1.07 over the scene.
  filter+="[$i:v]scale=3840:2160,zoompan=z='1+0.07*on/($dur*$fps)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=$fps,format=yuv420p,setsar=1[v$i];"
done
prev="v0"
for ((i=1; i<n; i++)); do
  offset=$(python3 -c "print(round($i*$dur - $i*$xfade, 3))")
  label="x$i"; [ "$i" -eq $((n-1)) ] && label="xf"
  filter+="[$prev][v$i]xfade=transition=fade:duration=$xfade:offset=$offset[$label];"
  prev="$label"
done
total=$(python3 -c "print(round($n*$dur - ($n-1)*$xfade, 3))")
filter+="[$prev]fade=t=in:st=0:d=0.6,fade=t=out:st=$(python3 -c "print($total-0.8)"):d=0.8[vout]"
ffmpeg -y -loglevel error "${inputs[@]}" -f lavfi -t "$total" -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "$filter" -map "[vout]" -map "$n:a" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r "$fps" -c:a aac -b:a 64k -shortest -movflags +faststart "$out"
echo "wrote $out ($total s)"
