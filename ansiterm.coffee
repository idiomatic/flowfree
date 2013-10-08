module.exports =
    color: (color=0) -> "\x1b[#{color}m"
    #color: -> ""
    position: (row=1, column=1) -> "\x1b[#{row};#{column}H"
    doublewide: -> "\x1b#6"
    up: (rows='') -> "\x1b[#{rows}A"
    down: (rows='') -> "\x1b[#{rows}B"
    right: (columns='') -> "\x1b[#{columns}C"
    left: (columns='') -> "\x1b[#{columns}D"
    eraseLine: (part=0) -> "\x1b[#{part}K" # 0:right, 1:left, 2:all
    eraseDisplay: (part=0) -> "\x1b[#{part}J" # 0:below, 1:above, 2: all
    charset: (set='1') -> "\x1b(#{set}"
    fg:
        reset: 0
        black: 30
        red: 31
        white: 37
    bg:
        reset: 0
        black: 40
        red: '48;5;9'
        green: 42
        yellow: 43
        blue: 44
        magenta: '48;5;13'
        cyan: 46
        white: '48;5;15'
        yellow: '48;5;11'
        orange: '48;5;214'
        cyan: 46
        dark_red: 41
        pink: '48;5;218'
        dark_magenta: '48;5;5'
        grey: 47
        light_green: '48;5;10'
