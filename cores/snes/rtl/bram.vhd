-- SPDX-License-Identifier: GPL-3.0-or-later
--------------------------------------------------------------------------------
-- bram.vhd (Retro25) — Ersatz für SNES_MiSTer rtl/bram.vhd auf Agilex 5
--
-- Zweck: dieselben Entities wie MiSTers Datei (spram, spram_sz, dpram,
--   dpram_dif, dpram_difclk) mit gleichen Generics und Ports (zusätzliche
--   byteena-Ports mit Vorgabe, wie beim MegaDrive), aber als inferierte RAMs
--   statt altsyncram. Abgeleitet von cores/megadrive/rtl/bram.vhd; Gründe dort
--   und in docs/core-portieren.md:
--   - altsyncram BIDIR_DUAL_PORT mit clock1 lehnt Agilex 5 ab (272006);
--   - verschieden breite Ports -> zwei Bänke (OAM 16/32, ARAM und BSRAM 8/16);
--   - Byte-Enables nur als getrennte 8-bit-Speicher (sonst Flipflops);
--   - init_file = " " lässt Quartus Pro abstürzen -> ram_init_file nur mit
--     echter Datei.
-- Zusätzlich zum MegaDrive:
--   - Breiten, die kein Vielfaches von 8 sind (CGRAM 15, SPR_BUF 9 bit): ein
--     Speicher in voller Breite, ohne Byte-Freigaben;
--   - dpram mit .mif (BSX: zwei Leseports auf eine Tabelle);
--   - dpram_difclk, bei dem BEIDE Ports schreiben (CX4: CLK und not CLK) —
--     Agilex 5 kann kein True-Dual-Port-RAM mit zwei Takten (22556). Lösung
--     unten: alle Schreibvorgänge im Takt von Port A, zwei Kopien zum Lesen.
-- Takt: spram/spram_sz/dpram/dpram_dif ein Takt (clock); dpram_difclk zwei
--   Takte (clock0, clock1), siehe dort.
-- Verhalten wie MiSTers altsyncram-Einstellung:
--   - Ausgang nicht registriert (Lesedaten einen Takt nach der Adresse),
--   - Lesen beim Schreiben am selben Port liefert die neuen Daten,
--   - cs = 0 sperrt das Schreiben und setzt q auf alle Einsen,
--   - enable (clocken) nutzt SNES_MiSTer nicht; hier ohne Wirkung.
--   Gleichzeitiger Zugriff beider Ports auf dieselbe Adresse: undefiniert.
-- Testbench: tb/tb_snes_bram.v (Questa)
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
	-- ganze Breite in einem Speicher: mit .mif oder ohne Byte-Raster
	constant whole    : boolean := has_init or data_width mod 8 /= 0;
	-- Speicher in voller Tiefe 2**addr_width, Zugriff ohne "mod numwords":
	-- bei krummem numwords (DSP-1: 8096, 7168) baute Quartus daraus eine
	-- Division und das ROM in Logik (5 000 LUTs). Über numwords hinaus greift
	-- der Core nie zu; die .mif ist dann kürzer als der Speicher (127005).
	constant DEPTH    : integer := 2**addr_width;
	signal q0 : std_logic_vector(data_width-1 downto 0);
	signal addr_r : integer range 0 to DEPTH-1 := 0;
begin
	q <= q0 when cs = '1' else (others => '1');

	-- ROM/RAM mit Inhalt aus .mif (DSP-1, CX4). Das Attribut nur mit echter
	-- Datei: ram_init_file = " " lässt Quartus Pro abstürzen (osi_sys.c,
	-- "required_unc_path_size") — daher getrennt vom Fall ohne Datei.
	g_init : if has_init generate
		type mem_t is array(0 to DEPTH-1) of std_logic_vector(data_width-1 downto 0);
		signal ram : mem_t;
		attribute ram_init_file : string;
		attribute ram_init_file of ram : signal is mem_init_file;
		attribute ramstyle : string;
		attribute ramstyle of ram : signal is "M20K";
	begin
		-- Ausgang im Takt gelesen (ROM-Muster). Mit registrierter Adresse und
		-- kombinatorischem Lesen (wie unten) rechnete Quartus Pro die nie
		-- beschriebenen Tabellen in Logik um, auch mit ramstyle M20K: DSP-1
		-- 5 200 LUTs, CX4 434. Für ROMs gleichwertig (ein Takt Latenz); wird
		-- doch geschrieben, liefert dieser Port beim Schreiben den alten Wert.
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					ram(to_integer(unsigned(address))) <= data;
				end if;
				q0 <= ram(to_integer(unsigned(address)));
			end if;
		end process;
	end generate;

	-- krumme Breite ohne .mif: ein Speicher in voller Breite
	g_odd : if whole and not has_init generate
		type mem_t is array(0 to DEPTH-1) of std_logic_vector(data_width-1 downto 0);
		signal ram : mem_t;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					ram(to_integer(unsigned(address))) <= data;
				end if;
				addr_r <= to_integer(unsigned(address));
			end if;
		end process;
		q0 <= ram(addr_r);
	end generate;

	-- Byte-Spuren (Intels Vorlage "single-port RAM with byte enable")
	g_bytes : if not whole generate
		type word_t is array(0 to NB-1) of std_logic_vector(7 downto 0);
		type mem_t is array(0 to DEPTH-1) of word_t;
		signal ram : mem_t;
	begin
		process(clock) begin
			if rising_edge(clock) then
				if wren = '1' and cs = '1' then
					for i in 0 to NB-1 loop
						if byteena(i) = '1' then
							ram(to_integer(unsigned(address)))(i) <= data(8*i+7 downto 8*i);
						end if;
					end loop;
				end if;
				addr_r <= to_integer(unsigned(address));
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
-- dpram_same: Baustein für dpram_dif — zwei gleich breite Ports, EIN Takt;
-- der schreibende Port liest dabei den neuen Wert.
-- Breite Vielfaches von 8, ohne .mif: je Byte ein eigener 8-bit-Speicher
-- (True-Dual-Port mit Byte-Enables erkennt Quartus Pro nicht, MegaDrive);
-- byteena wird zur Schreibfreigabe der Bank. Sonst ein Speicher in voller
-- Breite (byteena ohne Wirkung), auf Wunsch mit .mif.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram_same is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " "
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

