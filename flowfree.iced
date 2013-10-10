#!/usr/bin/env iced
fs = require 'fs'
readline = require 'readline'
ansiterm = require './ansiterm'

debug = false
scroll = debug
display_frequency = 20
display_showoff = 1

# TODO merge segment_ends and endpoints
# TODO grid for endpoints
# TODO patterns
# TODO list of patterns affected by this tile?
# TODO disallow BLANK dead ends

Array::removeFirst = (v) ->
    i = @indexOf v
    if i >= 0
        @splice i, 1

WALL = -1
BLANK = 0
# RED = 1
# ...

matchFactory = (width) ->
    N = -width
    E = 1
    S = width
    W = -1
    NW = N + W
    NE = N + E
    SE = S + E
    SW = S + W
    NN = N + N
    EE = E + E
    SS = S + S
    WW = W + W
    NNN = NN + N
    EEE = EE + E
    SSS = SS + S
    WWW = WW + W
    NNW = NN + W
    NNE = NN + E
    NEE = N + EE
    SEE = S + EE
    SSE = SS + E
    SSW = SS + W
    SWW = S + WW
    NWW = N + WW
    patterns = [
        # unacceptable clumping
        {me:[N, NE, E], fail:true}
        {me:[NE, E, SE], fail:true}
        {me:[E, SE, S], fail:true}
        {me:[SE, S, SW], fail:true}
        {me:[S, SW, W], fail:true}
        {me:[SW, W, NW], fail:true}
        {me:[W, NW, N], fail:true}
        {me:[NW, N, NE], fail:true}
        # no exit
        {notvacant:[N, E, S, W], fail:true}
        # vacant dead ends
        {vacant:[NW], midsegment:[NWW, NNW, N], fail:true}
        {vacant:[NW], midsegment:[NWW, NNW, W], fail:true}
        {vacant:[NE], midsegment:[NEE, NNE, N], fail:true}
        {vacant:[NE], midsegment:[NEE, NNE, E], fail:true}
        {vacant:[SE], midsegment:[SEE, SSE, S], fail:true}
        {vacant:[SE], midsegment:[SEE, SSE, E], fail:true}
        {vacant:[SW], midsegment:[SWW, SSW, S], fail:true}
        {vacant:[SW], midsegment:[SWW, SSW, W], fail:true}
        # involuntary exit
        {vacant:[N], notvacant:[E, S, W]}
        {vacant:[N], notvacant:[E, S, W]}
        {vacant:[E], notvacant:[S, W, N]}
        {vacant:[E], notvacant:[S, W, N]}
        {vacant:[S], notvacant:[N, E, W]}
        {vacant:[S], notvacant:[N, E, W]}
        {vacant:[W], notvacant:[N, E, S]}
        {vacant:[W], notvacant:[N, E, S]}
        # only line capable of feeding this part of a dead-end
        {vacant:[N, NN], midsegment:[NE, NW], notme:[NE, NW]}
        {vacant:[E, EE], midsegment:[NE, SE], notme:[NE, SE]}
        {vacant:[S, SS], midsegment:[SE, SW], notme:[SE, SW]}
        {vacant:[W, WW], midsegment:[NW, SW], notme:[NW, SW]}
        # only line able to turn a nearby corner
        {vacant:[N, NW], midsegment:[NE, NN], notme:[W, NE, NN]}
        {vacant:[N, NE], midsegment:[NW, NN], notme:[E, NW, NN]}
        {vacant:[E, NE], midsegment:[SE, EE], notme:[N, SE, EE]}
        {vacant:[E, SE], midsegment:[NE, EE], notme:[S, NE, EE]}
        {vacant:[S, SE], midsegment:[SW, SS], notme:[E, SW, SS]}
        {vacant:[S, SW], midsegment:[SE, SS], notme:[W, SE, SS]}
        {vacant:[W, SW], midsegment:[NW, WW], notme:[S, NW, WW]}
        {vacant:[W, NW], midsegment:[SW, WW], notme:[N, SW, WW]}
        # only line able to turn a slightly further corner
        {vacant:[N, NN, NNW], midsegment:[NE, NNE, NNN], notme:[NW, NE, NNE, NNN]}
        {vacant:[N, NN, NNE], midsegment:[NW, NNW, NNN], notme:[NE, NW, NNW, NNN]}
        {vacant:[E, EE, NEE], midsegment:[SE, SEE, EEE], notme:[NE, SE, SEE, EEE]}
        {vacant:[E, EE, SEE], midsegment:[NE, NEE, EEE], notme:[SE, NE, NEE, EEE]}
        {vacant:[S, SS, SSE], midsegment:[SW, SSW, SSS], notme:[SE, SW, SSW, SSS]}
        {vacant:[S, SS, SSW], midsegment:[SE, SSE, SSS], notme:[SW, SE, SSE, SSS]}
        {vacant:[W, WW, SWW], midsegment:[NW, NWW, WWW], notme:[SW, NW, NWW, WWW]}
        {vacant:[W, WW, NWW], midsegment:[SW, SWW, WWW], notme:[NW, SW, SWW, WWW]}
        # bent
        {vacant:[N], midsegment:[W], me:[S, SE]}
        {vacant:[N], midsegment:[E], me:[S, SW]}
        {vacant:[E], midsegment:[S], me:[W, NW]}
        {vacant:[E], midsegment:[N], me:[W, SW]}
        {vacant:[S], midsegment:[E], me:[N, NW]}
        {vacant:[S], midsegment:[W], me:[N, NE]}
        {vacant:[W], midsegment:[N], me:[E, SE]}
        {vacant:[W], midsegment:[S], me:[E, NE]}
        # guesses
        {vacant:[N, E], notvacant:[S, W], go:[[N], [E]]}
        {vacant:[N, S], notvacant:[E, W], go:[[N], [S]]}
        {vacant:[N, W], notvacant:[S, E], go:[[N], [W]]}
        {vacant:[S, E], notvacant:[N, W], go:[[S], [E]]}
        {vacant:[S, W], notvacant:[N, E], go:[[S], [W]]}
        {vacant:[E, W], notvacant:[N, S], go:[[E], [W]]}
        {vacant:[N, E, S], notvacant:[W], go:[[N], [E], [S]]}
        {vacant:[E, S, W], notvacant:[N], go:[[E], [S], [W]]}
        {vacant:[S, W, N], notvacant:[E], go:[[S], [W], [N]]}
        {vacant:[W, N, E], notvacant:[S], go:[[W], [N], [E]]}
        {vacant:[N, E, S, W], go:[[N], [E], [S], [W]]}
    ]
    compile = (pattern) ->
        source = []
        if pattern.me?.length > 0 or pattern.notme?.length > 0
            source.push "var line = this.line_grid[tile];"
        for offset in pattern.me or []
                source.push "if (this.line_grid[tile + #{offset}] !== line) return;"
        for offset in pattern.notme or []
                source.push "if (this.line_grid[tile + #{offset}] === line) return;"
        for offset in pattern.vacant or []
            source.push "if (this.line_grid[tile + #{offset}] !== #{BLANK}) return;"
        for offset in pattern.notvacant or []
            source.push "if (this.line_grid[tile + #{offset}] === #{BLANK}) return;"
        for offset in pattern.midsegment or []
            # XXX segment_end_grid
            source.push "if (this.line_grid[tile + #{offset}] === #{BLANK}) return;"
            source.push "if (this.segment_ends.indexOf(tile + #{offset}) !== -1) return;"
        if pattern.fail
            source.push "return [];"
        else
            source.push "return #{JSON.stringify pattern.go or [pattern.vacant]};"
        return new Function 'tile', source.join ' '
    patterns = (compile(pattern) for pattern in patterns)
    return (tile) ->
        for pattern in patterns
            go = pattern.call @, tile
            return go if go

