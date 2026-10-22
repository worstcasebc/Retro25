// SPDX-License-Identifier: GPL-3.0-or-later
// smbus.cpp (DE25) — Ersatz für Main_MiSTers smbus.cpp.
//
// Auf dem DE10-Nano hängt der HDMI-Sender (ADV7513) am I2C des HPS, Main
// spricht ihn über /dev/i2c-N an. Beim DE25-Nano hängt er an FPGA-Pins; der
// I2C-Master liegt im FPGA (sys/de25/i2c_master_de25.v) und ist über die
// LW-Bridge erreichbar (physisch 0x2001_6000):
//   +0  W Befehl: [7:0] Byte, [8] Start davor, [9] Stopp danach, [10] Lesen,
//                 [11] beim Lesen NACK senden
//       R Status: [7:0] gelesenes Byte, [8] busy, [9] NACK beim letzten
//                 Schreibbyte, [16] own, [31:24] 0x49
//   +4  RW [0] own (Master treibt die Pins; sonst konfiguriert hdmi_config
//          im FPGA den Sender), [31:16] Viertelperiode (0 = 100 kHz)
// Die Schnittstelle (smbus.h) bleibt gleich, damit video.cpp und
// hdmi_cec.cpp unverändert bleiben. Es gibt genau einen Bus (Nummer 0);
// ein "Dateideskriptor" ist hier 0x100 | Geräteadresse.

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include "smbus.h"

#define I2C_PAGE     0x20016000
#define I2C_ID       0x49
#define CMD_START    (1 << 8)
#define CMD_STOP     (1 << 9)
#define CMD_READ     (1 << 10)
#define CMD_NACK     (1 << 11)
#define ST_BUSY      (1 << 8)
#define ST_NACK      (1 << 9)
#define FD_FLAG      0x100

static volatile uint32_t *i2c_regs = 0;
static pthread_mutex_t i2c_lock = PTHREAD_MUTEX_INITIALIZER;

static int i2c_map()
{
	if (i2c_regs) return 1;

	int fd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
	if (fd < 0)
	{
		printf("i2c: /dev/mem nicht zu öffnen\n");
		return 0;
	}
	void *map = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, I2C_PAGE);
	close(fd);
	if (map == MAP_FAILED)
	{
		printf("i2c: mmap 0x%X fehlgeschlagen\n", I2C_PAGE);
		return 0;
	}

	volatile uint32_t *regs = (volatile uint32_t *)map;
	if ((regs[0] >> 24) != I2C_ID)
	{
		printf("i2c: kein I2C-Master im Core (Status 0x%08X)\n", regs[0]);
		munmap(map, 0x1000);
		return 0;
	}

	regs[1] = 1;   // Bus übernehmen: ab jetzt stellt Main den HDMI-Sender ein
	i2c_regs = regs;
	return 1;
}

static uint64_t now_us()
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

// Ein Byte übertragen; liefert den Status oder -1 bei Zeitüberschreitung.
// Sicherheitshalber erst warten, bis busy sichtbar wird (ein Byte dauert
// >= 90 µs, ein Lesezugriff nur wenige µs), dann bis busy wieder weg ist:
// so kann ein veralteter Status von vor dem Befehl nicht als "fertig" gelten.
static int i2c_cmd(uint32_t cmd)
{
	i2c_regs[0] = cmd;
	uint64_t t0 = now_us();
	int seen = 0;
	while (1)
	{
		uint32_t st = i2c_regs[0];
		if (st & ST_BUSY) seen = 1;
		else if (seen) return (int)st;
		if (now_us() - t0 > 10000)
		{
			printf("i2c: Zeitüberschreitung (Befehl 0x%03X, busy %s)\n", cmd, seen ? "bleibt" : "kam nie");
			return -1;
		}
	}
}

static void i2c_stop()
{
	// Nach einem NACK mitten im Ablauf den Bus freigeben. Der Master kennt
	// keinen Stopp ohne Byte; ein Start mit der reservierten Adresse 0x7F
	// (lesen, bestätigt niemand) und Stopp danach erfüllt denselben Zweck.
	i2c_cmd(CMD_START | CMD_STOP | 0xFF);
}

static int dev_addr(int file)
{
	return ((file & ~0x7F) == FD_FLAG) ? (file & 0x7F) : -1;
}

// Adresse senden (mit Start); 0 = bestätigt
static int i2c_addr(int addr, int rd, int stop)
{
	int st = i2c_cmd(CMD_START | (stop ? CMD_STOP : 0) | (addr << 1) | (rd ? 1 : 0));
	if (st < 0) return -EIO;
	if (st & ST_NACK)
	{
		if (!stop) i2c_stop();
		return -ENXIO;
	}
	return 0;
}

static int i2c_wr(uint8_t b, int stop)
{
	int st = i2c_cmd((stop ? CMD_STOP : 0) | b);
	if (st < 0) return -EIO;
	if (st & ST_NACK)
	{
		if (!stop) i2c_stop();
		return -EIO;
	}
	return 0;
}

static int i2c_rd(int last)
{
	int st = i2c_cmd(CMD_READ | (last ? (CMD_NACK | CMD_STOP) : 0));
	if (st < 0) return -EIO;
	return st & 0xFF;
}

