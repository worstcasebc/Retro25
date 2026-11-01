-- SPDX-License-Identifier: GPL-3.0-or-later
--------------------------------------------------------------------------------
-- bram.vhd (Retro25) — Ersatz für MegaDrive_MiSTer rtl/bram.vhd auf Agilex 5
--
-- Zweck: dieselben Entities wie MiSTers Datei (spram, spram_sz, dpram,
--   dpram_dif, dpram_difclk) mit gleichen Generics und Ports, aber als
--   inferierte RAMs statt altsyncram. Gründe (sys/de25/README.md,
--   docs/core-portieren.md):
--   - altsyncram BIDIR_DUAL_PORT mit clock1 lehnt Agilex 5 ab (272006);
--   - verschieden breite Ports, die beide schreiben, kann Agilex 5 nicht
--     (MegaDrive: Cartridge-SRAM 8 Bit / 16 Bit) -> zwei 8-bit-Bänke;
--   - Byte-Enables nur als getrennte 8-bit-Speicher (sonst baut Quartus Pro
--     Flipflops statt M20K);
--   - init_file = " " lässt Quartus Pro abstürzen -> ram_init_file nur mit
--     echter Datei.
-- Takt: spram/spram_sz/dpram/dpram_dif ein Takt (clock); dpram_difclk zwei
--   Takte — nur zulässig, wenn höchstens EIN Port schreibt (Agilex 5 kann kein
--   True-Dual-Port-RAM mit zwei Takten, 22556; MegaDrive: TMSS-ROM).
-- Verhalten wie MiSTers altsyncram-Einstellung:
--   - Ausgang nicht registriert (Lesedaten einen Takt nach der Adresse),
--   - Lesen beim Schreiben am selben Port liefert die neuen Daten (nicht
--     freigegebene Bytes: alter Inhalt),
--   - cs = 0 sperrt das Schreiben und setzt q auf alle Einsen,
--   - enable (clocken) nutzt MegaDrive nicht; hier ohne Wirkung.
--   Gleichzeitiger Zugriff beider Ports auf dieselbe Adresse: undefiniert.
-- Testbench: tb/tb_md_bram.v (Questa)
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
		byteena : in  std_logic_vector((data_width/8)-1 downto 0) := (others => '1');
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

architecture rtl of spram_sz is
	constant NB       : integer := data_width/8;
	constant has_init : boolean := mem_init_file /= " " and mem_init_file /= "";
	signal q0 : std_logic_vector(data_width-1 downto 0);
	signal addr_r : integer range 0 to numwords-1 := 0;
begin
	q <= q0 when cs = '1' else (others => '1');

	-- ROM/RAM mit Inhalt aus .mif: einfache Wortbreite (Byte-Freigaben nur
	-- für RAMs ohne Datei; MegaDrive: boot_rom 8 Bit)
	g_init : if has_init generate
		type mem_t is array(0 to numwords-1) of std_logic_vector(data_width-1 downto 0);
		signal ram : mem_t;
		attribute ram_init_file : string;
		attribute ram_init_file of ram : signal is mem_init_file;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					ram(to_integer(unsigned(address)) mod numwords) <= data;
				end if;
				addr_r <= to_integer(unsigned(address)) mod numwords;
			end if;
		end process;
		q0 <= ram(addr_r);   -- registrierte Adresse: neue Daten beim Schreiben
	end generate;

	-- Byte-Spuren (Intels Vorlage "single-port RAM with byte enable")
	g_bytes : if not has_init generate
		type word_t is array(0 to NB-1) of std_logic_vector(7 downto 0);
		type mem_t is array(0 to numwords-1) of word_t;
		signal ram : mem_t;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					for i in 0 to NB-1 loop
						if byteena(i) = '1' then
							ram(to_integer(unsigned(address)) mod numwords)(i) <= data(8*i+7 downto 8*i);
						end if;
					end loop;
				end if;
				addr_r <= to_integer(unsigned(address)) mod numwords;
			end if;
		end process;
		g_q : for i in 0 to NB-1 generate
			q0(8*i+7 downto 8*i) <= ram(addr_r)(i);
		end generate;
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
		byteena : in  std_logic_vector((data_width/8)-1 downto 0) := (others => '1');
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

architecture rtl of spram is
begin
	spram_sz : entity work.spram_sz
	generic map(addr_width, data_width, 2**addr_width, mem_init_file, mem_name)
	port map(clock, address, data, enable, wren, byteena, q, cs);
end architecture;