class Tiles
    constructor: (parent) ->
        #{@width, @height, @endpoint_grid, @match} = parent
        {@width, @height, @blanks, @match} = parent
        @line_grid = parent.line_grid.slice 0
        @segment_ends = parent.segment_ends.slice 0
        #@segment_end_grid = parent.segment_end_grid.slice 0
    set: (tile, line) ->
        #assert line isnt BLANK
        #assert line isnt WALL
        #assert @line_grid[tile] is BLANK
        --@blanks
        @line_grid[tile] = line
        # collapse adjacent segment ends
        neighbor_segment_ends = 0
        for offset in [-@width, @width, 1, -1]
            if @line_grid[tile + offset] is line
                if tile + offset in @segment_ends
                    ++neighbor_segment_ends
                    @segment_ends.removeFirst tile + offset
        unless neighbor_segment_ends is 2
            @segment_ends.push tile

puzzle_id = 0

class Puzzle
    constructor: (@size, @endpoints) ->
        #[red1, red2, green1, green2, ...]
        @n = ++puzzle_id
        @id = "#{@size}x#{@size} #{@endpoints}"
        @width = @height = @size + 2
        @segment_ends = []
        @blanks = 0
        @line_grid = new Array @width * @height
        for tile in [0...@height * @width]
            @line_grid[tile] = BLANK
        for col in [0...@width]
            @line_grid[col] = @line_grid[col + (@height - 1) * @width] = WALL
        for row in [0...@height]
            @line_grid[row * @width] = @line_grid[(row + 1) * @width - 1] = WALL
        for endpoint, i in @endpoints
            line = 1 + Math.floor i / 2
            @line_grid[endpoint] = line
            if i % 2 is 1
                better_half = @endpoints[i - 1]
                adjacent = (Math.abs better_half - endpoint is 1) or (Math.abs better_half - endpoint is @width)
                continue if adjacent
            @segment_ends.push endpoint
        @blanks = @size * @size - @endpoints.length
        #@endpoint_grid = new Array @width * @height
        #@segment_end_grid = new Array @width * @height
        @tiles = new Tiles @
        @stack = []
        @match = matchFactory @width
        @step = 0
        @start = null
        @elapsed = null
        @solutions = []
        @display_initialized = false
        @display_colors = [
            ansiterm.bg.black
            ansiterm.bg.reset
            ansiterm.bg.red
            ansiterm.bg.green
            ansiterm.bg.blue
            ansiterm.bg.yellow
            ansiterm.bg.orange
            ansiterm.bg.cyan
            ansiterm.bg.pink
            ansiterm.bg.dark_red
            ansiterm.bg.dark_magenta
            ansiterm.bg.white
            ansiterm.bg.grey
            ansiterm.bg.light_green
            ansiterm.bg.black # XXX PLACEHOLDER
        ]
    solve: (autocb) ->
        # maximally extends segments, somewhat balanced, but also preferring
        # recent or untested ends.
        @start = new Date
        #next_context_switch = @start + 500 / display_frequency
        loop
            tiles = @tiles
            hopeful = true
            mandatory_found = true
            # accumulate guesses, ordered by forkiness
            branches = [null, null, null]
            while hopeful and mandatory_found
                mandatory_found = false
                segment_index = 0
                while segment_index < tiles.segment_ends.length
                    tile = tiles.segment_ends[segment_index]
                    line = tiles.line_grid[tile]
                    matches = @match.call tiles, tile
                    console.log "tile #{tile} line #{line} si #{segment_index} hope #{hopeful} mf #{mandatory_found} matches #{JSON.stringify matches}" if debug
                    switch matches?.length or 0
                        when 0
                            hopeful = false
                        when 1
                            for offset in matches[0]
                                #console.log "    set #{tile} + #{offset}"
                                tiles.set tile + offset, line
                            @render() if debug
                            branches = [null, null, null]
                            mandatory_found = true
                        else
                            # save one (of each branchiness) for later
                            branches[matches.length - 2] or= [tile, line, matches]
                            segment_index++
                    break unless hopeful
                #console.log "mandatory restart"
            @render() if debug
            if hopeful and tiles.blanks > 0
                [tile, line, matches] = branches[0] or branches[1] or branches[2] or []
                hopeful = line?
                if hopeful
                    #console.log "    matches #{JSON.stringify matches}"
                    for offsets, i in matches
                        #console.log "    hypothesis #{i+1} of #{matches.length}: line #{line} tile #{tile} offsets #{JSON.stringify offsets}"
                        continue if i is 0
                        hypothesis = new Tiles tiles
                        for offset in offsets
                            #console.log "    set #{tile} + #{offset}"
                            hypothesis.set tile + offset, line
                        @stack.push hypothesis
                    # reuse current tile state
                    for offset in matches[0]
                        tiles.set tile + offset, line
            @render() if debug
            if hopeful and tiles.blanks is 0
                # solved!
                @solutions.push new Tiles @tiles
                hopeful = false
            unless hopeful
                #console.log "popping"
                @tiles = @stack.pop()
                break unless @tiles
            if debug
                await setTimeout defer(), 100
            else unless ++@step % 10000
                await setImmediate defer()
        @elapsed = new Date - @start
    render: (supplemental=[], screen_height=24) =>
        write = (data) -> process.stdout.write data
        unless @display_initialized or scroll
            @display_initialized = true
            write ansiterm.position()
            write ansiterm.eraseDisplay()
        write ansiterm.position() unless debug or scroll
        tiles = @tiles or @solutions?[0] or @
        for line, tile in tiles.line_grid
            write ansiterm.color @display_colors[line + 1]
            if tile in @endpoints
                write " () "
            else if tile in tiles.segment_ends
                write " -- "
            else
                write ansiterm.color ansiterm.fg.white
                write "    #{tile} "[-4..]
            if tile % @width is @width - 1
                write ansiterm.color()
                write "\n"
        write ansiterm.eraseDisplay()
        elapsed = @elapsed or (new Date - @start or 0) or 0
        if @best_time
            progress = "#{Math.round elapsed / @best_time} * 100}%"
        else
            progress = ""
        write "puzzle #{@n} step #{@step} stack #{@stack.length} solutions #{@solutions.length} elapsed #{elapsed}ms #{progress}\n"
        #write JSON.stringify tiles
        #write "\n"

parseSolution = (line) ->
    [summary, traces...] = line.split ';'
    [size, _, n, trace_count] = summary.split ','
    size = parseInt size
    width = size + 2
    endpoints = []
    for trace in traces
        trace = trace.split ','
        start = parseInt trace[0]
        end = parseInt trace[trace.length - 1]
        endpoints.push 1 + width + start + 2 * Math.floor(start / size)
        endpoints.push 1 + width + end + 2 * Math.floor(end / size)
    return new Puzzle size, endpoints

try
    timings = JSON.parse fs.readFileSync 'flowfree_timings.json'
catch e
    timings = {}

await
    lines = []
    rl = readline.createInterface input:process.stdin, terminal:false
    rl.on 'line', (line) ->
        lines.push line
    rl.on 'close', defer()

for line in lines
    await do (autocb=defer(done)) ->
        puzzle = parseSolution line
        puzzle.best_time = timings[puzzle.id]
        if display_frequency
            puzzle.render()
            interval = setInterval puzzle.render, 1000 / display_frequency
        await puzzle.solve defer()
        clearInterval interval
        puzzle.render()
        return true if puzzle.solutions.length < 1
        return true if debug and puzzle.solutions.length isnt 1
        await setTimeout defer(), display_showoff
    break if done
