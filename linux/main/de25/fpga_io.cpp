// SPDX-License-Identifier: GPL-3.0-or-later
// fpga_io.cpp — DE25-Nano-Fassung (Retro25) von Main_MiSTers fpga_io.cpp.
//
// Ersetzt linux/vendor/main_mister/fpga_io.cpp beim Bauen (build.sh).
// Schnittstelle (fpga_io.h) und alles ab fpga_gpo_write sind wie im Original;
// neu ist die unterste Schicht:
//
//  - gp_out/gp_in: Beim Cyclone V Register im HPS (0xFF706010/14). Auf dem
//    Agilex 5 bildet sie hps_gp_bridge im FPGA nach, an der LW-Bridge:
//    0x2001_0100 GPO, 0x104 GPI, 0x108 STATUS, 0x10C ID ("R25G").
//    Ein GPO-Schreibzugriff kehrt erst zurück, wenn der Core den Wert
//    übernommen hat — so gehen auch die schnellen Blockfunktionen nicht
//    verloren (siehe sys/de25/hps_gp_bridge.v).
//  - Core laden: nicht mehr selbst über den FPGA-Manager, sondern wie in P0
//    über den Kernel: Kern nach /run/retro25-fw/retro25/main.core.rbf, dann ein
//    Device-Tree-Overlay auf /fpga-region (configfs). Das Overlay
//    (main.dtbo) legt linux/main/install.sh einmalig an.
//  - Schutz: Während das Fabric neu geladen wird (oder wenn kein Retro25-Core
//    darin ist), darf niemand die LW-Bridge anfassen — ein Lesezugriff ins
//    Leere bringt Linux mit einem SError zum Absturz. fpga_ok merkt sich, ob
//    die Brücke da ist; alle gp-Zugriffe prüfen es.
//  - DDR-Sperre: Wird das FPGA mitten in einem F2SDRAM-Zugriff (Scaler,
//    DDRAM des Cores) neu geladen, hängt die SMMU und mit ihr ganz Linux
//    ("arm-smmu-v3 … CMD_SYNC timeout"). Vor dem Laden hält f2s_halt() daher
//    alle drei DDR-Ports im FPGA an und wartet, bis sie leer sind
//    (Register 0x2001_7000, sys/de25/f2s_halt_de25.v).
//  - WLAN: Der USB-WLAN-Stick (rt2800usb) stolpert über das Neuladen. Vorher
//    und nachher ruft fpga_load_rbf das Skript SWITCH_HOOK mit "pre"/"post"
//    auf (schaltet z. B. per nmcli das Funknetz aus und wieder ein, P0).
//  - Neustart: über /sbin/reboot statt über den Reset-Manager.

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include "fpga_io.h"
#include "file_io.h"
#include "input.h"
#include "osd.h"
#include "menu.h"
#include "shmem.h"
#include "offload.h"

#define GP_PAGE      0x20010000          // Seite der LW-Bridge mit hps_gp_bridge
#define GP_PAGE_SIZE 0x1000
#define GP_OFFSET    0x100
#define GP_ID        0x52323547          // "R25G"

#define HALT_PAGE    0x20017000          // DDR-Sperre (disk_m0 + 0x3000)
#define HALT_ID      0x4844              // "HD" in [31:16]
#define HALT_IDLE    0xE                 // [3:1] alle drei Ports leer

// Der Core liegt im RAM (/run), nicht in /lib/firmware: Das Root-Dateisystem
// ist schreibgeschützt (P3a, linux/system). Der Kernel sucht Firmware zuerst
// in FW_PATH (Parameter von firmware_class), dann in /lib/firmware — dort
// liegt das Overlay main.dtbo, das install.sh einmalig anlegt.
#define FW_PATH      "/run/retro25-fw"
#define FW_DIR       FW_PATH "/retro25"
#define FW_CORE      FW_DIR "/main.core.rbf"
#define FW_OVERLAY   "retro25/main.dtbo" // relativ zum Firmware-Suchpfad
#define FW_PARAM     "/sys/module/firmware_class/parameters/path"
#define OVERLAY_DIR  "/sys/kernel/config/device-tree/overlays/retro25"
#define FPGA_STATE   "/sys/class/fpga_manager/fpga0/state"
#define SWITCH_HOOK  "/usr/local/bin/retro25-switch-hook"

