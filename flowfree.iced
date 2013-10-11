#!/usr/bin/env iced
fs = require 'fs'
readline = require 'readline'
ansiterm = require './ansiterm'

debug = false
scroll = debug
display_frequency = 20
display_showoff = 1

# TODO apply failure rules after segment join?
# TODO list of patterns affected by this tile?

Array::removeFirst = (v) ->
    i = @indexOf v
    if i >= 0
        @splice i, 1

WALL = -1
BLANK = 0
# RED = 1
# ...

class Tiles
    constructor: (parent) ->
        {@width, @height, @blanks, @match, @mandatory_patterns, @failure_patterns, @guess_patterns} = parent
        @line_grid = parent.line_grid.slice 0
        @segment_ends = parent.segment_ends.slice 0
    set: (tile, line) ->
        #assert line isnt BLANK
        #assert line isnt WALL
        #assert @line_grid[tile] is BLANK
        #assert tile not in @segment_ends
        --@blanks
        @line_grid[tile] = line
        # collapse N segment end(s):
        #     1    -> move to me
        #     2    -> remove both
        #     3, 4 -> add me
        neighbor_segment_ends = 0
        for offset in [-@width, @width, 1, -1]
            if @line_grid[tile + offset] is line
                i = @segment_ends.indexOf tile + offset
                if i isnt -1
                    if ++neighbor_segment_ends is 1
                        # recycle the spot in the array
                        @segment_ends[i] = tile
                    else
                        @segment_ends.splice i, 1
        if neighbor_segment_ends is 2
            @segment_ends.removeFirst tile
    mandatory: (tile) ->
        for pattern in @mandatory_patterns
            go = pattern.call @, tile
            return go if go
    failed: (tile) ->
        for pattern in @failure_patterns
            return true if pattern.call @, tile
        return false
    guess: (tiles=@segment_ends) ->
        fallbacks = [null, null]
        for tile in tiles
            for pattern in @guess_patterns
                options = pattern.call @, tile 
                #console.log "guess tile #{tile} options #{JSON.stringify options}"
                continue unless options
                switch options.length
                    when 2
                        return [tile, options]
                    when 3, 4
                        fallbacks[options.length - 3] or= [tile, options]
        return fallbacks[0] or fallbacks[1]

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
        N = -@width
        E = 1
        S = @width
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
                source.push "if (this.line_grid[tile + #{offset}] === #{BLANK}) return;"
                source.push "if (this.segment_ends.indexOf(tile + #{offset}) !== -1) return;"
            for offset in pattern.segmentend or []
                source.push "if (this.segment_ends.indexOf(tile + #{offset}) === -1) return;"
            if pattern.fail
                source.push "return [];"
            else
                source.push "return #{JSON.stringify pattern.go or pattern.vacant};"
            return new Function 'tile', source.join ' '
        @failure_patterns = (compile pattern for pattern in [
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
            {notvacant:[N, E, S, W], segmentend:[0], fail:true}
            # vacant dead ends
            {vacant:[NW], midsegment:[NWW, NNW, N], fail:true}
            {vacant:[NW], midsegment:[NWW, NNW, W], fail:true}
            {vacant:[NE], midsegment:[NEE, NNE, N], fail:true}
            {vacant:[NE], midsegment:[NEE, NNE, E], fail:true}
            {vacant:[SE], midsegment:[SEE, SSE, S], fail:true}
            {vacant:[SE], midsegment:[SEE, SSE, E], fail:true}
            {vacant:[SW], midsegment:[SWW, SSW, S], fail:true}
            {vacant:[SW], midsegment:[SWW, SSW, W], fail:true}
            # loops
            {me:[N, E], midsegment:[N, E], segmentend:[0], fail:true}
            {me:[N, S], midsegment:[N, S], segmentend:[0], fail:true}
            {me:[N, W], midsegment:[N, W], segmentend:[0], fail:true}
            {me:[E, S], midsegment:[E, S], segmentend:[0], fail:true}
            {me:[E, W], midsegment:[E, W], segmentend:[0], fail:true}
            {me:[S, W], midsegment:[S, W], segmentend:[0], fail:true}
        ])
        @mandatory_patterns = (compile pattern for pattern in [
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
            {vacant:[N], midsegment:[NE, NW]}
            {vacant:[E], midsegment:[NE, SE]}
            {vacant:[S], midsegment:[SE, SW]}
            {vacant:[W], midsegment:[NW, SW]}
            # only line able to turn a nearby corner
            {vacant:[N, NW], midsegment:[NE, NN], notme:[W]}
            {vacant:[N, NE], midsegment:[NW, NN], notme:[E]}
            {vacant:[E, NE], midsegment:[SE, EE], notme:[N]}
            {vacant:[E, SE], midsegment:[NE, EE], notme:[S]}
            {vacant:[S, SE], midsegment:[SW, SS], notme:[E]}
            {vacant:[S, SW], midsegment:[SE, SS], notme:[W]}
            {vacant:[W, SW], midsegment:[NW, WW], notme:[S]}
            {vacant:[W, NW], midsegment:[SW, WW], notme:[N]}
            # only line able to turn a slightly further corner
            {vacant:[N, NN, NNW], midsegment:[NE, NNE, NNN], notme:[NW]}
            {vacant:[N, NN, NNE], midsegment:[NW, NNW, NNN], notme:[NE]}
            {vacant:[E, EE, NEE], midsegment:[SE, SEE, EEE], notme:[NE]}
            {vacant:[E, EE, SEE], midsegment:[NE, NEE, EEE], notme:[SE]}
            {vacant:[S, SS, SSE], midsegment:[SW, SSW, SSS], notme:[SE]}
            {vacant:[S, SS, SSW], midsegment:[SE, SSE, SSS], notme:[SW]}
            {vacant:[W, WW, SWW], midsegment:[NW, NWW, WWW], notme:[SW]}
            {vacant:[W, WW, NWW], midsegment:[SW, SWW, WWW], notme:[NW]}
            # bent
            {vacant:[N], midsegment:[W], me:[S, SE]}
            {vacant:[N], midsegment:[E], me:[S, SW]}
            {vacant:[E], midsegment:[S], me:[W, NW]}
            {vacant:[E], midsegment:[N], me:[W, SW]}
            {vacant:[S], midsegment:[E], me:[N, NW]}
            {vacant:[S], midsegment:[W], me:[N, NE]}
            {vacant:[W], midsegment:[N], me:[E, SE]}
            {vacant:[W], midsegment:[S], me:[E, NE]}
        ])
        @guess_patterns = (compile pattern for pattern in [
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
        ])
        @tiles = new Tiles @
        @stack = []
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
            ansiterm.bg.tan
            ansiterm.bg.dark_blue
            ansiterm.bg.slate
            ansiterm.bg.hot_pink
            ansiterm.bg.black # XXX PLACEHOLDER
        ]
    mandatory: =>
        loop
            console.log "mandatory segment_ends #{JSON.stringify @tiles.segment_ends}" if debug
            mandatory_found = false
            #for tile in @tiles.segment_ends
            # ... except we modify segment_ends, and thus would skip end(s)
            # ... and fail to slightly prioritize recently moved ends
            i = 0
            while i < @tiles.segment_ends.length
                tile = @tiles.segment_ends[i]
                go = @tiles.mandatory tile
                console.log "mandatory tile #{tile} go #{go and JSON.stringify (tile + offset for offset in go)}" if debug
                if go
                    line = @tiles.line_grid[tile]
                    for offset in go
                        new_tile = tile + offset
                        @tiles.set new_tile, line
                        if @tiles.failed new_tile
                            console.log "mandatory tile #{tile} go #{new_tile} failed" if debug
                            return false
                    mandatory_found = true
                    @render() if debug
                else
                    ++i
            break unless mandatory_found
        return true
    guess: =>
        # assert @tiles
        console.log "guess segment_ends #{JSON.stringify @tiles.segment_ends}" if debug
        [tile, options] = @tiles.guess() or []
        console.log "guess guessed #{tile} #{JSON.stringify options}" if debug
        # assert options.length > 1
        return false unless tile?
        for option, i in options
            last_guess = i is options.length - 1
            line = @tiles.line_grid[tile]
            console.log "guess tile #{tile} go #{JSON.stringify ((tile + offset for offset in go) for go in options)}" if debug
            # clone or recycle current state
            hypothesis = if last_guess then @tiles else new Tiles @tiles
            for offset in option
                new_tile = tile + offset
                hypothesis.set new_tile, line
                if hypothesis.failed new_tile
                    console.log "guess tile #{tile} go #{new_tile} failed" if debug
                    hypothesis = null
                    break
            if last_guess
                return false unless hypothesis
            else
                @stack.push hypothesis if hypothesis
        return true
    solve: (autocb) ->
        # assert @tiles
        @start = new Date
        while @tiles
            ++@step
            for strategy in [@mandatory, @guess]
                unless strategy()
                    console.log "popping" if debug
                    @render() if debug
                    @tiles = @stack.pop()
                    break
                if @tiles.segment_ends.length is 0 and @tiles.blanks is 0
                    @solutions.push new Tiles @tiles
                    @render()
            if debug
                await setTimeout defer(), 100
            else unless @step % 100
                await setImmediate defer()
        @elapsed = new Date - @start
    render: (supplemental=[], screen_height=24) =>
        write = (data) -> process.stdout.write data
        unless @display_initialized or scroll
            @display_initialized = true
            write ansiterm.position()
            write ansiterm.eraseDisplay()
        write ansiterm.position() unless debug or scroll
        renderGrid = (tiles) =>
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
        switch true
            when not not @tiles
                renderGrid @tiles
            when @solutions.length > 0
                write ansiterm.eraseDisplay() unless scroll
                for solution, i in @solutions
                    write "\n" if i > 0
                    renderGrid solution
            else
                renderGrid @
        write ansiterm.eraseDisplay()
        elapsed = @elapsed or (new Date - (@start or new Date))
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
        return true unless 1 <= puzzle.solutions.length <= 2
        return true if debug and puzzle.solutions.length isnt 1
        await setTimeout defer(), display_showoff
    break if done

#fs.writeFileSync 'flowfree_timings.json', JSON.stringify timings