architecture rtl of dpram_same is
	constant NB       : integer := data_width / 8;
	constant has_init : boolean := mem_init_file /= " " and mem_init_file /= "";
	constant whole    : boolean := has_init or data_width mod 8 /= 0;
begin
	g_byte : if not whole generate
		g_b : for i in 0 to NB-1 generate
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
	end generate;

	-- mit .mif (BSX); Attribut nur mit echter Datei (" " -> Absturz, s. o.)
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
				a := to_integer(unsigned(address_a));
				if wren_a = '1' then
					ram(a) := data_a;
				end if;
				q_a <= ram(a);
			end if;
		end process;

		process(clock)
			variable b : integer;
		begin
			if rising_edge(clock) then
				b := to_integer(unsigned(address_b));
				if wren_b = '1' then
					ram(b) := data_b;
				end if;
				q_b <= ram(b);
			end if;
		end process;
	end generate;

	-- krumme Breite ohne .mif (CGRAM 15, SPR_BUF 9 bit)
	g_odd : if whole and not has_init generate
		type mem_t is array(0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
		shared variable ram : mem_t;
		attribute ramstyle : string;
		attribute ramstyle of ram : variable is "no_rw_check";
	begin
		process(clock)
			variable a : integer;
		begin
			if rising_edge(clock) then
				a := to_integer(unsigned(address_a));
				if wren_a = '1' then
					ram(a) := data_a;
				end if;
				q_a <= ram(a);
			end if;
		end process;

		process(clock)
			variable b : integer;
		begin
			if rising_edge(clock) then
				b := to_integer(unsigned(address_b));
				if wren_b = '1' then
					ram(b) := data_b;
				end if;
				q_b <= ram(b);
			end if;
		end process;
	end generate;
end architecture;


--------------------------------------------------------------------------------
-- dpram_dif: zwei Ports, EIN Takt, Breiten im Verhältnis 1:1 oder 1:2
-- (Port A schmal). Bei 1:2 zwei Bänke (dpram_same) in der Breite von Port A;
-- Port A wählt mit seinem untersten Adressbit die Bank (Bit 0 = 0: untere
-- Bits des breiten Worts, wie altsyncram), Port B greift auf beide zu.
-- .mif nur bei 1:1.
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
	constant R : integer := data_width_b / data_width_a;   -- 1 oder 2
	signal q0 : std_logic_vector(data_width_a-1 downto 0);
	signal q1 : std_logic_vector(data_width_b-1 downto 0);
	signal wa, wb : std_logic;   -- Port-Map braucht Signale (VHDL-93: global statisch)
begin
	wa <= wren_a and cs_a;
	wb <= wren_b and cs_b;
	assert (R = 1 or (R = 2 and data_width_a mod 8 = 0))
	       and data_width_a * 2**addr_width_a = data_width_b * 2**addr_width_b
		report "dpram_dif (Retro25): nur 1:1 oder 1:2 (A schmal, Vielfaches von 8)"
		severity failure;
	assert R = 1 or mem_init_file = " " or mem_init_file = ""
		report "dpram_dif (Retro25): mem_init_file nur bei gleich breiten Ports" severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');

	g_same : if R = 1 generate
		ram : entity work.dpram_same
		generic map(addr_width_b, data_width_b, mem_init_file)
		port map(clock, address_a, data_a, wa, byteena_a, q0,
		         address_b, data_b, wb, byteena_b, q1);
	end generate;

	-- 1:2 — zwei gleich breite Bänke statt eines Speichers mit Byte-Spuren
	-- (ein über das Adressbit berechneter Spur-Index wird zu Flipflops)
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
			generic map(addr_width_b, W, " ")
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
-- dpram_difclk: zwei Takte (clock0 für Port A, clock1 für Port B), gleich
-- breite Ports, beide dürfen schreiben.
--
-- Agilex 5 kann kein True-Dual-Port-RAM mit zwei Takten (22556). SNES_MiSTer
-- nutzt es für CX4 (DATA_RAM: Port A = CX4 auf "not CLK", Port B = SNES-CPU
-- auf CLK, beide schreiben) und GSU (CACHE, nur Port B schreibt). Hier:
--   1. Ein Schreibwunsch von Port B wird mit clock1 gespeichert und mit der
--      nächsten Flanke von clock0 ausgeführt — bei clock0 = not clock1 einen
--      halben Takt später. Schreiben also nur im Takt clock0.
--   2. Zwei Kopien mit denselben Schreibvorgängen: Kopie A liest mit clock0
--      (Port A), Kopie B mit clock1 (Port B). Jede ist ein Simple-Dual-Port-
--      RAM (ein Schreib-, ein Leseport), das Agilex 5 auch mit zwei Takten kann.
-- Kosten: doppelter Speicher (CX4 4 KB, GSU 512 Byte).
-- Nur für clock0 und clock1 aus demselben Takt (gleich oder invertiert): Der
-- Übergang in Schritt 1 ist dann ein normaler, geprüfter Pfad, kein CDC.
-- Schreiben beide Ports in derselben Flanke von clock0, gewinnt Port A
-- (bei CX4 schließt sich das aus: Port B schreibt nur bei angehaltenem CX4).
-- Port B liest den eigenen, gerade geschriebenen Wert erst einen halben Takt
-- später (MiSTer: sofort) — die SNES-CPU liest frühestens im nächsten Takt.
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
		clock0    : in  std_logic;
		address_a : in  std_logic_vector(addr_width_a-1 downto 0);
		data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
		enable_a  : in  std_logic := '1';
		wren_a    : in  std_logic := '0';
		q_a       : out std_logic_vector(data_width_a-1 downto 0);
		cs_a      : in  std_logic := '1';
		clock1    : in  std_logic;
		address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
		data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
		enable_b  : in  std_logic := '1';
		wren_b    : in  std_logic := '0';
		q_b       : out std_logic_vector(data_width_b-1 downto 0);
		cs_b      : in  std_logic := '1'
	);
