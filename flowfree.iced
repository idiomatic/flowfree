#!/usr/bin/env iced
fs = require 'fs'
readline = require 'readline'
stream = require 'stream'
ansiterm = require './ansiterm'

Array::remove = (v) ->
    beyond = 0
    while (i = @indexOf v, beyond) >= 0
        @splice i, 1
        beyond = i
    return @

Array::pushIfAbsent = (values...) ->
    for v in values
        unless v in @
            @push v

String::repeat = (n) ->
    return new Array(++n).join @

log10 = (v) ->
    return Math.log(v) / Math.log(10)

WALL = -1
BLANK = 0
# RED = 1
# ...

COLUMN_WIDTH = 4

class Tiles
    # XXX bridges: makes @neighbor_offsets fail, warranting precalculation
    constructor: (parent, @segment_ends=[], @grid=undefined, @blank=0) ->
        {@height, @width, @endpoints, @bridges, @neighbor_offsets, @corner_offsets, @perimiter_offsets, @guess_depth} = parent
        N = -@width
        S = @width
        W = -1
        E = 1
        @neighbor_offsets or= [N, E, S, W]
        @perimiter_offsets or= [N+W, N, N+E, E, S+E, S, S+W, W]
        @corner_offsets or= [
            # nonend nonblank notme -> vacants/assigned
            [[N+E, N+N], [N, N+W]]
            [[N+W, N+N], [N, N+E]]
            [[S+E, E+E], [E, E+N]]
            [[N+E, E+E], [E, E+S]]
            [[S+W, S+S], [S, S+E]]
            [[S+E, S+S], [S, S+W]]
            [[N+W, W+W], [W, W+S]]
            [[S+W, W+W], [W, W+N]]
            [[N+E, N+N+E, N+N+N], [N, N+N, N+N+W]]
            [[N+W, N+N+W, N+N+N], [N, N+N, N+N+E]]
            [[S+E, S+E+E, E+E+E], [E, E+E, E+E+N]]
            [[N+E, N+E+E, E+E+E], [E, E+E, E+E+S]]
            [[S+W, S+S+W, S+S+S], [S, S+S, S+S+E]]
            [[S+E, S+S+E, S+S+S], [S, S+S, S+S+W]]
            [[N+W, N+W+W, W+W+W], [W, W+W, W+W+S]]
            [[S+W, S+W+W, W+W+W], [W, W+W, W+W+N]]
        ]
        # XXX more generalized patterns: likeme, notlikeme, endpoint, notendpoint, vacant, notvacant, becomesme
        @initGrid() unless @grid?
    clone: ->
        return new Tiles @, @segment_ends.slice(0), @grid.slice(0), @blank
    initGrid: ->
        @grid = new Array @width * @height
        for _, tile in @grid
            # removes endpoints
            #@set tile, BLANK
            @grid[tile] = BLANK
            ++@blank
        for tile in [0...@width]
            @set tile, WALL
            @set tile + @width * (@height - 1), WALL
        for row in [1...@height - 1]
            @set row * @width, WALL
            @set (row + 1) * @width - 1, WALL
        for [start, end], line in @endpoints
            if start?
                # adds to segment_ends
                @set start, line
                @set end, line
    isFull: ->
        return @blank is 0
    isEndpoint: (tile) ->
        line = @grid[tile]
        return line? and line isnt WALL and tile in @endpoints[line]
    isSegmentEnd: (tile) ->
        return tile in @segment_ends
    isDeadEnd: (tile) ->
        return false if @grid[tile] is BLANK
        line = @grid[tile]
        blank = @neighborsLength tile, BLANK
        like = @neighborsLength tile, line
        return (blank is 0) and (like < 2)
    neighborsLength: (tile, line) ->
        n = 0
        for offset in @neighbor_offsets
            ++n if @grid[tile + offset] is line
        return n
    neighbors: (tile, line) ->
        #return (tile + relative for relative in @neighbor_offsets when @grid[tile + relative] is line)
        # new Array is 4x faster
        a = new Array @neighborsLength tile, line
        i = 0
        for offset in @neighbor_offsets
            if @grid[tile + offset] is line
                a[i++] = tile + offset
        return a
    neighborSegmentEndLength: (tile) ->
        n = 0
        for offset in @neighbor_offsets
            ++n if @isSegmentEnd tile + offset
        return n
    rigidNeighborCorners: (tile) ->
        a = []
        line = @grid[tile]
        for corner in @corner_offsets
            failed = false
            for offset in corner[1]
                failed = @grid[tile + offset] isnt BLANK
                break if failed
            continue if failed
            for offset in corner[0]
                # has to be occupied by a different non-continuable line
                failed = @grid[tile + offset] is BLANK
                failed or= @grid[tile + offset] is line
                break if failed
            continue if failed
            for offset in corner[0]
                failed or= @isEndpoint tile + offset
                failed or= @isSegmentEnd tile + offset
                break if failed
            continue if failed
            for offset in corner[1]
                a.push tile + offset
            break if @isEndpoint tile
        return a
        for offset in @neighbor_offsets
            neighbor = tile + offset
            continue if @grid[neighbor] isnt BLANK
            continue if @neighborsLength(neighbor, BLANK) isnt 1
            continue if @neighborSegmentEndLength(neighbor) isnt 1
            a.push neighbor
        return a
    perimiterLength: (tile, line) ->
        n = 0
        for offset in @perimiter_offsets
            ++n if @grid[tile + offset] is line
        return n
    perimiterSegmentMaxLength: (tile, line) ->
        max = 0
        n = 0
        i = 0
        for offset in @perimiter_offsets
            if @grid[tile + offset] is line
                ++n
                max = n if n > max
            else
                n = 0
        if n
            # second attempt if segment crosses perimiter_offsets bounds
            for offset in @perimiter_offsets
                if @grid[tile + offset] is line
                    ++n
                    max = n if n > max
                else
                    break
        return max
    set: (tile, line) ->
        return if @grid[tile] is line
        if @grid[tile] is BLANK
            --@blank
        if line is BLANK
            ++@blank
        @grid[tile] = line
        switch line
            when WALL
                true
            when BLANK
                ++@blank
                @segment_ends.remove tile
        adjustSegment = (tile) =>
            n = @neighborsLength(tile, line)
            ++n if @isEndpoint tile
            if n > 1
                @segment_ends.remove tile
            else
                @segment_ends.pushIfAbsent tile
        for neighbor in @neighbors tile, line
            adjustSegment neighbor
        adjustSegment tile
    clear: (tile) ->
        @set tile, BLANK
    hasDeadEnds: ->
        for tile in @segment_ends
            return true if tile? and @isDeadEnd tile
        for line, tile in @grid
            continue if line isnt BLANK
            continue if @neighborsLength(tile, BLANK) > 1
            continue if @neighborSegmentEndLength(tile) > 0
            return true
        return false

