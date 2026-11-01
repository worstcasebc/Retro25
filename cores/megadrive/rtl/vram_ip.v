// SPDX-License-Identifier: GPL-3.0-or-later
// vram_ip (Retro25) — Ersatz für MegaDrive_MiSTer rtl/ram_md.v auf Agilex 5
//
// Zweck: eine Bank des Nuked-MD-VRAMs (nuked-md/vram.v instanziiert 8 Stück):
//   256 Wörter x 256 bit, 32 Byte-Freigaben, ein Port, ein Takt.
// Warum direkt altera_syncram statt inferiert (bram.vhd spram): Quartus Pro
//   zerlegt inferierte RAMs mit Byte-Freigaben in ein RAM je Byte — hier
//   8 x 32 = 256 RAMs zu 256 x 8 bit, jedes belegt einen ganzen M20K
//   (444 statt 358 Blöcke). altera_syncram mit width_byteena packt eine Bank
//   in 7 M20K (Breite 40, Byte-Freigaben je 8 bit).
// Verhalten: Lesedaten einen Takt nach der Adresse (Ausgang nicht
//   registriert), wie MiSTers spram. Lesen beim Schreiben derselben Adresse:
//   undefiniert (DONT_CARE) — vram.v liest und schreibt nie gleichzeitig
//   (rd und wr schließen sich über WE/OE aus).
// Testbench: tb/tb_md_vram_ip.v (Questa, altera_lnsim)

module vram_ip
(
	input   [7:0] address,
	input  [31:0] byteena,
	input         clock,
	input [255:0] data,
	input         wren,
	output[255:0] q
);

altera_syncram #(
	.operation_mode                ("SINGLE_PORT"),
	.width_a                       (256),
	.widthad_a                     (8),
	.numwords_a                    (256),
	.width_byteena_a               (32),
	.byte_size                     (8),
	.outdata_reg_a                 ("UNREGISTERED"),
	.outdata_aclr_a                ("NONE"),
	.clock_enable_input_a          ("BYPASS"),
	.clock_enable_output_a         ("BYPASS"),
	.read_during_write_mode_port_a ("DONT_CARE"),
	.power_up_uninitialized        ("FALSE"),
	.ram_block_type                ("M20K"),
	.intended_device_family        ("Agilex 5"),
	.lpm_type                      ("altera_syncram")
) ram (
	.clock0    (clock),
	.address_a (address),
	.data_a    (data),
	.wren_a    (wren),
	.byteena_a (byteena),
	.q_a       (q)
);

endmodule
