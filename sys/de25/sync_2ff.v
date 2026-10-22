// SPDX-License-Identifier: GPL-3.0-or-later
// Übernommen aus C64-DE25 (gleicher Autor).
// sync_2ff — Zwei-Flipflop-Synchronizer für asynchrone Eingänge.
//
// Zweck:  Taster/Schalter ändern sich zu beliebigen Zeitpunkten, also auch
//         genau an der Taktflanke. Das erste Flipflop kann dadurch kurz
//         "unentschieden" (metastabil) sein; das zweite gibt ihm einen ganzen
//         Takt Zeit, sich zu beruhigen. Erst d_sync_q darf in die Logik.
// Takt:   clk (Zieldomäne). Bewusst ohne Reset: Der Synchronizer liefert auch
//         das Reset-Signal selbst und muss daher immer durchlaufen.
// Ports:  d_async — asynchroner Eingang, d_sync_q — um 2 Takte verzögert.

`default_nettype none

module sync_2ff #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] d_async,
    output reg  [WIDTH-1:0] d_sync_q
);

    reg [WIDTH-1:0] meta_q;

    always @(posedge clk) begin
        meta_q   <= d_async;
        d_sync_q <= meta_q;
    end

endmodule

`default_nettype wire
