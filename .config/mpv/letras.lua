-- Letras sincronizadas desde LRCLIB (lrclib.net) como subtítulos. Lo carga la función fish `musica`.
-- La ventana es opcional (force-window): cerrarla solo la oculta, la música sigue.
local utils = require 'mp.utils'
local archivos = {}

-- Con la ventana abierta se muestra la carátula (miniatura de YouTube) como pista de video;
-- cerrarla quita la imagen y la ventana, el audio no se toca.
local function ventana(abrir)
    if abrir then
        mp.set_property('force-window', 'yes'); mp.set_property('vid', '1')
    else
        mp.set_property('vid', 'no'); mp.set_property('force-window', 'no')
    end
end
mp.add_forced_key_binding('CLOSE_WIN', 'ocultar-ventana', function() ventana(false) end)
-- El popout de las ondas: echo '{"command":["script-message","ventana"]}' | socat - musica.sock
mp.register_script_message('ventana', function() ventana(mp.get_property('force-window') == 'no') end)

mp.register_event('file-loaded', function()
    local id = mp.get_property('path', ''):match('[?&]v=([%w_-]+)') or mp.get_property('path', ''):match('youtu%.be/([%w_-]+)')
    if not id then return end
    -- Con `musica -V` ya hay video de verdad: nada de carátula
    for _, t in ipairs(mp.get_property_native('track-list', {})) do
        if t.type == 'video' and not t.albumart then return end
    end
    -- hqdefault (480x360) trae franjas negras arriba y abajo: se recortan
    mp.set_property('video-crop', '480x270+0+45')
    mp.commandv('video-add', 'https://i.ytimg.com/vi/' .. id .. '/hqdefault.jpg',
        mp.get_property('force-window') == 'no' and 'auto' or 'select', 'Carátula')
end)

-- Radio: si es una sola canción de YouTube, se agrega su Mix (canciones parecidas) para que "siguiente" sirva.
-- En segundo plano porque yt-dlp tarda ~15 s en traer el Mix.
local radio = false
mp.register_event('file-loaded', function()
    if radio or mp.get_property_number('playlist-count', 1) > 1 then return end
    local id = mp.get_property('path', ''):match('[?&]v=([%w_-]+)') or mp.get_property('path', ''):match('youtu%.be/([%w_-]+)')
    if not id then return end
    radio = true
    mp.command_native_async({
        name = 'subprocess', capture_stdout = true, playback_only = false,
        args = { 'yt-dlp', '--flat-playlist', '--playlist-end', '50', '--print', 'id', 'https://www.youtube.com/watch?v=' .. id .. '&list=RD' .. id },
    }, function(_, r)
        -- Si ya se paró (playlist vacía), no revivirla con el Mix
        if mp.get_property_number('playlist-count', 0) == 0 then return end
        for otro in (r and r.stdout or ''):gmatch('[%w_-]+') do
            if otro ~= id then mp.commandv('loadfile', 'https://youtu.be/' .. otro, 'append') end
        end
    end)
end)

mp.register_event('file-loaded', function()
    local titulo = mp.get_property('media-title', '')
    if not titulo:find(' %- ') then titulo = mp.get_property('metadata/by-key/uploader', '') .. ' ' .. titulo end
    titulo = titulo:gsub('%b()', ''):gsub('%b[]', ''):gsub('[|｜].*', '')
        :gsub('[Oo]fficial.*', ''):gsub('[Ll]yrics?', ''):gsub('["“”]', '')
    local duracion = mp.get_property_number('duration', 0)
    local r = mp.command_native({
        name = 'subprocess', capture_stdout = true, playback_only = false,
        args = { 'curl', '-sf', '--max-time', '10', '--get',
                 '--data-urlencode', 'q=' .. titulo, 'https://lrclib.net/api/search' },
    })
    -- Varias versiones (video, álbum…): la de duración más parecida
    local mejor, dif = nil, math.huge
    for _, c in ipairs(utils.parse_json(r.stdout or '') or {}) do
        if type(c.syncedLyrics) == 'string' then
            local d = math.abs((c.duration or 0) - duracion)
            if d < dif then mejor, dif = c, d end
        end
    end
    if not mejor then return mp.osd_message('Sin letra sincronizada para: ' .. titulo, 6) end
    local ruta = os.tmpname() .. '.lrc'
    local f = io.open(ruta, 'w'); f:write(mejor.syncedLyrics); f:close()
    archivos[#archivos + 1] = ruta
    mp.commandv('sub-add', ruta, 'select', 'Letra')
end)

-- Al cerrarse mpv guarda canción y segundo para reanudar desde el ▶ de la barra (zenWaves)
local ultima = os.getenv('HOME') .. '/.local/state/musica-ultima'
-- (al llegar 'shutdown' ya no hay archivo cargado: se van guardando mientras suena)
local path, t
mp.observe_property('path', 'string', function(_, v) if v then path = v end end)
mp.observe_property('time-pos', 'number', function(_, v) if v then t = v end end)
-- ⏹ de la barra: apagar del todo, sin dejar nada para reanudar
mp.register_script_message('apagar', function() path = nil; os.remove(ultima); mp.command('quit') end)
mp.register_event('shutdown', function()
    if path and t then
        local f = io.open(ultima, 'w'); f:write(math.floor(t) .. '\t' .. path); f:close()
    end
    for _, ruta in ipairs(archivos) do os.remove(ruta); os.remove((ruta:gsub('%.lrc$', ''))) end
end)