static volatile uint32_t *gp_regs = 0;   // [0] GPO, [1] GPI, [2] STATUS, [3] ID
static int fpga_ok = 0;                  // 1 = Brücke da, Zugriffe erlaubt

// Zustand des FPGA-Managers als Text ("" wenn nicht lesbar)
static void fpga_mgr_state(char *buf, size_t size)
{
	buf[0] = 0;
	int fd = open(FPGA_STATE, O_RDONLY);
	if (fd < 0) return;
	int n = read(fd, buf, size - 1);
	close(fd);
	buf[n > 0 ? n : 0] = 0;
}

// "operating" = Linux hat den Kern selbst geladen, Fabric läuft
static int fpga_mgr_operating()
{
	char buf[32];
	fpga_mgr_state(buf, sizeof(buf));
	return !strncmp(buf, "operating", 9);
}

// Darf die Brücke gelesen werden? Außer "operating" auch "unknown": So meldet
// sich der Manager nach dem Booten, wenn U-Boot den Start-Core geladen hat
// (HPS-first: U-Boot lädt immer einen Kern, bevor Linux startet, und gibt die
// Brücken frei). Ob es ein Retro25-Core ist, entscheidet danach die ID.
// Alle anderen Zustände (Laden läuft, Fehler) sperren die Brücke.
static int fpga_mgr_configured()
{
	char buf[32];
	fpga_mgr_state(buf, sizeof(buf));
	return !strncmp(buf, "operating", 9) || !strncmp(buf, "unknown", 7);
}

// Prüft, ob ein Retro25-Core mit hps_gp_bridge geladen ist, und setzt fpga_ok.
static int fpga_check_bridge()
{
	fpga_ok = 0;
	if (!gp_regs || !fpga_mgr_configured()) return 0;
	uint32_t id = gp_regs[3];
	if (id != GP_ID)
	{
		printf("FPGA: keine hps_gp_bridge gefunden (ID 0x%08X statt 0x%08X)\n", id, GP_ID);
		return 0;
	}
	fpga_ok = 1;
	return 1;
}

// Hält die DDR-Ports des laufenden Cores an (siehe Kopf). Nur bei geladenem
// Retro25-Core aufrufen (fpga_ok). Rückgabe 0 = leer, -2 = Core ohne Sperre
// (älterer Stand, Laden trotzdem), -1/-3 = nicht leer: dann nicht laden,
// die Sperre ist wieder aufgehoben.
static int f2s_halt()
{
	int fd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
	if (fd < 0) return -1;
	void *map = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, HALT_PAGE);
	close(fd);
	if (map == MAP_FAILED) return -1;
	volatile uint32_t *reg = (volatile uint32_t *)map;

	int ret = 0;
	uint32_t st = reg[0];
	if ((st >> 16) != HALT_ID)
	{
		printf("FPGA: Core ohne DDR-Sperre (0x%08X) - Laden auf eigene Gefahr\n", st);
		ret = -2;
	}
	else
	{
		struct timespec t0, t1;
		clock_gettime(CLOCK_MONOTONIC, &t0);
		reg[0] = 1;
		double dt;
		do
		{
			st = reg[0];
			clock_gettime(CLOCK_MONOTONIC, &t1);
			dt = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
		} while ((st & HALT_IDLE) != HALT_IDLE && dt < 0.5);

		if ((st & HALT_IDLE) == HALT_IDLE) printf("FPGA: DDR-Ports angehalten (%.1f ms)\n", dt * 1000);
		else
		{
			printf("FPGA: DDR-Ports nicht leer (Status 0x%08X)\n", st);
			reg[0] = 0;
			ret = -3;
		}
	}
	munmap(map, 0x1000);
	return ret;
}

