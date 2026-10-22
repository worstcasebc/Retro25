// SPDX-License-Identifier: GPL-3.0-or-later
// shmem.cpp — DE25-Nano-Fassung (Retro25) von Main_MiSTers shmem.cpp.
//
// Ersetzt linux/vendor/main_mister/shmem.cpp beim Bauen (build.sh).
// Main_MiSTer bildet mit shmem_map() physische Adressen per /dev/mem ab.
// Beim DE10-Nano liegt dort überall DDR; auf dem Agilex 5 nicht — ein Zugriff
// auf eine leere Adresse bringt Linux mit einem SError zum Absturz. Daher
// lässt diese Fassung nur bekannte Bereiche zu:
//
//  - 0x1FFFF000 (4 KB): Parameterseite. MiSTer legt dort Werte ab, die einen
//    Neustart von Main überleben sollen (SDRAM-Größe, altcfg, U-Boot-Umgebung).
//    Hier: Datei /dev/shm/retro25_param — überlebt den Neustart von Main
//    (Core-Wechsel), aber nicht den des Boards. Das reicht: Beim DE10-Nano
//    nutzt erst U-Boot die Werte nach einem Board-Neustart.
//  - DDR-Fenster der Cores (0x20000000–0x3FFFFFFF, fpga_mem(); Scaler-Puffer,
//    Core-Speicher): seit P3 physisch 0xA0000000–0xBFFFFFFF (reserviert per
//    U-Boot, linux/boot/retro25-bootscr.sh). Dieselbe Umrechnung wie im FPGA
//    (sys/de25/sysmem_de25.v): Bits 31..29 = 101. Abgebildet über /dev/mem
//    mit O_SYNC wie im Original; F2SDRAM ist ohnehin kohärent (P3 Schritt 1).
//  Alles andere liefert 0 — die Aufrufer prüfen das und melden einen Fehler.

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>

#include "shmem.h"

#define PARAM_ADDR 0x1FFFF000
#define PARAM_SIZE 0x1000
#define PARAM_FILE "/dev/shm/retro25_param"

#define WIN_ADDR   0x20000000u         // MiSTer-Sicht
#define WIN_SIZE   0x20000000u
#define WIN_PHYS   0xA0000000ull       // physisch (DE25)

static int memfd = -1;

void *shmem_map(uint32_t address, uint32_t size)
{
	if (address >= PARAM_ADDR && address + (uint64_t)size <= PARAM_ADDR + PARAM_SIZE)
	{
		int fd = open(PARAM_FILE, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
		if (fd < 0)
		{
			printf("Error: Unable to open %s: %s\n", PARAM_FILE, strerror(errno));
			return 0;
		}
		if (ftruncate(fd, PARAM_SIZE) < 0)
		{
			close(fd);
			return 0;
		}
		// mmap braucht eine seitenausgerichtete Position: ganze Seite abbilden
		uint8_t *page = (uint8_t *)mmap(0, PARAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		close(fd);
		if (page == MAP_FAILED) return 0;
		if (address != PARAM_ADDR)
		{
			printf("Error: shmem_map(0x%X) inside the parameter page is not supported\n", address);
			munmap(page, PARAM_SIZE);
			return 0;
		}
		return page;
	}

	if (address >= WIN_ADDR && address + (uint64_t)size <= WIN_ADDR + (uint64_t)WIN_SIZE)
	{
		if (memfd < 0)
		{
			memfd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
			if (memfd == -1)
			{
				printf("Error: Unable to open /dev/mem!\n");
				return 0;
			}
		}
		// mmap braucht eine seitenausgerichtete Position: ab Seitenanfang
		// abbilden und den Versatz aufschlagen (z. B. x86_share 0x300CE004);
		// shmem_unmap rechnet ihn wieder heraus
		off_t phys = (off_t)(WIN_PHYS + (address - WIN_ADDR));
		size_t pg = (size_t)sysconf(_SC_PAGESIZE);
		size_t lead = (size_t)phys & (pg - 1);
		uint8_t *res = (uint8_t *)mmap(0, size + lead, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, phys - lead);
		if (res == MAP_FAILED)
		{
			printf("Error: Unable to mmap (0x%X -> 0x%llX, %u): %s\n", address,
				(unsigned long long)phys, size, strerror(errno));
			return 0;
		}
		return res + lead;
	}

	printf("shmem_map(0x%X, 0x%X): Adresse außerhalb des DE25-Fensters\n", address, size);
	return 0;
}

int shmem_unmap(void* map, uint32_t size)
{
	// Gegenstück zu shmem_map: Versatz innerhalb der Seite herausrechnen
	size_t pg = (size_t)sysconf(_SC_PAGESIZE);
	size_t lead = (uintptr_t)map & (pg - 1);
	map = (uint8_t *)map - lead;
	size += lead;
	if (munmap(map, size) < 0)
	{
		printf("Error: Unable to unmap(%p, %u)!\n", map, size);
		return 0;
	}

	return 1;
}

// Kopieren in/aus dem DDR-Fenster. /dev/mem bildet es (reserved, no-map, mit
// CONFIG_STRICT_DEVMEM) als Device-Speicher ab: Dort sind nicht ausgerichtete
// Zugriffe und DC ZVA (memset) verboten — memcpy/memset lösen SIGBUS aus.
// Daher volatile, je Zugriff ausgerichtet: Bytes bis zur 8-Byte-Grenze, dann
// 64-bit-Wörter, Rest wieder Bytes. (Die Parameterseite ist eine normale Datei,
// dort schadet das nicht.)
static void dev_copy_to(volatile uint8_t *dst, const uint8_t *src, uint32_t n)
{
	while (n && ((uintptr_t)dst & 7)) { *dst++ = *src++; n--; }
	volatile uint64_t *d64 = (volatile uint64_t *)dst;
	while (n >= 8)
	{
		uint64_t v;
		memcpy(&v, src, 8);            // Quelle ist normaler Speicher
		*d64++ = v;
		src += 8;
		n -= 8;
	}
	dst = (volatile uint8_t *)d64;
	while (n--) *dst++ = *src++;
}

static void dev_copy_from(uint8_t *dst, const volatile uint8_t *src, uint32_t n)
{
	while (n && ((uintptr_t)src & 7)) { *dst++ = *src++; n--; }
	const volatile uint64_t *s64 = (const volatile uint64_t *)src;
	while (n >= 8)
	{
		uint64_t v = *s64++;
		memcpy(dst, &v, 8);            // Ziel ist normaler Speicher
		dst += 8;
		n -= 8;
	}
	src = (const volatile uint8_t *)s64;
	while (n--) *dst++ = *src++;
}

int shmem_put(uint32_t address, uint32_t size, void *buf)
{
	void *shmem = shmem_map(address, size);
	if (shmem)
	{
		dev_copy_to((volatile uint8_t *)shmem, (const uint8_t *)buf, size);
		shmem_unmap(shmem, size);
	}

	return shmem != 0;
}

int shmem_get(uint32_t address, uint32_t size, void *buf)
{
	void *shmem = shmem_map(address, size);
	if (shmem)
	{
		dev_copy_from((uint8_t *)buf, (const volatile uint8_t *)shmem, size);
		shmem_unmap(shmem, size);
	}

	return shmem != 0;
}