--------------------------------------------------------------------------------
-- dpram_same: Baustein für dpram_dif — zwei gleich breite Ports, EIN Takt,
-- Byte-Enables; der schreibende Port liest dabei den neuen Wert.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_same is
	generic (
		addr_width : integer := 8;
		data_width : integer := 8
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(addr_width-1 downto 0);
		data_a    : in  std_logic_vector(data_width-1 downto 0);
		wren_a    : in  std_logic;
		byteena_a : in  std_logic_vector((data_width/8)-1 downto 0);
		q_a       : out std_logic_vector(data_width-1 downto 0);
		address_b : in  std_logic_vector(addr_width-1 downto 0);
		data_b    : in  std_logic_vector(data_width-1 downto 0);
		wren_b    : in  std_logic;
		byteena_b : in  std_logic_vector((data_width/8)-1 downto 0);
		q_b       : out std_logic_vector(data_width-1 downto 0)
	);
end entity;

-- Je Byte ein eigener 8-bit-Speicher: Ein True-Dual-Port-RAM mit Byte-
-- Enables (Intels Vorlage, Wort = Byte-Array) erkennt Quartus Pro 26.1 für
-- Agilex 5 nicht — ram_68k (32K x 16) wurde zu 524 288 Flipflops. Gleich breite
-- 8-bit-Bänke ohne Byte-Enable werden erkannt; byteena wird zur
-- Schreibfreigabe der Bank.
architecture rtl of dpram_same is
	constant NB : integer := data_width / 8;
begin
	g_byte : for i in 0 to NB-1 generate
		type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(7 downto 0);
		shared variable ram : mem_t;
		attribute ramstyle : string;
		attribute ramstyle of ram : variable is "no_rw_check";
	begin
		process(clock)
			variable a : integer;
		begin
			if rising_edge(clock) then
				a := to_integer(unsigned(address_a));
				if wren_a = '1' and byteena_a(i) = '1' then
					ram(a) := data_a(8*i+7 downto 8*i);
				end if;
				q_a(8*i+7 downto 8*i) <= ram(a);
			end if;
		end process;

		process(clock)
			variable b : integer;
		begin
			if rising_edge(clock) then
				b := to_integer(unsigned(address_b));
				if wren_b = '1' and byteena_b(i) = '1' then
					ram(b) := data_b(8*i+7 downto 8*i);
				end if;
				q_b(8*i+7 downto 8*i) <= ram(b);
			end if;
		end process;
	end generate;
end architecture;


