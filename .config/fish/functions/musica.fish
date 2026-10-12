function musica --description 'YouTube en segundo plano: musica [-v|-V] "nombre o link" | musica -q (parar)'
    argparse v/ventana V/video q/parar 'd/desde=' -- $argv; or return
    set -l sock $XDG_RUNTIME_DIR/musica.sock
    # Solo una canción a la vez: parar la anterior (también es lo que hace -q)
    echo '{"command":["quit"]}' | socat - $sock >/dev/null 2>&1
    set -q _flag_parar; and return

    set -l q (string join ' ' -- $argv)
    if test -z "$q"
        echo 'Uso: musica [-v|-V] "nombre o link"   (-v letra, -V video, -vV ambos; musica -q para)'
        return 1
    end
    string match -qr '^https?://' -- $q; or set q "ytdl://ytsearch:$q"
    set -l ventana no
    set -q _flag_ventana; and set ventana immediate
    # -V: video real (máx. 720p) en la ventana en vez de la carátula
    set -l vid no
    set -l formato bestaudio
    set -l tam 520x320
    if set -q _flag_video
        set ventana immediate; set vid auto; set tam 854x480
        set formato 'bestvideo[height<=720]+bestaudio/best'
    end
    # La letra solo con -v (con -V sola queda oculta; la tecla v de mpv la muestra)
    set -l letra yes
    set -q _flag_video; and not set -q _flag_ventana; and set letra no
    # Sin terminal: se controla desde las ondas de la barra o las teclas multimedia.
    # El popout de las ondas abre/oculta la ventana por el socket.
    set -l desde --start=(set -q _flag_desde; and echo $_flag_desde; or echo 0)
    setsid -f mpv $desde --vid=$vid --force-window=$ventana --geometry=$tam --wayland-app-id=musica \
        --input-ipc-server=$sock --background-color='#111111' \
        --ytdl-format=$formato --script=$HOME/.config/mpv/letras.lua \
        --sub-visibility=$letra --sub-align-y=center --sub-font-size=70 --sub-border-size=2 \
        --title='${media-title}' $q >$XDG_RUNTIME_DIR/musica.log 2>&1 </dev/null
    echo "Cargando… ya puedes cerrar la terminal (musica -q para parar; errores en $XDG_RUNTIME_DIR/musica.log)"
end
