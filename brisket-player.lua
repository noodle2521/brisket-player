local speaker = peripheral.find("speaker")
if (not speaker) then error("error: speaker not found") end

local success, urlPlayer = pcall(require, "urlPlayer")
if (not success) then
    shell.run("wget https://raw.githubusercontent.com/noodle2521/brisket-player/refs/heads/main/url-player.lua urlPlayer.lua")
    urlPlayer = require("urlPlayer")
end


local songListPath = "caches/song_list.txt"
local playlistsPath = "caches/playlists.txt"


-- cache tables
local songList = {}
local playlists = {}

local sortedPlaylists = {}

-- constants
local bytesPerSecond = 6000 -- 48kHz cc: tweaked speakers, dfpwm has 1 bit samples
local screenWidth = term.getSize()

--- ui variables
local uiLayer = 1
local pageOffset = 0
local songQueue = {}
local queuePos = 1
local currentPlaylist


local function updateCache(cacheTable, path)
	local cacheFile = fs.open(path, "w")

    for _, line in ipairs(cacheTable) do
        cacheFile.writeLine(table.concat(line, "|"))
    end

	cacheFile.close()
end

local function readCache(cacheTable, path)
    if (fs.exists(path)) then
        local file = fs.open(path, "r")
        local line = file.readLine()
        local i = 1
        while (line) do
            local entry = {}
            for str in string.gmatch(line, "[^%|]+") do
                table.insert(entry, str)
            end
            cacheTable[i] = entry
            
            line = file.readLine()
            i = i + 1
        end
    end
end

local function updatePlaylists(removedIndex)
    for i, line in ipairs(playlists) do
        local songInPlaylist = false

        -- binary search sorted playlist
        local sorted = sortedPlaylists[i]
        local k , j = 1, #sorted
        while (j > k) do
            if (sorted[k] == removedIndex or sorted[j] == removedIndex) then
                songInPlaylist = true
                break
            end

            local mid = math.floor(k + (j/2))
            if (removedIndex < mid) then
                j = mid - 1
            elseif (removedIndex > mid) then
                k = mid + 1
            else
                songInPlaylist = true
                break
            end
        end

        if (songInPlaylist) then
            local songs = { table.unpack(line, 2) }
            for i, song in ipairs(songs) do
                local id = tonumber(song)
                if (id > removedIndex) then
                    line[i] = id - 1;
                end
            end
        end
    end
end

-- generates new song queue from current playlist
local function refreshSongQueue()
    local currentSongIDs = { table.unpack(playlists[currentPlaylist], 2) }
    songQueue = {}
    for i, id in currentSongIDs do
        table.insert(songQueue, songList[id])
    end
end

-- *** WHETHER 0 IS LOWEST OR HIGHEST IN THE KEYS TABLE IS INCONSISTENT DEPENDING ON VERSION OF CC: TWEAKED
local function keyToDigit(key)
    if (keys.zero < keys.nine) then
        -- use zero-lowest ordering

        if (key < keys.zero or key > keys.nine) then
            --error("key is not a digit")
            return -1
        end

        return key - keys.zero
    else
        -- use zero-last ordering
        if (key < keys.one or key > keys.zero) then
            --error("key is not a digit")
            return -1
        end

        local num = key - keys.one + 1
        if (num == 10) then num = 0 end
        return num
    end
end


