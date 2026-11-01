# SPDX-License-Identifier: GPL-3.0-or-later
"""Selbsttest für tools/port_core.py (ohne Quartus).

Aufruf (aus dem Projektverzeichnis Retro25):
    python tools/test_port_core.py
Prüft die Textumformungen an kleinen Beispielen, wie sie in NES_MiSTer
vorkamen. Ausgabe "PASS: test_port_core" oder die erste Abweichung.
"""
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import port_core as pc  # noqa: E402


def src_of(text: str, eol: str = "\r\n", name: str = "x.sv") -> pc.Src:
    d = Path(tempfile.mkdtemp())
    p = d / name
    p.write_bytes(text.replace("\n", eol).encode("utf-8"))
    return pc.Src(p)


def check(name: str, got: str, want: str) -> None:
    if got != want:
        print(f"FAIL: {name}\n--- erwartet ---\n{want}\n--- erhalten ---\n{got}")
        sys.exit(1)


def t_13386() -> None:
    s = src_of(
        "module m(input clk, output [7:0] q, output reg r, output ok);\n"
        "wire a;\n"
        "wire [3:0] b, c;\n"
        "wire d = clk;\n"
        "assign ok = 1'b1;\n"
        "always @(posedge clk) begin\n"
        "\ta <= 1;\n"
        "\tcase (b)\n"
        "\t\t2'b00: c = 4'd1;\n"
        "\tendcase\n"
        "\tq <= 8'd0;\n"
        "\tr <= 1'b0;\n"
        "end\n"
        "endmodule")
    n = pc.fix13386_text(s)
    check("13386 Anzahl", str(n), "2")   # a; Zeile "b, c" (c in case); q steht in der ANSI-Liste
    lines = s.text.split("\r\n")
    check("13386 a", lines[1], "logic a;" + pc.NOTE_LOGIC)
    check("13386 b,c", lines[2], "logic [3:0] b, c;" + pc.NOTE_LOGIC)
    check("13386 d bleibt", lines[3], "wire d = clk;")
    check("CRLF erhalten", str("\r\n" in s.text and "\n" not in s.text.replace("\r\n", "")), "True")

    s = src_of(
        "module m(\n"
        "\tinput clk,\n"
        "\toutput [7:0] q,\n"
        "\toutput   reg r\n"
        ");\n"
        "always @(posedge clk) q <= 8'd1;\n"
        "always @(posedge clk) r <= 1'b1;\n"
        "endmodule", "\n")
    pc.fix13386_text(s)
    lines = s.text.split("\n")
    check("13386 output", lines[2], "\toutput logic [7:0] q,")
    check("13386 output reg bleibt", lines[3], "\toutput   reg r")

    # Verilog-2001 (.v): reg statt logic; auskommentiertes Modul bleibt
    s = src_of(
        "module m(input clk, output q);\n"
        "wire a;\n"
        "always @(posedge clk) begin a <= 1; q <= 0; end\n"
        "endmodule\n"
        "/*module old(\n"
        "\toutput q\n"
        ");\n"
        "assign q = 1;\n"
        "endmodule*/", "\n", "x.v")
    n = pc.fix13386_text(s)
    lines = s.text.split("\n")
    check(".v Anzahl", str(n), "1")
    check(".v reg", lines[1].split("//")[0].strip(), "reg a;")
    check("Blockkommentar bleibt", lines[5], "\toutput q")


def t_implicit() -> None:
    s = src_of(
        "module m(\n"
        "\tinput clk\n"
        ");\n"
        "sub u(.a(x), .b(y), .c(z));\n"
        "wire [7:0] x = 8'd5;\n"
        "wire [3:0] y;\n"
        "wire z = clk;\n"
        "endmodule", "\n")
    log = pc.fix_implicit_text(s, [(4, "x"), (4, "z"), (4, "y")], {6})
    want = ("module m(\n\tinput clk\n);\n"
            f"{pc.NOTE_ASSIGN}\nwire [7:0] x;\n{pc.NOTE_ASSIGN}\nwire z;\n"
            f"{pc.NOTE_MOVE}\nwire [3:0] y;\n"
            "sub u(.a(x), .b(y), .c(z));\n"
            "assign x = 8'd5;\n"
            "// Retro25: Deklaration nach oben gezogen (16746): wire [3:0] y;\n"
            "assign z = clk;\n"
            "endmodule")
    check("implizite Netze", s.text, want)
    check("implizit Protokoll", str(len(log)), "3")


def t_16754() -> None:
    s = src_of(
        "always @(posedge clk) begin\n"
        "\treg [4:0] cnt = 0;\n"
        "\treg pald = 0, pald2 = 1'b0;\n"
        "\treg init_old=0; // alt\n"
        "\treg [1:0] st = 2'd1;\n"
        "end", "\n")
    log = pc.fix16754_text(s, [(2, "cnt"), (3, "pald"), (4, "init_old"), (5, "st")])
    lines = s.text.split("\n")
    check("16754 cnt", lines[1], "\treg [4:0] cnt;" + pc.NOTE_16754)
    check("16754 zwei", lines[2], "\treg pald, pald2;" + pc.NOTE_16754)
    check("16754 Kommentar", lines[3], "\treg init_old; // alt")
    check("16754 nicht 0 bleibt", lines[4], "\treg [1:0] st = 2'd1;")
    check("16754 Protokoll", str(len(log)), "4")


def t_vhdl_case() -> None:
    text = ("case s is\n  when \"00\" => a <= '1';\n  when \"11\" => a <= '0';\nend case;\n"
            "case t is\n  when A => null;\n  when others => null;\nend case;\n")
    check("VHDL case ohne others", str(pc.vhdl_case_without_others(text)), "[3]")


if __name__ == "__main__":
    t_13386()
    t_implicit()
    t_16754()
    t_vhdl_case()
    print("PASS: test_port_core")