class Puzzle
    constructor: (@size, @endpoints) ->
        @height = @width = @size + 2
        @guess_depth = 0
        @tiles = new Tiles @
        @tiles_stack = []
        @steps = 0
        @message = undefined
        @solutions = []
        @strategies = [@mandatory, @guess]
        @id = "#{@size}x#{@size} #{@endpoints[2..]}"
        @start = undefined
        @elapsed = undefined
        @best_time = undefined
        @guess_branches = [0, 0, 0, 0, 0]
    solve: (autocb) ->
        @start = new Date
        loop
            ++@steps
            for strategy in @strategies
                unless strategy()
                    break
                if @tiles.hasDeadEnds()
                    break
                if @tiles.isFull() and @tiles.segment_ends.length is 0
                    @solutions.push @tiles.clone()
                    break
            @tiles = @tiles_stack.pop()
            break unless @tiles
            # lastly...
            unless @steps % 1000
                await setImmediate defer()
            #await setTimeout defer(), 1000 / Math.sqrt @steps
        @elapsed = new Date - @start
    mandatory: =>
        found = true
        while found
            found = false
            for tile in @tiles.segment_ends
                line = @tiles.grid[tile]
                if @tiles.neighborsLength(tile, BLANK) is 1
                    # this line has no choice
                    [vacant] = @tiles.neighbors tile, BLANK
                    # avoid over congestion
                    if @tiles.perimiterSegmentMaxLength(vacant, line) >= 3
                        return false
                    @tiles.set vacant, line
                    found = true
                else
                    for neighbor in @tiles.rigidNeighborCorners tile
                        # no other line is going into this corner
                        if @tiles.perimiterSegmentMaxLength(neighbor, line) >= 3
                            return false
                        @tiles.set neighbor, line
                        found = true
        return true
    guess: =>
        [unfinished] = @tiles.segment_ends
        if unfinished
            line = @tiles.grid[unfinished]
            ++@tiles.guess_depth
            branches = 0
            for neighbor in @tiles.neighbors unfinished, BLANK
                continue if @tiles.perimiterSegmentMaxLength(neighbor, line) >= 3
                hypothesis = @tiles.clone()
                hypothesis.set neighbor, line
                @tiles_stack.push hypothesis
                ++branches
            ++@guess_branches[branches]
        # this tile is superceded by those just pushed
        return false