end entity;

architecture rtl of dpram_difclk is
	constant N : integer := 2**addr_width_a;
	type mem_t is array(0 to N-1) of std_logic_vector(data_width_a-1 downto 0);
	signal ram_a, ram_b : mem_t;
	attribute ramstyle : string;
	attribute ramstyle of ram_a : signal is "no_rw_check";
	attribute ramstyle of ram_b : signal is "no_rw_check";

	-- Schreibwunsch von Port B (clock1)
	signal pb_we   : std_logic := '0';
	signal pb_addr : std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
	signal pb_data : std_logic_vector(data_width_b-1 downto 0) := (others => '0');
	-- gemeinsamer Schreibport (clock0)
	signal w_en    : std_logic;
	signal w_addr  : integer range 0 to N-1;
	signal w_data  : std_logic_vector(data_width_a-1 downto 0);

	signal ra_r : integer range 0 to N-1 := 0;
	signal rb_r : integer range 0 to N-1 := 0;
	signal q0, q1 : std_logic_vector(data_width_a-1 downto 0);
begin
	assert data_width_a = data_width_b and addr_width_a = addr_width_b
		report "dpram_difclk (Retro25): nur gleich breite Ports" severity failure;
	assert mem_init_file = " " or mem_init_file = ""
		report "dpram_difclk (Retro25): mem_init_file wird nicht unterstützt" severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');

	process(clock1) begin
		if rising_edge(clock1) then
			pb_we   <= wren_b and cs_b;
			pb_addr <= address_b;
			pb_data <= data_b;
		end if;
	end process;

	-- Port A hat Vorrang
	w_en   <= '1' when (wren_a = '1' and cs_a = '1') or pb_we = '1' else '0';
	w_addr <= to_integer(unsigned(address_a)) when wren_a = '1' and cs_a = '1'
	          else to_integer(unsigned(pb_addr));
	w_data <= data_a when wren_a = '1' and cs_a = '1' else pb_data;

	-- Kopie A: schreiben und lesen mit clock0 (neue Daten beim Schreiben)
	process(clock0) begin
		if rising_edge(clock0) then
			if w_en = '1' then
				ram_a(w_addr) <= w_data;
			end if;
			ra_r <= to_integer(unsigned(address_a));
		end if;
	end process;
	q0 <= ram_a(ra_r);

	-- Kopie B: schreiben mit clock0, lesen mit clock1
	process(clock0) begin
		if rising_edge(clock0) then
			if w_en = '1' then
				ram_b(w_addr) <= w_data;
			end if;
		end if;
	end process;
	process(clock1) begin
		if rising_edge(clock1) then
			q1 <= ram_b(to_integer(unsigned(address_b)));
		end if;
	end process;
end architecture;