static void switch_hook(const char *phase)
{
	if (access(SWITCH_HOOK, X_OK)) return;
	char cmd[256];
	snprintf(cmd, sizeof(cmd), "%s %s", SWITCH_HOOK, phase);
	int res = system(cmd);
	if (res) printf("%s: Rückgabe %d\n", cmd, res);
}

static int write_file(const char *path, const void *data, size_t size)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) return -1;
	const uint8_t *p = (const uint8_t *)data;
	while (size)
	{
		ssize_t n = write(fd, p, size);
		if (n <= 0) { close(fd); return -1; }
		p += n;
		size -= n;
	}
	return close(fd);
}

static int read_text(const char *path, char *buf, int size)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) return -1;
	int n = read(fd, buf, size - 1);
	close(fd);
	if (n < 0) n = 0;
	buf[n] = 0;
	while (n && (buf[n - 1] == '\n' || buf[n - 1] == ' ')) buf[--n] = 0;
	return n;
}

// Lädt den Kern über den Kernel: Overlay auf /fpga-region, dessen
// firmware-name auf FW_CORE zeigt. Das Schreiben von "path" kehrt erst zurück,
// wenn der FPGA-Manager fertig ist (ca. 2 s).
static int socfpga_load(const void *rbf_data, size_t rbf_size)
{
	mkdir(FW_PATH, 0755);
	mkdir(FW_DIR, 0755);
	char fw_path[256];
	if (read_text(FW_PARAM, fw_path, sizeof(fw_path)) < 0 || strcmp(fw_path, FW_PATH))
	{
		// sonst setzt ihn /etc/tmpfiles.d/retro25.conf beim Booten
		if (write_file(FW_PARAM, FW_PATH, strlen(FW_PATH)))
			printf("FPGA: Firmware-Pfad nicht setzbar: %s\n", strerror(errno));
	}
	if (write_file(FW_CORE, rbf_data, rbf_size))
	{
		printf("FPGA: %s nicht schreibbar: %s\n", FW_CORE, strerror(errno));
		return -1;
	}

	// Altes Overlay entfernen — das lädt nichts, gibt nur den Knoten frei.
	if (!access(OVERLAY_DIR, F_OK) && rmdir(OVERLAY_DIR))
	{
		printf("FPGA: altes Overlay nicht entfernbar: %s\n", strerror(errno));
		return -2;
	}
	if (mkdir(OVERLAY_DIR, 0755))
	{
		printf("FPGA: %s nicht anlegbar: %s (configfs, Module of-fpga-region/stratix10-soc?)\n",
			OVERLAY_DIR, strerror(errno));
		return -3;
	}

	struct timespec t0, t1;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	int fd = open(OVERLAY_DIR "/path", O_WRONLY);
	if (fd < 0) return -4;
	ssize_t n = write(fd, FW_OVERLAY, strlen(FW_OVERLAY));
	close(fd);
	clock_gettime(CLOCK_MONOTONIC, &t1);

	char status[32];
	read_text(OVERLAY_DIR "/status", status, sizeof(status));
	int ok = (n == (ssize_t)strlen(FW_OVERLAY)) && !strcmp(status, "applied") && fpga_mgr_operating();
	printf("FPGA: Overlay %s, %.2f s\n", status,
		(t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9);
	return ok ? 0 : -5;
}

int fpga_load_rbf(const char *name, const char *cfg, const char *xml)
{
	OsdDisable();
	static char path[1024];
	int ret = 0;

	// Original: Core mit eigener Konfiguration über einen Neustart laden
	// (U-Boot-Umgebung im DDR). Gibt es hier nicht — der Kern wird normal geladen.
	if (cfg) printf("FPGA: Konfiguration %s wird ignoriert (DE25)\n", cfg);

	printf("Loading RBF: %s\n", name);

	if(name[0] == '/') strcpy(path, name);
	else sprintf(path, "%s/%s", !strcasecmp(name, "menu.rbf") ? getStorageDir(0) : getRootDir(), name);

	int rbf = open(path, O_RDONLY);
	if (rbf < 0)
	{
		char error[4096];
		snprintf(error,4096,"%s\nNot Found", name);
		printf("Couldn't open file %s\n", path);
		Info(error,5000);
		return -1;
	}
	else
	{
		struct stat64 st;
		if (fstat64(rbf, &st)<0)
		{
			printf("Couldn't get info of file %s\n", path);
			ret = -1;
		}
		else
		{
			printf("Bitstream size: %lld bytes\n", (long long)st.st_size);

			void *buf = malloc(st.st_size);
			if (!buf)
			{
				printf("Couldn't allocate %llu bytes.\n", (unsigned long long)st.st_size);
				ret = -1;
			}
			else
			{
				fpga_core_reset(1);
				if (read(rbf, buf, st.st_size)<st.st_size)
				{
					printf("Couldn't read file %s\n", name);
					ret = -1;
				}
				else
				{
					void *p = buf;
					__off64_t sz = st.st_size;
					if (!memcmp(buf, "MiSTer", 6))
					{
						sz = *(uint32_t*)(((uint8_t*)buf) + 12);
						p = (void*)(((uint8_t*)buf) + 16);
					}
					int halt = fpga_ok ? f2s_halt() : 0;
					if (halt == -1 || halt == -3)
					{
						// Laden würde Linux aufhängen: lieber beim alten Core bleiben
						free(buf);
						close(rbf);
						fpga_core_reset(0);
						Info("DDR busy,\ncore not loaded", 5000);
						return -1;
					}
					fpga_ok = 0;             // ab hier keine Zugriffe auf die Brücke
					switch_hook("pre");
					ret = socfpga_load(p, sz);
					switch_hook("post");
					if (ret)
					{
						printf("Error %d while loading %s\n", ret, path);
					}
					else
					{
						fpga_check_bridge();
					}
				}
				free(buf);
			}
		}
	}
	close(rbf);

	app_restart(!strcasecmp(name, "menu.rbf") ? "menu.rbf" : path, xml);
	return ret;
}

// Ab hier wie im Original — nur der Registerzugriff geht über gp_regs und
// ist durch fpga_ok geschützt. Ohne Brücke liest GPI 0x8000_0000 (Bit 31 =
// "FPGA nicht bereit"), genau wie es Main_MiSTer auswertet.

static uint32_t gpo_copy = 0;
void inline fpga_gpo_write(uint32_t value)
{
	gpo_copy = value;
	if (fpga_ok) gp_regs[0] = value;
}

#define fpga_gpo_writeN(value) do { if (fpga_ok) gp_regs[0] = (value); } while (0)
#define fpga_gpo_read() gpo_copy
#define fpga_gpi_read() (int)(fpga_ok ? gp_regs[1] : 0x80000000)

// Original: Zugriff auf weitere Register des Cores an der LW-Bridge
// (0xFF200000). Auf dem DE25 belegt dort das HPS-System eigene Fenster; kein
// Teil von Main nutzt die Funktionen — daher bewusst ohne Wirkung.
void fpga_core_write(uint32_t offset, uint32_t value)
{
	(void)offset;
	(void)value;
}

uint32_t fpga_core_read(uint32_t offset)
{
	(void)offset;
	return 0;
}

int fpga_io_init()
{
	if (!gp_regs)
	{
		int fd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
		if (fd < 0)
		{
			printf("Error: Unable to open /dev/mem!\n");
			return -1;
		}
		void *map = mmap(0, GP_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, GP_PAGE);
		close(fd);
		if (map == MAP_FAILED)
		{
			printf("Error: Unable to mmap LW bridge (0x%X)!\n", GP_PAGE);
			return -1;
		}
		gp_regs = (volatile uint32_t *)((uint8_t *)map + GP_OFFSET);
	}

	if (!fpga_check_bridge()) return -1;
	fpga_gpo_write(0);
	return 0;
}

int fpga_core_id()
{
	uint32_t gpo = (fpga_gpo_read() & 0x7FFFFFFF);
	fpga_gpo_write(gpo);
	uint32_t coretype = fpga_gpi_read();
	gpo |= 0x80000000;
	fpga_gpo_write(gpo);

	if ((coretype >> 8) != 0x5CA623) return -1;
	return coretype & 0xFF;
}

int fpga_get_fio_size()
{
	return (fpga_gpi_read() >> 16) & 1;
}

int fpga_get_io_version()
{
	return (fpga_gpi_read() >> 18) & 3;
}

void fpga_set_led(uint32_t on)
{
	uint32_t gpo = fpga_gpo_read();
	fpga_gpo_write(on ? gpo | 0x20000000 : gpo & ~0x20000000);
}

int fpga_get_buttons()
{
	fpga_gpo_write(fpga_gpo_read() | 0x80000000);
	int gpi = fpga_gpi_read();
	if (gpi < 0) gpi = 0; // FPGA is not in user mode. Ignore the data;
	return (gpi >> 29) & 3;
}

int fpga_get_io_type()
{
	fpga_gpo_write(fpga_gpo_read() | 0x80000000);
	return (fpga_gpi_read() >> 28) & 1;
}

int fpga_get_hdmi_int()
{
	return (fpga_gpi_read() >> 20) & 1;
}

void reboot(int cold)
{
	(void)cold;
	sync();
	fpga_core_reset(1);

	usleep(500000);

	// Original: Neustart über den Reset-Manager, Kalt/Warm-Kennung im DDR für
	// U-Boot. Hier ein normaler Linux-Neustart (U-Boot lädt den Start-Core).
	execl("/sbin/reboot", "reboot", (char *)NULL);
	while (1) sleep(1);
}

char *getappname()
{
	static char dest[PATH_MAX];
	memset(dest, 0, sizeof(dest));

	char path[64];
	sprintf(path, "/proc/%d/exe", getpid());
	if (readlink(path, dest, PATH_MAX - 1) < 0) dest[0] = 0;

	return dest;
}

void app_restart(const char *path, const char *xml, const char *exe)
{
	sync();
	fpga_core_reset(1);

	input_switch(0);
	input_uinp_destroy();

	offload_stop();

	const char *appname = exe ? exe : getappname();
	printf("restarting to %s\n", appname);
	fflush(stdout);

	// DE25: Das Original startet per doppeltem fork + setsid einen losgelösten
	// Nachfolger und beendet sich. Unter systemd (retro25-main.service) sähe
	// das wie ein Ende von Main aus: systemd räumte den Nachfolger weg und
	// startete Main mit dem alten Core-Pfad neu. Daher ohne fork: Main
	// ersetzt sich selbst, die PID bleibt dieselbe.
	execl(appname, appname, path, xml, NULL);

	printf("execl %s: %s\n", appname, strerror(errno));
	printf("Something went wrong. Rebooting...\n");
	reboot(1);
	_exit(1);
}

void fpga_core_reset(int reset)
{
	uint32_t gpo = fpga_gpo_read() & ~0xC0000000;
	fpga_gpo_write(reset ? gpo | 0x40000000 : gpo | 0x80000000);
}

int is_fpga_ready(int quick)
{
	if (quick)
	{
		return (fpga_gpi_read() >= 0);
	}

	return fpga_check_bridge();
}

#define SSPI_STROBE  (1<<17)
#define SSPI_ACK     SSPI_STROBE

void fpga_spi_en(uint32_t mask, uint32_t en)
{
	uint32_t gpo = fpga_gpo_read() | 0x80000000;
	fpga_gpo_write(en ? gpo | mask : gpo & ~mask);
}

void fpga_wait_to_reset()
{
	printf("FPGA is not ready. JTAG uploading?\n");
	printf("Waiting for FPGA to be ready...\n");

	fpga_core_reset(1);

	while (!is_fpga_ready(0))
	{
		sleep(1);
	}
	reboot(0);
}

uint16_t fpga_spi(uint16_t word)
{
	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE)) | word;

	fpga_gpo_write(gpo);
	fpga_gpo_write(gpo | SSPI_STROBE);

	int gpi;
	do
	{
		gpi = fpga_gpi_read();
		if (gpi < 0)
		{
			printf("GPI[31]==1. FPGA is uninitialized?\n");
			fpga_wait_to_reset();
			return 0;
		}
	} while (!(gpi & SSPI_ACK));

	fpga_gpo_write(gpo);

	do
	{
		gpi = fpga_gpi_read();
		if (gpi < 0)
		{
			printf("GPI[31]==1. FPGA is uninitialized?\n");
			fpga_wait_to_reset();
			return 0;
		}
	} while (gpi & SSPI_ACK);

	return (uint16_t)gpi;
}

