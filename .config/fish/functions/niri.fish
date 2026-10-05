# niri commit: muestra los pasos para guardar la config en el repo de dotfiles (no ejecuta nada).
# Cualquier otro subcomando (msg, validate...) va al niri real.
function niri --wraps niri
    if test "$argv[1]" != commit
        command niri $argv
        return
    end
    echo "Pasos para subir los cambios del escritorio:

  1. dot status                  ver qué cambió
  2. dot diff                    ver las líneas cambiadas (opcional)
  3. dot add -u                  preparar los archivos ya registrados
     dot add ~/ruta/al/archivo   archivo nuevo (siempre con ~/)
  4. dot commit -m \"mensaje\"     crear el commit
  5. dot push                    subir a GitHub

  Si editaste algo en github.com: dot pull antes del push."
end
