import std.stdio;
import std.getopt;
import std.process : pipeShell, Redirect, wait;
import std.algorithm;
import std.array;
import std.math : abs;
import std.conv : to;

immutable jump_instrs = ["jmp", "jmpq", "ja", "je", "jne"];

/// represents one arrow to draw
class arrow {
    string start;
    string end;
    uint length;
    int column;
    this(string start, string end) {
        this.start = start;
        this.end = end;
        this.length = cast(uint) abs(end.to!long(16) - start.to!long(16));
    }
}

/// represents a line to print
struct cmdline {
    string addr;
    string cmd;
    arrow[] arrows;
}

void handleSection(string[] lines)
{
    writeln();
    if (lines.front.canFind("<.gnu.hash>")
            || lines.front.canFind("<.dynstr>")
            || lines.front.canFind("<.gnu.version>")
            || lines.front.canFind("<.gnu.version_r>")
            || lines.front.canFind("<.dynsym>")) {
        writeln("omit ", lines.front);
        return;
    }
    writeln(lines.front);
    lines.popFront();

    // find all jumps
    cmdline[] my_lines;
    arrow[] arrows;
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
            arrows ~= new arrow(addr, target);
        }
    }
    //writeln("arrows: ", arrows.length);
    //foreach (k,v; jump_targets) { writeln("J ",k," ",v); }

    // compute arrow columns
    int max_col;
    foreach (ref line; my_lines) {
        auto addr = line.addr;
        arrow[] as;
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
    writeln("maximum column: ", max_col);

    // print lines
    foreach (line; my_lines) {
        auto addr = line.addr;

        int target_col = max_col + 1;
        int source_col = max_col + 1;
        foreach (a; line.arrows) {
            if (a.end == addr) target_col = min(target_col, a.column);
            if (a.start == addr) source_col = min(target_col, a.column);
        }

        // compose arrow output
        wchar[] output;
        output.length = max_col+1;
        output[] = ' ';
        foreach (a; line.arrows) {
            const c = a.column;
            if (c == target_col) {
                if (a.end < a.start)
                    output[c] = '┍';
                else
                    output[c] = '┕';
                foreach (i; c + 1 .. output.length)
                    output[i] = '━';
            } else if (c == source_col) {
                if (a.end < a.start)
                    output[c] = '╰';
                else
                    output[c] = '╭';
                foreach (i; c + 1 .. output.length)
                    output[i] = '─';
            } else {
                if (output[c] == '─')
                    output[c] = '┼';
                else if (output[c] == '━')
                    if (a.end == addr) // another arrow also ends here
                        if (a.start < a.end)
                            output[c] = '┷';
                        else
                            output[c] = '┯';
                    else
                        output[c] = '┿';
                else
                    if (a.start < a.end)
                        output[c] = '│';
                    else // backarrow
                        output[c] = '┆';
            }
        }

        // actually print
        write(" ", addr, ": ");
        write(output);
        write(" ", line.cmd);
        writeln();
        continue;

/**
        if (line.cmd.length > 3) {
            auto target = "";
            if (target > addr)
                write("┌─");
            else
                write("└─");
        } else if (addr in jump_targets) {
            bool above = false, below = false;
            foreach (src; jump_targets[addr]) {
                if (src < addr)
                    above = true;
                else
                    below = true;
            }
            if (above)
                if (below)
                    write("┝━");
                else
                    write("┕━");
            else {
                assert (below);
                write("┍━");
            }
        } else {
            write("  ");
        }
        writeln();
        **/
    }
}

void main(string[] args)
{
    string path = args[1];
    auto pipes = pipeShell("objdump --no-show-raw-insn -D "~path, Redirect.stdout);
    scope(exit) wait(pipes.pid);

    string[] lines;
    foreach (line; pipes.stdout.byLine) {
        if (line == "") {
            if (lines.length > 2)
                handleSection(lines);
            lines = [];
            continue;
        }
        lines ~= line.idup;
    }
}