uint16_t fpga_spi_fast(uint16_t word)
{
	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE)) | word;
	fpga_gpo_write(gpo);
	fpga_gpo_write(gpo | SSPI_STROBE);
	fpga_gpo_write(gpo);
	return (uint16_t)fpga_gpi_read();
}

// Die Blockfunktionen: im Original von Hand 16-fach entrollt. Der Bus-
// Handshake der Brücke kostet ohnehin weit mehr als die Schleife; daher hier
// schlicht als Schleife — gleiche Zugriffsfolge wie im Original.

void fpga_spi_fast_block_write(const uint16_t *buf, uint32_t length)
{
	uint32_t gpoH = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));
	uint32_t gpo = gpoH;

	while (length--)
	{
		gpo = gpoH | *buf++;
		fpga_gpo_writeN(gpo);
		fpga_gpo_writeN(gpo | SSPI_STROBE);
	}
	fpga_gpo_write(gpo);
}

void fpga_spi_fast_block_read(uint16_t *buf, uint32_t length)
{
	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));

	while (length--)
	{
		fpga_gpo_writeN(gpo | SSPI_STROBE);
		fpga_gpo_writeN(gpo);
		*buf++ = (uint16_t)fpga_gpi_read();
	}
}

void fpga_spi_fast_block_write_8(const uint8_t *buf, uint32_t length)
{
	uint32_t gpoH = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));
	uint32_t gpo = gpoH;

	while (length--)
	{
		gpo = gpoH | *buf++;
		fpga_gpo_writeN(gpo);
		fpga_gpo_writeN(gpo | SSPI_STROBE);
	}

	fpga_gpo_write(gpo);
}

