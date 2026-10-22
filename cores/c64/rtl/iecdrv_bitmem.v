// SPDX-License-Identifier: GPL-3.0-or-later
// iecdrv_bitmem — Spurpuffer des 1541-Laufwerks für Agilex 5 (Retro25).
//
// Ersatz für MiSTers iecdrv_bitmem (rtl/iec_drive/iecdrv_misc.sv), gleiche
// Schnittstelle: Port A liest/schreibt Bytes (Spurdaten von/zur SD-Karte),
// Port B einzelne Bits (Schreib-/Lesekopf); Bit b von Port B ist Bit b[2:0]
// von Wort b[ADDRWIDTH+2:3].
//
// Warum neu: MiSTer beschreibt einen Speicher mit zwei Portbreiten. Agilex 5
// kann im echten Zwei-Port-Betrieb (beide Ports schreiben) nur gleiche
// Breiten und einen Takt (altera_syncram, Fehler 272006). C64-DE25 zerlegte
// den Speicher deshalb in acht 1-Bit-Speicher — mit MiSTers bitmem64 wurden
// daraus 64 M20K je Laufwerk. Hier: ein 8-bit-Speicher (1 M20K bei 1024
// Wörtern); Port B schreibt ein Bit per Lesen-Ändern-Schreiben.
//
// Takt: nur clock_a. clock_b muss derselbe Takt sein (im C64-Core beide
// clk_sys) — ein anderer Takt an clock_b wird nicht unterstützt.
//
// Zeitverhalten wie im Original: Eingänge einen Takt registriert, Daten einen
// Takt später (zusammen zwei Takte nach der Adresse); beim Schreiben liefert
// der Port im Folgetakt den geschriebenen Wert.
// Lesen-Ändern-Schreiben: Ein Bitschreiben von Port B liest im ersten Takt
// das Wort und schreibt im zweiten das geänderte Wort zurück. In diesem
// zweiten Takt belegt das Zurückschreiben Port B: Ein Lesezugriff auf ein
// ANDERES Wort genau in diesem Takt liefert einen Takt lang den Inhalt des
// geschriebenen Worts. Das Laufwerk schreibt höchstens ein Bit je Bitzelle
// (dutzende Takte) und liest danach dasselbe Wort, das stört dort nicht.
// Gleichzeitiges Schreiben beider Ports in dasselbe Wort ist (wie beim
// Original) nicht definiert.

module iecdrv_bitmem #(parameter ADDRWIDTH = 10)
(
	input                      clock_a,
	input      [ADDRWIDTH-1:0] address_a,
	input                [7:0] data_a,
	input                      wren_a,
	output               [7:0] q_a,

	input                      clock_b,      // muss gleich clock_a sein (unbenutzt)
	input      [ADDRWIDTH+2:0] address_b,
	input                      data_b,
	input                      wren_b,
	output                     q_b
);

// no_rw_check: Agilex 5 kann im Zwei-Port-Betrieb nicht garantieren, was ein
// Port beim gleichzeitigen Schreiben des anderen auf dieselbe Adresse liest —
// ohne das Attribut baut Quartus den Speicher aus Registern (Info 276009).
// Der eine Fall, der beim Laufwerk vorkommt, ist unten weitergeleitet.
(* ramstyle = "no_rw_check" *) reg [7:0] ram[0:(1<<ADDRWIDTH)-1];

// ---- Port A: wie im Original ---------------------------------------------
reg                 wren_a_d;
reg [ADDRWIDTH-1:0] address_a_d;
reg           [7:0] data_a_d;
always @(posedge clock_a) begin
	wren_a_d    <= wren_a;
	address_a_d <= address_a;
	data_a_d    <= data_a;
end

reg [7:0] qa_word;                 // Ausgang des Speichers an Port A
always @(posedge clock_a) begin
	if (wren_a_d) begin
		ram[address_a_d] <= data_a_d;
		qa_word <= data_a_d;
	end else begin
		qa_word <= ram[address_a_d];
	end
end

// ---- Port B: Byte-Zugriff, Bit per Lesen-Ändern-Schreiben -----------------
reg                 wren_b_d;
reg [ADDRWIDTH+2:0] address_b_d;
reg                 data_b_d;
always @(posedge clock_a) begin
	wren_b_d    <= wren_b;
	address_b_d <= address_b;
	data_b_d    <= data_b;
end

// Takt 1 eines Bitschreibens: Wort lesen (wie ein Lesezugriff) und merken,
// welches Bit mit welchem Wert zu ersetzen ist.
reg                 wpend_q;        // im Folgetakt Wort zurückschreiben
reg [ADDRWIDTH-1:0] waddr_q;
reg           [2:0] wbit_q;
reg                 wval_q;
reg           [2:0] bsel_q;         // Bitnummer des laufenden Lesezugriffs
always @(posedge clock_a) begin
	wpend_q <= wren_b_d;
	waddr_q <= address_b_d[ADDRWIDTH+2:3];
	wbit_q  <= address_b_d[2:0];
	wval_q  <= data_b_d;
	bsel_q  <= address_b_d[2:0];
end

reg  [7:0] qb_word;                 // Ausgang des Speichers an Port B
wire [7:0] wword = (qb_word & ~(8'd1 << wbit_q)) | ({7'd0, wval_q} << wbit_q);

// Takt 2: geändertes Wort zurückschreiben (sonst normal lesen). Eine Adresse
// für Lesen und Schreiben an Port B — sonst erkennt Quartus keinen M20K
// (getrennte Lese- und Schreibadresse wären ein dritter Port).
wire [ADDRWIDTH-1:0] addr_b = wpend_q ? waddr_q : address_b_d[ADDRWIDTH+2:3];
always @(posedge clock_a) begin
	if (wpend_q) begin
		ram[addr_b] <= wword;
		qb_word <= wword;
	end else begin
		qb_word <= ram[addr_b];
	end
end

// Im Takt nach dem Schreibbefehl liefert das Original den geschriebenen Wert
assign q_b = wpend_q ? wval_q : qb_word[bsel_q];

// Weiterleitung an Port A: Im Original steht ein Bit von Port B einen Takt
// früher im Speicher. Liest Port A das Wort genau in dem Takt, in dem es hier
// erst zurückgeschrieben wird, bekommt er das neue Wort (Umschalter hinter
// dem Speicherausgang, damit Quartus den Speicher als M20K erkennt).
reg       fwd_q;
reg [7:0] fwd_word_q;
always @(posedge clock_a) begin
	fwd_q      <= wpend_q && !wren_a_d && (address_a_d == waddr_q);
	fwd_word_q <= wword;
end
assign q_a = fwd_q ? fwd_word_q : qa_word;

endmodule
