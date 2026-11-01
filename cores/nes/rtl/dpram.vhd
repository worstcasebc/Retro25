-- SPDX-License-Identifier: GPL-3.0-or-later
--------------------------------------------------------------------------------
-- dpram.vhd (Retro25) — Ersatz für NES_MiSTer rtl/dpram.vhd auf Agilex 5
--
-- Zweck: Dieselben Entities wie MiSTers Datei (spram, spram_sz, dpram), mit
--   gleichen Generics und Ports, aber als inferierte RAMs statt altsyncram.
--   Gründe (siehe sys/de25/README.md, Quartus-Pro-Fallen):
--   - altsyncram BIDIR_DUAL_PORT mit clock1 lehnt Agilex 5 ab (272006).
--   - init_file = " " (Leerzeichen = "keine Datei") lässt Quartus Pro
--     abstürzen -> ram_init_file nur setzen, wenn eine Datei genannt ist.
-- Takt: spram/spram_sz ein Takt (clock); dpram hat zwei Takteingänge
--   (clock_a, clock_b), Agilex-5-M20K erlaubt bei zwei schreibenden Ports
--   aber nur EINEN Takt (Fehler 22556) -> beide an denselben Takt legen
--   (NES-EEPROM: pro/NES.sv taktet Port B mit clk85 statt clk).
-- Verhalten wie MiSTers altsyncram-Einstellung:
--   - Ausgang nicht registriert (Lesedaten einen Takt nach der Adresse),
--   - Lesen beim Schreiben auf derselben Adresse am selben Port liefert die
--     neuen Daten (NEW_DATA_NO_NBE_READ),
--   - spram: cs = 0 sperrt das Schreiben und setzt q auf alle Einsen,
--   - byteena ist im NES überall '1' und wird nicht ausgewertet; enable
--     nutzt MiSTers spram_sz ebenfalls nicht.
--   Gleichzeitiger Zugriff beider dpram-Ports auf dieselbe Adresse ist
--   undefiniert (no_rw_check) — wie bei MiSTer mit zwei Takten auch.
-- Testbench: tb/tb_nes_dpram.v (Questa)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spram_sz is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		numwords      : integer := 2**8;
		mem_init_file : string := " ";
		mem_name      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(addr_width-1 downto 0);
		data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

architecture rtl of spram_sz is
	subtype word_t is std_logic_vector(data_width-1 downto 0);
	type mem_t is array(0 to numwords-1) of word_t;
	signal q0 : word_t;
	constant has_init : boolean := mem_init_file /= " " and mem_init_file /= "";
begin
	q <= q0 when cs = '1' else (others => '1');

	-- Zwei Zweige, weil das Attribut nur mit echter Datei gesetzt werden darf
	g_init : if has_init generate
		signal ram : mem_t;
		attribute ram_init_file : string;
		attribute ram_init_file of ram : signal is mem_init_file;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					ram(to_integer(unsigned(address))) <= data;
					q0 <= data;
				else
					q0 <= ram(to_integer(unsigned(address)));
				end if;
			end if;
		end process;
	end generate;

	g_plain : if not has_init generate
		signal ram : mem_t;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					ram(to_integer(unsigned(address))) <= data;
					q0 <= data;
				else
					q0 <= ram(to_integer(unsigned(address)));
				end if;
			end if;
		end process;
	end generate;
end architecture;


library ieee;
use ieee.std_logic_1164.all;

entity spram is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " ";
		mem_name      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(addr_width-1 downto 0);
		data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

architecture rtl of spram is
begin
	spram_sz : entity work.spram_sz
	generic map(addr_width, data_width, 2**addr_width, mem_init_file, mem_name)
	port map(clock, address, data, enable, wren, q, cs);
end architecture;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
	generic (
		init_file     : string := " ";
		widthad_a     : natural;
		width_a       : natural := 8;
		outdata_reg_a : string := "UNREGISTERED";
		outdata_reg_b : string := "UNREGISTERED"
	);
	port (
		address_a : in  std_logic_vector(widthad_a-1 downto 0);
		address_b : in  std_logic_vector(widthad_a-1 downto 0) := (others => '0');
		clock_a   : in  std_logic;
		clock_b   : in  std_logic;
		data_a    : in  std_logic_vector(width_a-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(width_a-1 downto 0) := (others => '0');
		wren_a    : in  std_logic := '0';
		wren_b    : in  std_logic := '0';
		byteena_a : in  std_logic_vector(width_a/8-1 downto 0) := (others => '1');
		byteena_b : in  std_logic_vector(width_a/8-1 downto 0) := (others => '1');
		q_a       : out std_logic_vector(width_a-1 downto 0);
		q_b       : out std_logic_vector(width_a-1 downto 0)
	);
end entity;

architecture rtl of dpram is
	subtype word_t is std_logic_vector(width_a-1 downto 0);
	type mem_t is array(0 to 2**widthad_a-1) of word_t;
	-- Zwei Ports mit eigenem Takt schreiben -> shared variable (Intels
	-- Vorlage "True Dual-Port RAM, dual clock")
	shared variable ram : mem_t;
	attribute ramstyle : string;
	attribute ramstyle of ram : variable is "no_rw_check";
begin
	assert init_file = " " or init_file = ""
		report "dpram (Retro25): init_file wird nicht unterstuetzt" severity failure;

	process(clock_a) begin
		if rising_edge(clock_a) then
			if wren_a = '1' then
				ram(to_integer(unsigned(address_a))) := data_a;
				q_a <= data_a;
			else
				q_a <= ram(to_integer(unsigned(address_a)));
			end if;
		end if;
	end process;

	process(clock_b) begin
		if rising_edge(clock_b) then
			if wren_b = '1' then
				ram(to_integer(unsigned(address_b))) := data_b;
				q_b <= data_b;
			else
				q_b <= ram(to_integer(unsigned(address_b)));
			end if;
		end if;
	end process;
end architecture;