// Schreiben: Adresse, Befehl, n Datenbytes, Stopp
static int xfer_write(int file, int has_cmd, uint8_t command, int len, const uint8_t *data)
{
	int addr = dev_addr(file);
	if (addr < 0 || !i2c_regs) return -EBADF;
	pthread_mutex_lock(&i2c_lock);
	int res = i2c_addr(addr, 0, !has_cmd && !len);
	if (!res && has_cmd) res = i2c_wr(command, !len);
	for (int i = 0; !res && i < len; i++) res = i2c_wr(data[i], i == len - 1);
	pthread_mutex_unlock(&i2c_lock);
	return res;
}

// Lesen: [Adresse, Befehl, Repeated Start], Adresse+R, n Bytes, NACK, Stopp
static int xfer_read(int file, int has_cmd, uint8_t command, int len, uint8_t *data)
{
	int addr = dev_addr(file);
	if (addr < 0 || !i2c_regs) return -EBADF;
	pthread_mutex_lock(&i2c_lock);
	int res = 0;
	if (has_cmd)
	{
		res = i2c_addr(addr, 0, 0);
		if (!res) res = i2c_wr(command, 0);
	}
	if (!res) res = i2c_addr(addr, 1, 0);
	for (int i = 0; !res && i < len; i++)
	{
		int v = i2c_rd(i == len - 1);
		if (v < 0) res = v;
		else data[i] = (uint8_t)v;
	}
	pthread_mutex_unlock(&i2c_lock);
	return res;
}

int i2c_open(int dev_address, int is_smbus, int force_bus, int *found_bus)
{
	if (force_bus > 0 || dev_address < 0 || dev_address > 0x7F) return -1;
	if (!i2c_map()) return -1;

	int fd = FD_FLAG | dev_address;
	int res;
	if (is_smbus) res = i2c_smbus_write_quick(fd, 0);
	else res = i2c_smbus_read_byte(fd);
	if (res < 0) return -1;

	printf("Opened FPGA-I2C for device 0x%X\n", dev_address);
	if (found_bus) *found_bus = 0;
	return fd;
}

void i2c_close(int fd)
{
	(void)fd;
}

int i2c_smbus_write_quick(int file, uint8_t value)
{
	int addr = dev_addr(file);
	if (addr < 0 || !i2c_regs) return -EBADF;
	pthread_mutex_lock(&i2c_lock);
	int res = i2c_addr(addr, value & 1, 1);
	pthread_mutex_unlock(&i2c_lock);
	return res;
}

int i2c_smbus_read_byte(int file)
{
	uint8_t v;
	int res = xfer_read(file, 0, 0, 1, &v);
	return res < 0 ? res : v;
}

int i2c_smbus_write_byte(int file, uint8_t value)
{
	return xfer_write(file, 1, value, 0, 0);
}

int i2c_smbus_read_byte_data(int file, uint8_t command)
{
	uint8_t v;
	int res = xfer_read(file, 1, command, 1, &v);
	return res < 0 ? res : v;
}

int i2c_smbus_write_byte_data(int file, uint8_t command, uint8_t value)
{
	return xfer_write(file, 1, command, 1, &value);
}

int i2c_smbus_read_word_data(int file, uint8_t command)
{
	uint8_t v[2];
	int res = xfer_read(file, 1, command, 2, v);
	return res < 0 ? res : (v[0] | (v[1] << 8));
}

int i2c_smbus_write_word_data(int file, uint8_t command, uint16_t value)
{
	uint8_t v[2] = { (uint8_t)value, (uint8_t)(value >> 8) };
	return xfer_write(file, 1, command, 2, v);
}

int i2c_smbus_process_call(int file, uint8_t command, uint16_t value)
{
	// Schreiben + Lesen ohne Stopp dazwischen: von Main nicht benutzt
	(void)file; (void)command; (void)value;
	return -1;
}

int i2c_smbus_read_block_data(int file, uint8_t command, uint8_t *values)
{
	// Länge kommt vom Gerät: von Main nicht benutzt
	(void)file; (void)command; (void)values;
	return -EOPNOTSUPP;
}

int i2c_smbus_write_block_data(int file, uint8_t command, uint8_t length, const uint8_t *values)
{
	if (length > 32) length = 32;
	uint8_t buf[33];
	buf[0] = length;
	for (int i = 0; i < length; i++) buf[i + 1] = values[i];
	return xfer_write(file, 1, command, length + 1, buf);
}

int i2c_smbus_read_i2c_block_data(int file, uint8_t command, uint8_t length, uint8_t *values)
{
	if (length > 32) length = 32;
	if (!length) return 0;
	int res = xfer_read(file, 1, command, length, values);
	return res < 0 ? res : length;
}

int i2c_smbus_write_i2c_block_data(int file, uint8_t command, uint8_t length, const uint8_t *values)
{
	if (length > 32) length = 32;
	return xfer_write(file, 1, command, length, values);
}

int i2c_smbus_block_process_call(int file, uint8_t command, uint8_t length, uint8_t *values)
{
	(void)file; (void)command; (void)length; (void)values;
	return -1;
}
