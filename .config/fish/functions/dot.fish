# git de los dotfiles (repo bare en ~/.dotfiles, archivos en su lugar en ~): dot status, dot add, dot commit...
function dot --wraps git
    git --git-dir=$HOME/.dotfiles --work-tree=$HOME $argv
end
