import std.stdio;
import std.getopt;
import std.process : pipeShell, Redirect, wait;
import std.algorithm : splitter, canFind;
import std.array;

immutable jump_instrs = ["jmp", "jmpq", "ja", "je", "jne"];

void handleSection(string[] lines)
{
    writeln();
    writeln(lines.front);
    lines.popFront();

    // find all jumps
    string[][string] jump_targets;
    foreach (line; lines) {
        auto parts = line.splitter().array;
        if (parts.length <= 2) continue;
        auto addr = parts[0][0 .. $-1];
        auto instr = parts[1];
        if (canFind(jump_instrs, instr)) {
            auto target = parts[2];
            jump_targets[target] ~= addr;
        }
    }
    //foreach (k,v; jump_targets) { writeln("J ",k," ",v); }

    // print lines
    foreach (line; lines) {
        auto parts = line.splitter().array;
        if (parts.length <= 2) continue;
        auto addr = parts[0][0 .. $-1];
        write(" ", addr, ": ");
        auto instr = parts[1];
        if (canFind(jump_instrs, instr)) {
            auto target = parts[2];
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
        foreach (p; parts[1 .. $]) {
            write(p, " ");
        }
        writeln();
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