--------------------------------------------------------------------------------
-- dpram_dif: zwei Ports, EIN Takt, Breiten im Verhältnis 1:1 oder 1:2
-- (Port A schmal). Speicher in der Breite von Port B mit Byte-Spuren; Port A
-- wählt mit seinem untersten Adressbit die Hälfte (unteres Bit 0 = untere
-- Bits des breiten Worts, wie altsyncram).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_dif is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	port (
		clock     : in  std_logic;
		address_a : in  std_logic_vector(addr_width_a-1 downto 0);
		data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
		enable_a  : in  std_logic := '1';
		wren_a    : in  std_logic := '0';
		byteena_a : in  std_logic_vector((data_width_a/8)-1 downto 0) := (others => '1');
		q_a       : out std_logic_vector(data_width_a-1 downto 0);
		cs_a      : in  std_logic := '1';
		address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		byteena_b : in  std_logic_vector((data_width_b/8)-1 downto 0) := (others => '1');
		q_b       : out std_logic_vector(data_width_b-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture rtl of dpram_dif is
	constant R   : integer := data_width_b / data_width_a;   -- 1 oder 2
	signal q0 : std_logic_vector(data_width_a-1 downto 0);
	signal q1 : std_logic_vector(data_width_b-1 downto 0);
	signal wa, wb : std_logic;   -- Port-Map braucht Signale (VHDL-93: global statisch)
begin
	wa <= wren_a and cs_a;
	wb <= wren_b and cs_b;
	assert (R = 1 or R = 2) and data_width_a mod 8 = 0
	       and data_width_a * 2**addr_width_a = data_width_b * 2**addr_width_b
		report "dpram_dif (Retro25): nur Breitenverhältnis 1:1 oder 1:2 (A schmal), Vielfache von 8"
		severity failure;
	assert mem_init_file = " " or mem_init_file = ""
		report "dpram_dif (Retro25): mem_init_file wird nicht unterstützt" severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');

	g_same : if R = 1 generate
		ram : entity work.dpram_same
		generic map(addr_width_b, data_width_b)
		port map(clock, address_a, data_a, wa, byteena_a, q0,
		         address_b, data_b, wb, byteena_b, q1);
	end generate;

	-- 1:2 — zwei gleich breite Bänke statt eines Speichers mit Byte-Spuren:
	-- Ein über das Adressbit berechneter Spur-Index (ram(wa)(lane)) erkennt
	-- Quartus Pro nicht als RAM; 64K x 16 wurden zu Flipflops, die Synthese
	-- lief stundenlang. Bank j = Bits j*data_width_a.. des breiten Worts.
	g_half : if R = 2 generate
		constant W   : integer := data_width_a;
		constant NBA : integer := data_width_a / 8;
		type q_t is array(0 to 1) of std_logic_vector(W-1 downto 0);
		signal qa, qb : q_t;
		signal sel_q  : std_logic := '0';
	begin
		process(clock)
		begin
			if rising_edge(clock) then
				sel_q <= address_a(0);
			end if;
		end process;
		q0 <= qa(1) when sel_q = '1' else qa(0);

		g_bank : for j in 0 to 1 generate
			signal we_a : std_logic;
		begin
			we_a <= wa when (address_a(0) = '1') = (j = 1) else '0';
			ram : entity work.dpram_same
			generic map(addr_width_b, W)
			port map(clock, address_a(addr_width_a-1 downto 1), data_a, we_a, byteena_a, qa(j),
			         address_b, data_b(W*j+W-1 downto W*j), wb,
			         byteena_b(NBA*j+NBA-1 downto NBA*j), qb(j));
			q1(W*j+W-1 downto W*j) <= qb(j);
		end generate;
	end generate;
end architecture;


library ieee;
use ieee.std_logic_1164.all;

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
		byteena_a : in  std_logic_vector((data_width/8)-1 downto 0) := (others => '1');
		q_a       : out std_logic_vector(data_width-1 downto 0);
		cs_a      : in  std_logic := '1';
		address_b : in  std_logic_vector(addr_width-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		byteena_b : in  std_logic_vector((data_width/8)-1 downto 0) := (others => '1');
		q_b       : out std_logic_vector(data_width-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture rtl of dpram is
begin
	ram : entity work.dpram_dif
	generic map(addr_width, data_width, addr_width, data_width, mem_init_file)
	port map(clock, address_a, data_a, enable_a, wren_a, byteena_a, q_a, cs_a,
	         address_b, data_b, enable_b, wren_b, byteena_b, q_b, cs_b);
end architecture;


--------------------------------------------------------------------------------
-- dpram_difclk: zwei Takte. Nur gleich breite Ports; nur ein Port darf
-- schreiben (sonst 22556 in der Synthese). Ein konstantes wren = '0' (Vorgabe)
-- entfernt die Synthese, dann bleibt ein Simple-Dual-Port-RAM.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_difclk is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	port (
		clock_a   : in  std_logic;
		address_a : in  std_logic_vector(addr_width_a-1 downto 0);
		data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
		enable_a  : in  std_logic := '1';
		wren_a    : in  std_logic := '0';
		byteena_a : in  std_logic_vector((data_width_a/8)-1 downto 0) := (others => '1');
		q_a       : out std_logic_vector(data_width_a-1 downto 0);
		cs_a      : in  std_logic := '1';
		clock_b   : in  std_logic;
		address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		byteena_b : in  std_logic_vector((data_width_b/8)-1 downto 0) := (others => '1');
		q_b       : out std_logic_vector(data_width_b-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture rtl of dpram_difclk is
	type mem_t is array(0 to 2**addr_width_a-1) of std_logic_vector(data_width_a-1 downto 0);
	shared variable ram : mem_t;
	attribute ramstyle : string;
	attribute ramstyle of ram : variable is "no_rw_check";
	signal q0 : std_logic_vector(data_width_a-1 downto 0);
	signal q1 : std_logic_vector(data_width_b-1 downto 0);
begin
	assert data_width_a = data_width_b and addr_width_a = addr_width_b
		report "dpram_difclk (Retro25): nur gleich breite Ports" severity failure;
	assert mem_init_file = " " or mem_init_file = ""
		report "dpram_difclk (Retro25): mem_init_file wird nicht unterstützt" severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');

	process(clock_a) begin
		if rising_edge(clock_a) then
			if wren_a = '1' and cs_a = '1' then
				ram(to_integer(unsigned(address_a))) := data_a;
			end if;
			q0 <= ram(to_integer(unsigned(address_a)));
		end if;
	end process;

	process(clock_b) begin
		if rising_edge(clock_b) then
			if wren_b = '1' and cs_b = '1' then
				ram(to_integer(unsigned(address_b))) := data_b;
			end if;
			q1 <= ram(to_integer(unsigned(address_b)));
		end if;
	end process;
end architecture;
