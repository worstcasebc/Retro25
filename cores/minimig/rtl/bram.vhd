-- SPDX-License-Identifier: GPL-3.0-or-later
--------------------------------------------------------------------------------
-- bram.vhd (Retro25) — Ersatz für Minimig-AGA_MiSTer rtl/bram.vhd auf Agilex 5
--
-- Zweck: Entity dpram mit gleichen Generics und Ports wie MiSTers Datei, aber
--   inferiert statt altsyncram (BIDIR_DUAL_PORT mit clock1 lehnt Agilex 5 ab,
--   272006). Der Minimig benutzt aus der Originaldatei nur dpram; spram,
--   dpram_dif und dpram_difclk entfallen deshalb.
-- Takt: ein Takt (clock) für beide Ports.
-- Schnittstelle wie altsyncram des Originals:
--   - Lesedaten einen Takt nach der Adresse,
--   - Lesen beim Schreiben am selben Port liefert die neuen Daten,
--   - cs = 0 sperrt das Schreiben und setzt q auf alle Einsen,
--   - enable_a/b (clocken): Bei 0 steht der Port still; der Minimig lässt sie
--     auf der Vorgabe 1.
--   Gleichzeitiger Zugriff beider Ports auf dieselbe Adresse: undefiniert.
-- Der Speicher bleibt in voller Breite an einem Stück. Anders als beim SNES
--   gibt es keine Byte-Freigaben, und die 40-bit-Cache-Tags würden in 8-bit-
--   Bänken fünf statt eines M20K-Blocks belegen.
-- Testbench: tb/tb_minimig_ram.v (Questa)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " "
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(addr_width-1 downto 0);
		data_a    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable_a  : in  std_logic := '1';
		wren_a    : in  std_logic := '0';
		q_a       : out std_logic_vector(data_width-1 downto 0);
		cs_a      : in  std_logic := '1';
		address_b : in  std_logic_vector(addr_width-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		q_b       : out std_logic_vector(data_width-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture rtl of dpram is
	constant has_init : boolean := mem_init_file /= " " and mem_init_file /= "";
	signal q0, q1 : std_logic_vector(data_width-1 downto 0);
	signal we_a, we_b : std_logic;
begin
	q_a  <= q0 when cs_a = '1' else (others => '1');
	q_b  <= q1 when cs_b = '1' else (others => '1');
	we_a <= wren_a and cs_a;
	we_b <= wren_b and cs_b;

	-- ram_init_file nur mit echter Datei: " " lässt Quartus Pro abstürzen
	-- (docs/core-portieren.md), daher zwei getrennte Zweige.
	g_init : if has_init generate
		type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
		shared variable ram : mem_t;
		attribute ramstyle : string;
		attribute ramstyle of ram : variable is "no_rw_check";
		attribute ram_init_file : string;
		attribute ram_init_file of ram : variable is mem_init_file;
	begin
		process(clock)
			variable a : integer;
		begin
			if rising_edge(clock) then
				if enable_a = '1' then
					a := to_integer(unsigned(address_a));
					if we_a = '1' then
						ram(a) := data_a;
					end if;
					q0 <= ram(a);
				end if;
			end if;
		end process;

		process(clock)
			variable b : integer;
		begin
			if rising_edge(clock) then
				if enable_b = '1' then
					b := to_integer(unsigned(address_b));
					if we_b = '1' then
						ram(b) := data_b;
					end if;
					q1 <= ram(b);
				end if;
			end if;
		end process;
	end generate;

	g_plain : if not has_init generate
		type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
		shared variable ram : mem_t;
		attribute ramstyle : string;
		attribute ramstyle of ram : variable is "no_rw_check";
	begin
		process(clock)
			variable a : integer;
		begin
			if rising_edge(clock) then
				if enable_a = '1' then
					a := to_integer(unsigned(address_a));
					if we_a = '1' then
						ram(a) := data_a;
					end if;
					q0 <= ram(a);
				end if;
			end if;
		end process;

		process(clock)
			variable b : integer;
		begin
			if rising_edge(clock) then
				if enable_b = '1' then
					b := to_integer(unsigned(address_b));
					if we_b = '1' then
						ram(b) := data_b;
					end if;
					q1 <= ram(b);
				end if;
			end if;
		end process;
	end generate;
end architecture;