void fpga_spi_fast_block_read_8(uint8_t *buf, uint32_t length)
{
	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));

	while (length--)
	{
		fpga_gpo_writeN(gpo | SSPI_STROBE);
		fpga_gpo_writeN(gpo);
		*buf++ = (uint8_t)fpga_gpi_read();
	}
}

void fpga_spi_fast_block_write_be(const uint16_t *buf, uint32_t length)
{
	uint32_t gpoH = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));
	uint32_t gpo = gpoH;

	while (length--)
	{
		uint16_t tmp = *buf++;
		tmp = (tmp << 8) | (tmp >> 8);
		gpo = gpoH | tmp;
		fpga_gpo_writeN(gpo);
		fpga_gpo_writeN(gpo | SSPI_STROBE);
	}
	fpga_gpo_write(gpo);
}

void fpga_spi_fast_block_read_be(uint16_t *buf, uint32_t length)
{
	uint32_t gpo = (fpga_gpo_read() & ~(0xFFFF | SSPI_STROBE));

	while (length--)
	{
		fpga_gpo_writeN(gpo | SSPI_STROBE);
		fpga_gpo_writeN(gpo);
		uint16_t tmp = (uint16_t)fpga_gpi_read();
		*buf++ = (tmp << 8) | (tmp >> 8);
	}
}
