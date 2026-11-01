-- SPDX-License-Identifier: GPL-3.0-or-later
--------------------------------------------------------------------------------
-- mlab.vhd (Retro25) — Ersatz für SNES_MiSTer rtl/mlab.vhd (wie MegaDrive)
--
-- Zweck: kleine RAMs mit asynchronem Lesen (SNES: PPU RANGE_TBL u. a.) mit
--   gleicher Entity wie das Original, aber inferiert statt altdpram
--   (Cyclone-Primitive). Gleich wie cores/megadrive/rtl/mlab.vhd (MiSTers
--   Originale beider Cores sind identisch).
-- Takt: clock (Schreiben). Lesen ASYNCHRON wie im Original
--   (rdaddress_reg/outdata_reg = UNREGISTERED): q folgt rdaddress ohne Takt;
--   Quartus bildet das auf MLAB ab.
-- Schreiben: data/wraddress/wren mit der Taktflanke (indata_reg/wraddress_reg
--   = INCLOCK). cs = 0 setzt q auf alle Einsen (Schreiben bleibt wie im
--   Original unberührt).
-- Testbench: tb/tb_md_bram.v (Questa, gleiche Datei)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mlab is
	generic (
		addr_width : integer := 8;
		data_width : integer := 8
	);
	port (
		clock     : in  std_logic;
		rdaddress : in  std_logic_vector(addr_width-1 downto 0);
		wraddress : in  std_logic_vector(addr_width-1 downto 0);
		data      : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		wren      : in  std_logic := '0';
		q         : out std_logic_vector(data_width-1 downto 0);
		cs        : in  std_logic := '1'
	);
end entity;

architecture rtl of mlab is
	type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	signal ram : mem_t;
	attribute ramstyle : string;
	attribute ramstyle of ram : signal is "MLAB, no_rw_check";
begin
	process(clock) begin
		if rising_edge(clock) then
			if wren = '1' then
				ram(to_integer(unsigned(wraddress))) <= data;
			end if;
		end if;
	end process;

	q <= ram(to_integer(unsigned(rdaddress))) when cs = '1' else (others => '1');
end architecture;
