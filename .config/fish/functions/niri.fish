# niri commit ["mensaje"]: guarda los cambios del escritorio en el repo de dotfiles (dot) y los sube.
# Cualquier otro subcomando (msg, validate...) va al niri real.
function niri --wraps niri
    if test "$argv[1]" != commit
        command niri $argv
        return
    end
    if test -z "$(dot status --porcelain)"
        echo "Nada que guardar."
        return 0
    end
    echo "Cambios:"
    dot status --short
    echo "(Los archivos nuevos no salen aquí: agrégalos antes con  dot add <ruta>)"
    set -l msg "$argv[2..]"
    test -n "$msg"; or read -P "Mensaje del commit (vacío = cancelar): " msg
    test -n "$msg"; or return 1
    dot add -u; and dot commit -m "$msg"; and dot push
end
