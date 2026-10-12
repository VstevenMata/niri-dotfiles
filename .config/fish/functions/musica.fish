function musica --description 'YouTube solo audio en segundo plano: musica [-v] "nombre o link" | musica -q (parar)'
    argparse v/ventana q/parar 'd/desde=' -- $argv; or return
    set -l sock $XDG_RUNTIME_DIR/musica.sock
    # Solo una canción a la vez: parar la anterior (también es lo que hace -q)
    echo '{"command":["quit"]}' | socat - $sock >/dev/null 2>&1
    set -q _flag_parar; and return

    set -l q (string join ' ' -- $argv)
    if test -z "$q"
        echo 'Uso: musica [-v] "nombre o link"   (-v abre la ventana de letra; musica -q para)'
        return 1
    end
    string match -qr '^https?://' -- $q; or set q "ytdl://ytsearch:$q"
    set -l ventana no
    set -q _flag_ventana; and set ventana immediate
    # Sin terminal: se controla desde las ondas de la barra o las teclas multimedia.
    # El popout de las ondas abre/oculta la ventana por el socket.
    set -l desde --start=(set -q _flag_desde; and echo $_flag_desde; or echo 0)
    setsid -f mpv $desde --vid=no --force-window=$ventana --geometry=520x320 --wayland-app-id=musica \
        --input-ipc-server=$sock --background-color='#111111' \
        --ytdl-format=bestaudio --script=$HOME/.config/mpv/letras.lua \
        --sub-align-y=center --sub-font-size=70 --sub-border-size=2 \
        --title='${media-title}' $q >$XDG_RUNTIME_DIR/musica.log 2>&1 </dev/null
    echo "Cargando… ya puedes cerrar la terminal (musica -q para parar; errores en $XDG_RUNTIME_DIR/musica.log)"
end