class ANSITermRender extends stream.Transform
    constructor: (@refresh=50) ->
        super objectMode:true
        @puzzles = 0
        @log = []
        @screen_height = 24
    _flush: ->
        if @interval
            clearInterval @interval
            @interval = null
        @push null
    _transform: (data, encoding, autocb) ->
        #return unless data
        if typeof(data) is 'object'
            ++@puzzles
            @puzzle = data
        else
            @log.push [@puzzle.elapsed, @status()]
            @log.sort (a, b) -> b[0] - a[0]
        unless @puzzle.tiles or @puzzle.solutions[0]
            return
        @tile_colors = [
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
            ansiterm.bg.black # PLACEHOLDER
        ]
        @row = (1 + Math.floor tile / @puzzle.width for tile in [0..@puzzle.width * @puzzle.height])
        @column = (1 + tile % @puzzle.width * COLUMN_WIDTH for tile in [0..@puzzle.width * @puzzle.height])
        @initDisplay()
        @border()
        @render()
        @interval or= setInterval @render, @refresh
        return null
    status: =>
        tiles = @puzzle.tiles or @puzzle.solutions[0]
        elapsed = @puzzle.elapsed or (new Date - @puzzle.start) or 0
        if @puzzle.best_time > 0
            progress = "#{Math.round elapsed / @puzzle.best_time * 100}%"
        else
            progress = ""
        #return "puzzle #{@puzzles} step #{@puzzle.steps} stack #{@puzzle.tiles_stack.length} guess_depth #{tiles.guess_depth} solutions #{@puzzle.solutions.length} elapsed #{elapsed}ms #{progress}\n"
        return "##{@puzzles} step #{@puzzle.steps} elapsed #{elapsed}ms #{progress} #{@puzzle.guess_branches}\n"
    initDisplay: ->
        @push ansiterm.position()
        @push ansiterm.eraseDisplay()
    render: =>
        @raster()
        @push ansiterm.color()
        if @puzzle.steps?
            @push ansiterm.position @puzzle.height + 1
            @push ansiterm.eraseLine()
            @push @status()
            #@push JSON.stringify @puzzle.tiles
        if @puzzle.message
            @push ansiterm.position @puzzle.height + 2
            @push ansiterm.eraseDisplay()
            @push "#{@puzzle.message}\n"
        else
            @push ansiterm.position @puzzle.height + 2
            @push ansiterm.eraseDisplay()
            @push (status for [_, status] in @log)[..@screen_height - @puzzle.height - 3].join ''
        @push ansiterm.position 24
    border: ->
        @push ansiterm.color ansiterm.bg.black
        tiles = @puzzle.tiles or @puzzle.solutions[0]
        for line, tile in tiles.grid
            if line is WALL
                @push ansiterm.position @row[tile], @column[tile]
                @push " ".repeat COLUMN_WIDTH
    raster: ->
        current_row = null
        next_column = null
        left_pad = " ".repeat COLUMN_WIDTH
        draw = (tile, line, glyph) =>
            right_pad = " ".repeat Math.floor (COLUMN_WIDTH - glyph.length) / 2
            glyph = (left_pad + glyph + right_pad)[-COLUMN_WIDTH..]
            if @row[tile] isnt current_row or @column[tile] isnt next_column
                @push ansiterm.position @row[tile], @column[tile]
            @push ansiterm.color @tile_colors[line + 1]
            @push ansiterm.color ansiterm.fg.white
            @push glyph
            next_column = @column[tile] + COLUMN_WIDTH
            current_row = @row[tile]
        tiles = @puzzle.tiles or @puzzle.solutions[0]
        numeric_width = Math.ceil log10 @puzzle.height * @puzzle.width
        for line, tile in tiles.grid
            switch true
                when tiles.isEndpoint tile
                    draw tile, line, "()"
                when tiles.isDeadEnd tile
                    draw tile, line, "XX"
                when tiles.isSegmentEnd tile
                    draw tile, line, "--"
                else
                    if numeric_width < COLUMN_WIDTH
                        glyph = tile.toString()
                        glyph = "#{' '.repeat numeric_width - glyph.length}#{glyph} "
                    else
                        glyph = ""
                    draw tile, line, glyph

# XXX parser driver
parsePuzzle = (line) ->
    [summary, traces...] = line.split ';'
    [size, _, n, trace_count] = summary.split ','
    size = parseInt size
    addWalls = (packed_tile) ->
        width = size + 2
        packed_tile = parseInt packed_tile
        return 1 + width + packed_tile + 2 * Math.floor(packed_tile / (width - 2))

    traces = ((addWalls(packed_tile) for packed_tile in trace.split ',') for trace in traces)
    endpoints = ([tiles[0], tiles[tiles.length-1]] for tiles in traces)
    endpoints.unshift [undefined, undefined]
    return new Puzzle size, endpoints

render = new ANSITermRender
render.pipe process.stdout

try
    timings = JSON.parse fs.readFileSync 'flowfree_timings.json'
catch
    timings = {}

await
    puzzle_queue = []
    rl = readline.createInterface input:process.stdin, terminal:false
    rl.on 'line', (line) ->
        if line
            puzzle = parsePuzzle line
            puzzle.best_time = timings[puzzle.id]
            puzzle_queue.push puzzle
    rl.on 'close', ->
        puzzle_queue.push null
    do (autocb=defer()) ->
        loop
            p = puzzle_queue.shift()
            switch p
                when null
                    return
                when undefined
                    rl.resume()
                    await setTimeout defer(), 10
                else
                    rl.pause()
                    render.write p
                    await p.solve defer()
                    timings[p.id] = Math.min p.elapsed, (timings[p.id] ? p.elapsed)
                    render.write true
                    if p.solutions.length is 0
                        throw new Error 'no solution'
                    #if p.solutions.length > 1
                    #    throw new Error 'too many solutions'
                    #process.stdout.write '\x07'
                    await setTimeout defer(), 100

render.end()

fs.writeFileSync 'flowfree_timings.json', JSON.stringify timings