--- ui functions
local function songListUI()
    -- populate songQueue from current playlist
    refreshSongQueue()

    local playlistName = playlists[currentPlaylist][1]
    local maxSongPage = math.ceil(#songQueue / 10) - 1

    print(playlistName .. ":\n")
    if (#songQueue == 0) then
        print("none")
    else
        local start = (pageOffset) * 10 + 1
        for i = start, start + 9 do
            if (not songQueue[i]) then
                break
            end

            print(i .. ". " .. songQueue[i][1])
        end
    end

    print("\n\n1-0: play song, J,K: page down/up, A: add song, E: edit song, D: delete song, P: add to playlist, tab: playlists menu, X: exit")

    local event, key = os.pullEvent("key_up")
    local digit = keyToDigit(key)
    if (digit == 0) then
        digit = 10
    end
    if (digit >= 0 and #songQueue ~= 0) then
        local num = digit + (pageOffset * 10)

        if (songQueue[num]) then
            -- enter songPlayerUI
            uiLayer = 3
            queuePos = num
        end
    end
    -- jrop and klimb :relieved:
    if (key == keys.j) then
        pageOffset = math.min(pageOffset + 1, maxSongPage)
    end
    if (key == keys.k) then
        pageOffset = math.max(pageOffset - 1, 0)
    end
    if (key == keys.a) then
        term.clear()

        print("new song title (spaces fine, pls no | thats my string separator):")
        local input1 = read()
        if (input1 == "") then
            return
        end
        while (string.find(input1, "%|")) do
            print(">:(")
            input1 = read()
        end
        --songList[#songList+1][1] = input

        print("new song url (pls no | here either):")
        local input2 = read()
        if (input2 == "") then
            return
        end
        while (string.find(input2, "%|")) do
            print(">:(")
            input2 = read()
        end
        --songList[#songList+1][2] = input

        table.insert(songList, {input1, input2})
        table.insert(playlists[currentPlaylist], #songList)

        updateCache(songList, songListPath)
        updateCache(playlists, playlistsPath)
    end
    if (key == keys.e) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #songQueue > 0) then
            local num = _digit + (pageOffset * 10)

            if (songQueue[num]) then
                term.clear()

                print("new song title (spaces fine, pls no | thats my string separator):")
                local song = songList[playlists[currentPlaylist][num + 1]]
                local input1
                repeat
                    input1 = read()
                    if (input1 == "") then input1 = song[1] end
                until not string.find(input1, "%|")

                print("new song url (pls no | here either):")
                local input2
                repeat
                    input2 = read()
                    if (input2 == "") then input2 = song[2] end
                until not string.find(input2, "%|")
                
                songList[playlists[currentPlaylist][num + 1]] = {input1, input2}

                updateCache(songList, songListPath)
            end
        end
    end
    if (key == keys.d) then
        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #songQueue > 0) then
            local num = _digit + (pageOffset * 10)

            if (songQueue[num]) then
                print("removing " .. songQueue[num][1])
                table.remove(songList, playlists[currentPlaylist][num + 1])
                updateCache(songList, songListPath)
                updatePlaylists(playlists[currentPlaylist][num + 1])
                os.sleep(1)
            end
        end
    end
    if (key == keys.p) then
        if (#playlists == 0) then
            print("no playlists found")
            return
        end

        print("which one? (1-0)")
        local event, key = os.pullEvent("key_up")
        local _digit = keyToDigit(key)
        if (_digit == 0) then
            _digit = 10
        end
        if (_digit >= 0 and #songQueue > 0) then
            local num = _digit + (pageOffset * 10)

            if (songQueue[num]) then
                term.clear()

                local input
                repeat
                    print("to which playlist? (1-" .. #playlists .. ")")
                    input = tonumber(read())
                until playlists[input + 1]

                table.insert(playlists[input + 1], playlists[currentPlaylist][num])
                updateCache(playlists, playlistsPath)
            end
        end
    end
    if (key == keys.tab) then
        -- enter playlistsUI
        uiLayer = 2
    end
    if (key == keys.x) then
        uiLayer = 0
    end
end


local function playlistsUI()
    --
end


local function songPlayerUI()
    local title = songQueue[queuePos][1]
    local url = songQueue[queuePos][2]

    local allowSeek, audioByteLength = urlPlayer.pollUrl(url)
    if (allowSeek == nil) then
        return
    end

    local songLength = math.floor(audioByteLength / bytesPerSecond)

    local continue = false
    local shuffle = false
    local paused = false
    local playbackOffset = 0
    local lastChunkByteOffset = 0
    --local lastChunkTime = os.clock()

    local function playSong()
        if (not paused) then
            local interrupt = urlPlayer.playFromUrl(url, "song_interrupt", "chunk_queued", playbackOffset, allowSeek, audioByteLength)
            if (not interrupt) then
                if (queuePos < #songQueue) then
                    queuePos = queuePos + 1
                else
                    queuePos = 1
                end
            end
        else
            os.pullEvent("song_interrupt")
        end
    end
    
    local function updateLastChunk()
        while true do
            _, lastChunkByteOffset, _ = os.pullEvent("chunk_queued")
            lastChunkByteOffset = math.max(lastChunkByteOffset - urlPlayer.chunkSize, 0) -- awful nightmare duct tape solution to fix pausing but it is what it is
        end
    end

    local function seek(newOffset)
        if (allowSeek) then
            os.queueEvent("song_interrupt")

            local clampedOffset = math.max(0, math.min(newOffset, audioByteLength - 1))
            playbackOffset = clampedOffset

            lastChunkByteOffset = clampedOffset
            --lastChunkTime = os.clock()
        end
    end

    local function songUI()
        continue = false

        local key, keyPressed
        local timer = os.startTimer(1)

        local function pullKeyEvent()
            local _
            _, key = os.pullEvent("key_up")
            keyPressed = true
        end
        local function secondTimer()
            local _, id
            repeat
                _, id = os.pullEvent("timer")
            until (id == timer)

            timer = os.startTimer(1)
        end


        local prevTitle = songQueue[queuePos - 1][1] or songQueue[#songQueue][1]
        if (#prevTitle > 9) then
            prevTitle = string.sub(prevTitle, 1, 7) .. ".."
        end
        local nextTitle = songQueue[queuePos + 1][1] or songQueue[1][1]
        if (#nextTitle > 9) then
            nextTitle = string.sub(nextTitle, 1, 7) .. ".."
        end
        local queueString = "< " .. prevTitle .. string.rep(" ", screenWidth - #nextTitle - #prevTitle - 4) .. nextTitle .. " >"
        
        while true do
            repeat
                parallel.waitForAny(pullKeyEvent, secondTimer)
                term.clear()
                print(title)

                -- scrubber bar
                local songPos = math.floor((screenWidth - 2 - 1) * (lastChunkByteOffset / audioByteLength))
                print("\n|" .. string.rep("-", songPos) .. "o" .. string.rep("-", screenWidth - 2 - songPos - 1) .. "|")
                -- song time display
                local songTime = math.floor(lastChunkByteOffset / bytesPerSecond)
                print(string.format("%02d:%02d / %02d:%02d", math.floor(songTime / 60), math.floor(math.fmod(songTime, 60)), math.floor(songLength / 60), math.floor(math.fmod(songLength, 60))))

                print("\nspace: pause, 0-9: seek, A,D: back/forward 10s, J,K: prev/next song, R: shuffle(" .. (shuffle and "x" or " ") .. "), X: exit")

                print("\n\n" .. queueString)
            until keyPressed
            keyPressed = false


            local digit = keyToDigit(key)
            if (digit >= 0) then
                local newOffset = math.floor((digit / 10) * audioByteLength)
                seek(newOffset)
            end
            if (key == keys.space) then
                paused = not paused
                if (paused) then
                    seek(lastChunkByteOffset)
                else
                    os.queueEvent("song_interrupt")
                end
            end
            if (key == keys.a) then
                -- estimate offset of current playback
                --local currentOffset = lastChunkByteOffset + (6000 * (math.floor(os.clock()) - lastChunkTime))

                local newOffset = lastChunkByteOffset - (10 * 6000)
                seek(newOffset)
            end
            if (key == keys.d) then
                -- estimate offset of current playback
                --local currentOffset = lastChunkByteOffset + (6000 * (math.floor(os.clock()) - lastChunkTime))

                local newOffset = lastChunkByteOffset + (10 * 6000)
                seek(newOffset)
            end
            if (key == keys.j) then
                if (queuePos > 1) then
                    queuePos = queuePos - 1
                else
                    queuePos = #songQueue
                end

                os.queueEvent("song_interrupt")
                continue = true
            end
            if (key == keys.k) then
                if (queuePos < #songQueue) then
                    queuePos = queuePos + 1
                else
                    queuePos = 1
                end

                os.queueEvent("song_interrupt")
                continue = true
            end
            if (key == keys.r) then
                if (not shuffle) then
                    shuffle = true
                    --- shuffle queue, will be reset to regular order upon return to songListUI
                    -- remove current song from queue before shuffling
                    local song = songQueue[queuePos]
                    table.remove(songQueue, queuePos)
                    -- shuffle remaining queue (sort with random comparator lmao)
                    table.sort(songQueue, function(a, b) return (math.random() < 0.5) end)
                    -- insert current song at beginning of new queue
                    table.insert(songQueue, song, 1)
                    queuePos = 1
                else
                    shuffle = false
                    -- restore queue order from current playlist
                    refreshSongQueue()
                end
                
            end
            if (key == keys.x) then
                os.queueEvent("song_interrupt")
                uiLayer = 1
                continue = true
            end
        end
    end


    repeat
        parallel.waitForAny(playSong, songUI, updateLastChunk)
    until continue
    os.sleep(0.5)
end


---- main
-- read from song_list.txt if exists
readCache(songList, songListPath)

-- read from playlists.txt if exists
readCache(playlists, playlistsPath)

-- if playlists empty, build global playlist as first entry
if (#playlists == 0) then
    playlists[1] = {"songs"}
    for i=1, #songList do
        table.insert(playlists[1], i)
    end
end

-- generate sortedPlaylists for faster contains check
for i, line in ipairs(playlists) do
    local sortedLine = { table.unpack(line, 2) }
    table.sort(sortedLine)
    sortedPlaylists[i] = sortedLine
end

-- initialize with the global playlist open
currentPlaylist = 1


--- ui loop
while true do
    term.clear()

    if (uiLayer == 1) then
        songListUI()
    elseif (uiLayer == 2) then
        playlistsUI()
    elseif (uiLayer == 3) then
        songPlayerUI()
    else
        break
    end
end