import std.stdio;
import std.getopt;
import std.process : pipeShell, Redirect, wait;
import std.algorithm;
import std.array;
import std.math : abs;
import std.conv : to;
import std.format : format;

immutable jump_instrs = ["jmp", "jmpq", "ja", "je", "jne"];

/// represents one arrow to draw
class Arrow {
    string start;
    string end;
    uint length;
    int column;
    this(string start, string end) {
        this.start = start;
        this.end = end;
        this.length = cast(uint) abs(end.to!long(16) - start.to!long(16));
    }
    @property bool forwards() {
        return start < end;
    }
}

/// represents a line to print
struct cmdline {
    string addr;
    string cmd;
    Arrow[] arrows;
}

string[] handleSection(string[] lines)
{
    if (lines.empty) return lines;
    if (lines.front.canFind("<.gnu.hash>")
            || lines.front.canFind("<.dynstr>")
            || lines.front.canFind("<.gnu.version>")
            || lines.front.canFind("<.gnu.version_r>")
            || lines.front.canFind("<.dynsym>")) {
        return ["omit "~lines.front];
    }
    writeln(lines.front);
    lines.popFront();

    // find all jumps
    cmdline[] my_lines;
    Arrow[] arrows;
    string[][string] jump_targets;
    foreach (line; lines) {
        auto parts = line.splitter().array;
        if (parts.length <= 2) continue;
        auto addr = parts[0][0 .. $-1];
        auto instr = parts[1];
        string cmd = line[9 .. $].strip(' ').strip('\t');
        auto l = cmdline(addr, cmd, []);
        my_lines ~= l;
        if (canFind(jump_instrs, instr)) {
            auto target = parts[2];
            if (target[0] == '*') continue;
            if (target[0] == 'f') continue;
            jump_targets[target] ~= addr;
            arrows ~= new Arrow(addr, target);
        }
    }
    //writeln("arrows: ", arrows.length);
    //foreach (k,v; jump_targets) { writeln("J ",k," ",v); }

    // compute arrow columns
    int max_col;
    foreach (ref line; my_lines) {
        auto addr = line.addr;
        Arrow[] as;
        foreach (a; arrows) {
            if (a.start <= addr && a.end >= addr)
                as ~= a;
            else if (a.start >= addr && a.end <= addr)
                as ~= a;
        }
        as.sort!"a.length < b.length"();
        int col = 0;
        foreach(ref a; as) {
            if (col > a.column)
                a.column = col;
            else
                col = a.column;
            col += 1;
        }
        max_col = max(col, max_col);
        line.arrows = as;
        //if (!as.empty) writeln(addr, " ", line.arrows);
    }
    //writeln("maximum column: ", max_col);

    // print lines
    string[] ret;
    foreach (line; my_lines) {
        auto addr = line.addr;

        int target_col = int.min;
        int source_col = int.min;
        foreach (a; line.arrows) {
            if (a.end == addr) target_col = max(target_col, a.column);
            if (a.start == addr) source_col = max(source_col, a.column);
        }

        // compose arrow output
        wchar[] output;
        output.length = max_col+1;
        output[] = ' ';
        assert (output.length < int.max);
        target_col = cast(int)output.length - target_col - 1;
        source_col = cast(int)output.length - source_col - 1;
        foreach (a; line.arrows) {
            const c = output.length - a.column - 1;
            if (a.start == addr) { // starting here
                if (a.forwards)
                    output[c] = '╭';
                else
                    output[c] = '╰';
                foreach (i; c + 1 .. output.length)
                    if (output[i] == ' ')
                        output[i] = '─';
                    else
                        output[i] = '┼';
            } else if (a.end == addr) { // ending here
                if (a.forwards)
                    output[c] = '┕';
                else
                    output[c] = '┍';
                foreach (i; c + 1 .. output.length)
                    if (output[i] == ' ')
                        output[i] = '━';
                    else if (output[i] == '│' || output[i] == '┆')
                        output[i] = '┿';
                    else if (output[i] == '┕')
                        output[i] = '┷';
                    else if (output[i] == '┍')
                        output[i] = '┯';
            } else { // passing through
                if (output[c] == '─')
                    output[c] = '┼';
                else if (output[c] == '━')
                    output[c] = '┿';
                else
                    if (a.forwards)
                        output[c] = '│';
                    else // backarrow
                        output[c] = '┆';
            }
        }

        // actually print
        ret ~= format(" %s:%s %s", addr, output, line.cmd);
    }
    return ret;
}

unittest {
    assert (handleSection([]) == []);
}

void main(string[] args)
{
    auto helpInformation = getopt(args);

    if (helpInformation.helpWanted || args.length <= 1) {
        defaultGetoptPrinter("Usage:", helpInformation.options);
        return;
    }

    string path = args[1];
    auto pipes = pipeShell("objdump --no-show-raw-insn -D "~path, Redirect.stdout);
    scope(exit) wait(pipes.pid);

    string[] lines;
    foreach (line; pipes.stdout.byLine) {
        if (line == "") {
            if (lines.length > 2) {
                writeln();
                foreach(l; handleSection(lines))
                    writeln(l);
            }
            lines = [];
            continue;
        }
        lines ~= line.idup;
    }
}
