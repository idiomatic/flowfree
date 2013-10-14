#!/usr/bin/env iced
readline = require 'readline'
ansiterm = require './ansiterm'

debug = false
scroll = debug
display_frequency = 20
display_showoff = 50

# TODO list of patterns affected by this tile?
# TODO visualization of guesses

String::repeat = (n) ->
    new Array(n + 1).join @

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
        {@width, @height, @blanks} = parent
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
        switch neighbor_segment_ends
            when 0
                @segment_ends.push tile
            when 2
                @segment_ends.removeFirst tile

puzzle_count = 0

class Puzzle
    constructor: (@size, @endpoints) ->
        #[red1, red2, green1, green2, ...]
        @n = ++puzzle_count
        @width = @height = @size + 2
        @segment_ends = []
        @blanks = 0
        @line_grid = new Array @width * @height
        # initialize WALLs and BLANKs
        for tile in [0...@height * @width]
            @line_grid[tile] = BLANK
        for col in [0...@width]
            @line_grid[col] = @line_grid[col + (@height - 1) * @width] = WALL
        for row in [0...@height]
            @line_grid[row * @width] = @line_grid[(row + 1) * @width - 1] = WALL
        # initialize endpoints unless they're already neighboring
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
        compile = (patterns) ->
            conditions =
                me: (offset) -> "tiles.line_grid[tile] === tiles.line_grid[tile + #{offset}]"
                vacant: (offset) -> "tiles.line_grid[tile + #{offset}] === #{BLANK}"
                midsegment: (offset) -> "(tiles.line_grid[tile + #{offset}] !== #{BLANK}) && (tiles.segment_ends.indexOf(tile + #{offset}) === -1)"
            # recursive decision tree
            # {a1_v1: {attr:a1, value:v1, positive:{...}, negative:{...}}, ...}
            root = {}
            for pattern in patterns
                # build index of each attr/value
                # {a1_v1: [polarity1, attr1, value1], a2_v21: ..., a2_v22: ...}
                indexed_pattern = {}
                for attr, values of pattern
                    continue if attr is 'go' or attr is 'fail'
                    polarity = 'positive'
                    if attr[..2] is 'not'
                        attr = attr[3..]
                        polarity = 'negative'
                    for value in values
                        attr_value = "#{attr}=#{value}"
                        indexed_pattern[attr_value] = [polarity, attr, value]
                # traverse existing branches in common between tree and pattern
                r = root
                loop
                    done = true
                    for attr_value, [polarity] of indexed_pattern
                        if r[attr_value]
                            # attr_value is in both this fork and the pattern
                            delete indexed_pattern[attr_value]
                            r = r[attr_value][polarity]
                            done = false
                            break
                    break if done
                # grow new branches for remaining pattern conditions
                loop
                    done = true
                    for attr_value, [polarity, attr, value] of indexed_pattern
                        delete indexed_pattern[attr_value]
                        r[attr_value] =
                            condition: conditions[attr] value
                            positive: {comment: "#{value} is #{attr}"}
                            negative: {comment: "#{value} isnt #{attr}"}
                        r = r[attr_value][polarity]
                        done = false
                        break
                    break if done
                r.retval = JSON.stringify pattern.fail or pattern.go or pattern.vacant
                r.comment = JSON.stringify pattern if debug
            codegen = (root, depth=1) ->
                return unless root
                pad = "  ".repeat depth
                out = []
                out.push "#{pad}/* #{root.comment} */\n" if root.comment
                if root.retval
                    out.push "#{pad}return #{root.retval};\n"
                else
                    for _, {condition, positive, negative} of root
                        continue unless condition
                        out.push "#{pad}if (#{condition}) {\n"
                        out.push codegen positive, depth + 1
                        out.push "#{pad}} else {\n"
                        out.push codegen negative, depth + 1
                        out.push "#{pad}}\n"
                return out.join ''
            return new Function 'tiles', 'tile', codegen root
        @failure_decision_tree = compile [
            # no exit
            {notvacant:[N, E, S, W], notmidsegment:[0], fail:true}
            # unacceptable clumping
            {me:[N, NE, E], fail:true}
            {me:[NE, E, SE], fail:true}
            {me:[E, SE, S], fail:true}
            {me:[SE, S, SW], fail:true}
            {me:[S, SW, W], fail:true}
            {me:[SW, W, NW], fail:true}
            {me:[W, NW, N], fail:true}
            {me:[NW, N, NE], fail:true}
            # loops
            {me:[N, E], midsegment:[N, E], notmidsegment:[0], fail:true}
            {me:[N, S], midsegment:[N, S], notmidsegment:[0], fail:true}
            {me:[N, W], midsegment:[N, W], notmidsegment:[0], fail:true}
            {me:[E, S], midsegment:[E, S], notmidsegment:[0], fail:true}
            {me:[E, W], midsegment:[E, W], notmidsegment:[0], fail:true}
            {me:[S, W], midsegment:[S, W], notmidsegment:[0], fail:true}
            # vacant dead ends
            {vacant:[NW], midsegment:[NWW, NNW, N], fail:true}
            {vacant:[NW], midsegment:[NWW, NNW, W], fail:true}
            {vacant:[NE], midsegment:[NEE, NNE, N], fail:true}
            {vacant:[NE], midsegment:[NEE, NNE, E], fail:true}
            {vacant:[SE], midsegment:[SEE, SSE, S], fail:true}
            {vacant:[SE], midsegment:[SEE, SSE, E], fail:true}
            {vacant:[SW], midsegment:[SWW, SSW, S], fail:true}
            {vacant:[SW], midsegment:[SWW, SSW, W], fail:true}
            # corner dead ends
            {me:[N], vacant:[E], midsegment:[EE, SE], fail:true}
            {me:[N], vacant:[W], midsegment:[WW, SW], fail:true}
            {me:[E], vacant:[N], midsegment:[NN, NW], fail:true}
            {me:[E], vacant:[S], midsegment:[SS, SW], fail:true}
            {me:[S], vacant:[E], midsegment:[EE, NE], fail:true}
            {me:[S], vacant:[W], midsegment:[WW, NW], fail:true}
            {me:[W], vacant:[N], midsegment:[NN, NE], fail:true}
            {me:[W], vacant:[S], midsegment:[SS, SE], fail:true}
        ]
        if debug
            console.log '/* failure_decision_tree */'
            console.log @failure_decision_tree.toString()
        @mandatory_decision_tree = compile [
            # involuntary exit
            {vacant:[N], notvacant:[E, S, W]}
            {vacant:[E], notvacant:[S, W, N]}
            {vacant:[S], notvacant:[N, E, W]}
            {vacant:[W], notvacant:[N, E, S]}
            # only line able to turn a nearby corner
            {vacant:[N, NW], midsegment:[NE, NN]}
            {vacant:[N, NE], midsegment:[NW, NN]}
            {vacant:[E, NE], midsegment:[SE, EE]}
            {vacant:[E, SE], midsegment:[NE, EE]}
            {vacant:[S, SE], midsegment:[SW, SS]}
            {vacant:[S, SW], midsegment:[SE, SS]}
            {vacant:[W, SW], midsegment:[NW, WW]}
            {vacant:[W, NW], midsegment:[SW, WW]}
            # only line able to turn a slightly further corner
            {vacant:[N, NN, NNW], midsegment:[NE, NNE, NNN]}
            {vacant:[N, NN, NNE], midsegment:[NW, NNW, NNN]}
            {vacant:[E, EE, NEE], midsegment:[SE, SEE, EEE]}
            {vacant:[E, EE, SEE], midsegment:[NE, NEE, EEE]}
            {vacant:[S, SS, SSE], midsegment:[SW, SSW, SSS]}
            {vacant:[S, SS, SSW], midsegment:[SE, SSE, SSS]}
            {vacant:[W, WW, SWW], midsegment:[NW, NWW, WWW]}
            {vacant:[W, WW, NWW], midsegment:[SW, SWW, WWW]}
            # bent
            {vacant:[N], midsegment:[W], me:[S, SE]}
            {vacant:[N], midsegment:[E], me:[S, SW]}
            {vacant:[E], midsegment:[S], me:[W, NW]}
            {vacant:[E], midsegment:[N], me:[W, SW]}
            {vacant:[S], midsegment:[E], me:[N, NW]}
            {vacant:[S], midsegment:[W], me:[N, NE]}
            {vacant:[W], midsegment:[N], me:[E, SE]}
            {vacant:[W], midsegment:[S], me:[E, NE]}
            # only line capable of feeding this part of a dead-end
            {vacant:[N], midsegment:[NE, NW]}
            {vacant:[E], midsegment:[NE, SE]}
            {vacant:[S], midsegment:[SE, SW]}
            {vacant:[W], midsegment:[NW, SW]}
        ]
        if debug
            console.log '/* mandatory_decision_tree */'
            console.log @mandatory_decision_tree.toString()
        @guess_decision_tree = compile [
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
        if debug
            console.log '/* guess_decision_tree */'
            console.log @guess_decision_tree.toString()
        @tiles = new Tiles @
        @stack = []
        @step = 0
        @guesses = 0
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
        ]
    setAndCheck: (tiles, tile, line) ->
        tiles.set tile, line
        failed = @failure_decision_tree tiles, tile
        console.log "tile #{tile} failed" if debug and failed
        return not failed
    mandatory: =>
        success = true
        loop
            console.log "mandatory segment_ends #{JSON.stringify @tiles.segment_ends}" if debug
            progress = false
            #for tile in @tiles.segment_ends
            # ... except we modify segment_ends, and thus would skip end(s)
            # ... and fail to slightly prioritize recently moved ends
            i = 0
            while success and i < @tiles.segment_ends.length
                tile = @tiles.segment_ends[i]
                go = @mandatory_decision_tree @tiles, tile
                console.log "mandatory tile #{tile} go #{go and JSON.stringify (tile + offset for offset in go)}" if debug
                if go
                    line = @tiles.line_grid[tile]
                    for offset in go
                        new_tile = tile + offset
                        success = @setAndCheck @tiles, new_tile, line
                        console.log "mandatory tile #{tile} go #{new_tile} failed" if debug and not success
                        break unless success
                    progress = success
                else
                    ++i
            break unless progress
        return success
    guess: =>
        success = true
        fallbacks = [null, null]
        match = undefined
        for tile in @tiles.segment_ends
            options = @guess_decision_tree @tiles, tile
            continue unless options
            m = [tile, options]
            switch options.length
                when 2
                    # we really like this guess; use it now
                    match = m
                when 3, 4
                    fallbacks[options.length - 3] or= m
        console.log "guess match #{JSON.stringify match}" if debug
        match or= fallbacks[0] or fallbacks[1]
        if match
            [tile, options] = match
            # assert options.length > 1
            console.log "guess tile #{tile} go #{JSON.stringify ((tile + offset for offset in go) for go in options)}" if debug
            for option, i in options
                last_guess = i is options.length - 1
                line = @tiles.line_grid[tile]
                # clone or recycle current state
                hypothesis = if last_guess then @tiles else new Tiles @tiles
                for offset in option
                    new_tile = tile + offset
                    success = @setAndCheck hypothesis, new_tile, line
                    console.log "guess tile #{tile} go #{new_tile} failed" if debug and not success
                    break unless success
                if success
                    ++@guesses
                    unless last_guess
                        @stack.push hypothesis
        else
            success = false
        return success
    solve: (autocb) ->
        # assert @tiles
        @start = new Date
        while @tiles
            for strategy in [@mandatory, @guess]
                @render() if debug
                unless strategy()
                    @tiles = @stack.pop()
                    break
                if @tiles.segment_ends.length is 0 and @tiles.blanks is 0
                    @solutions.push new Tiles @tiles
                    @render()
            if debug
                await setTimeout defer(), 100
            else unless ++@step % 100
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
                    write ansiterm.color ansiterm.fg.white
                    write if debug then " () " else "()"
                else if tile in tiles.segment_ends
                    write ansiterm.color ansiterm.fg.grey44
                    write if debug then " -- " else "--"
                else
                    if debug
                        write ansiterm.color ansiterm.fg.grey
                        write "    #{tile} "[-4..]
                    else
                        write "  "
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
        write "puzzle #{@n} guesses #{@guesses} stack #{@stack.length} solutions #{@solutions.length} elapsed #{elapsed}ms #{progress}\n"

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

# readlines
await
    lines = []
    rl = readline.createInterface input:process.stdin, terminal:false
    rl.on 'line', (line) ->
        lines.push line
    rl.on 'close', defer()

for line in lines
    await do (autocb=defer(done)) ->
        puzzle = parseSolution line
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
