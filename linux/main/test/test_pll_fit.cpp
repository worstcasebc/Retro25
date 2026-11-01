// SPDX-License-Identifier: GPL-3.0-or-later
// test_pll_fit — Selbsttest für linux/main/de25/pll_fit.cpp (ohne Board).
//
// Aufruf (Container retro25-arm64 oder jeder Rechner mit g++):
//     g++ -O2 -I linux/main/de25 linux/main/test/test_pll_fit.cpp
//         linux/main/de25/pll_fit.cpp -o /tmp/t && /tmp/t   (eine Zeile)
// Prüft: (1) bekannte PLL-Einstellungen (74,25 / 148,5 MHz exakt, Grenzen),
// (2) pll_fit_totals für die Bildraten unserer Cores in 720p/1080p: Rest
// < 2 ppm, Änderungen im erlaubten Bereich, und die Bildrate mit den neuen
// Summen und dem erreichbaren Takt weicht < 2 ppm von der des Cores ab.
// Ausgabe "PASS: test_pll_fit" oder FAIL-Zeilen.

#include <math.h>
#include <stdio.h>
#include "pll_fit.h"

static int errors = 0;

static void check(bool ok, const char *what)
{
	if (!ok) { printf("FAIL: %s\n", what); errors++; }
}

int main()
{
	uint32_t n, m, c;
	// 74,25 MHz (720p60) und 148,5 MHz (1080p60) sind exakt erreichbar
	check(pll_fit_search(74.25, &n, &m, &c) && fabs(pll_fit_freq(n, m, c) - 74.25) < 1e-9, "74.25 exakt");
	check(pll_fit_search(148.5, &n, &m, &c) && fabs(pll_fit_freq(n, m, c) - 148.5) < 1e-9, "148.5 exakt");
	check(50.0 * m / n >= 600.0 && 50.0 * m / n <= 3200.0 && m <= 320 && c <= 510 && n <= 5, "Grenzen");
	check(!pll_fit_search(0.5, &n, &m, &c), "0,5 MHz unerreichbar");

	struct { const char *core; double hz; } cores[] = {
		{ "MegaDrive NTSC", 59.9227 }, { "NES/SNES NTSC", 60.0988 },
		{ "C64 PAL", 50.1246 },        { "z486 VGA 70 Hz", 70.086 },
		{ "60 Hz", 60.0 },
	};
	struct { const char *name; int H, V, hfp, vfp; } modes[] = {
		{ "720p", 1650, 750, 110, 5 }, { "1080p", 2200, 1125, 88, 4 },
	};
	for (auto &cr : cores)
		for (auto &md : modes)
		{
			uint32_t vtime = (uint32_t)(100000000.0 / cr.hz + 0.5);
			int dh, dv;
			double ppm;
			char what[128];
			bool ok = pll_fit_totals(md.H, md.V, md.hfp, md.vfp, vtime, &dh, &dv, &ppm);
			snprintf(what, sizeof(what), "%s %s gefunden", cr.core, md.name);
			check(ok, what);
			if (!ok) continue;
			// Bildrate aus neuen Summen und dem tatsächlich erreichbaren Takt
			double F = 100.0 * (md.H + dh) * (md.V + dv) / vtime;
			pll_fit_search(F, &n, &m, &c);
			double hz = pll_fit_freq(n, m, c) * 1e6 / ((md.H + dh) * (double)(md.V + dv));
			double err = (hz - 1e8 / vtime) / (1e8 / vtime) * 1e6;
			printf("%-16s %-6s htotal %+3d vtotal %+2d  PLL %5.2f ppm  Bildrate %+6.2f ppm\n",
				cr.core, md.name, dh, dv, ppm, err);
			snprintf(what, sizeof(what), "%s %s Rest %.2f ppm", cr.core, md.name, ppm);
			check(ppm < 2.0 && fabs(err) < 2.0, what);
			check(dh % 2 == 0 && dh >= -24 && dh <= 24 && dv >= -4 && dv <= 8, "Bereich dh/dv");
			check(md.hfp + dh >= 1 && md.vfp + dv >= 1, "Porch >= 1");
		}
	// 60,00 Hz in 720p: kein Eingriff nötig (74,25 MHz exakt) -> dh = dv = 0
	{
		int dh, dv; double ppm;
		pll_fit_totals(1650, 750, 110, 5, 1666667, &dh, &dv, &ppm);
		check(dh == 0, "60 Hz 720p ohne hfp-Änderung");
	}
	if (!errors) printf("PASS: test_pll_fit\n");
	return errors ? 1 : 0;
}
