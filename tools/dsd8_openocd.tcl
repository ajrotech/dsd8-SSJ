# Source after bringing up the board's JTAG transport and declaring dsd8.debug.
proc dsd8_scan {tap low} {
    return [drscan $tap 32 $low 32 0]
}

proc dsd8 {command {arg 0} {tap dsd8.debug}} {
    switch -- $command {
        pause   { set opcode 1 }
        run     { set opcode 2 }
        step    { set opcode 3 }
        break   { set opcode 4 }
        status  { set opcode 5 }
        inspect { set opcode 6 }
        trace   { set opcode 7 }
        release { set opcode 8 }
        clear   { set opcode 9 }
        default { error "unknown DSD-8 command: $command" }
    }
    if {$arg < 0 || $arg > 511} {
        error "DSD-8 argument must fit in 9 bits"
    }

    irscan $tap 0x2
    dsd8_scan $tap [expr {($arg << 4) | $opcode}]
    for {set attempt 0} {$attempt < 20} {incr attempt} {
        set fields [dsd8_scan $tap 0]
        if {[scan [lindex $fields 1] %x high] != 1 ||
            [scan [lindex $fields 0] %x low] != 1} {
            error "invalid DSD-8 scan response: $fields"
        }
        if {($high & 0x80000000) != 0} {
            if {($high & 0x40000000) != 0} {
                error "DSD-8 rejected $command (check attach/pause state and argument)"
            }
            return [format "0x%08x%08x" [expr {$high & 0x3fffffff}] [expr {$low & 0xffffffff}]]
        }
    }
    error "DSD-8 timed out waiting for $command"
}
