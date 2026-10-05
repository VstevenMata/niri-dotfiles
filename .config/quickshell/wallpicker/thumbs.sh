#!/bin/sh
# Genera miniaturas (solo las nuevas o cambiadas) en paralelo: $1 = carpeta de fondos, $2 = caché
mkdir -p "$2"
for f in "$1"/*; do
    [ "$2/${f##*/}.jpg" -nt "$f" ] || printf '%s\0' "$f"
done | xargs -0 -r -P "$(nproc)" -I{} sh -c 'magick "$1[0]" -thumbnail 800x500^ -quality 85 "$2/${1##*/}.jpg"' _ {} "$2"
