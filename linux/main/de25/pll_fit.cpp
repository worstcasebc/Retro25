// SPDX-License-Identifier: GPL-3.0-or-later
// pll_fit.cpp (DE25) — Rechnungen für die ganzzahlige HDMI-PLL.
//
// Die HDMI-PLL des Agilex 5 (HVIO-IOPLL) teilt nur ganzzahlig:
// Fpix = 50 MHz * M / (N * C). Grenzen laut Agilex-5-Datenblatt und
// Clocking-Handbuch: PFD 10..325 MHz (N 1..5 bei 50 MHz), VCO 600..3200 MHz,
// M bis 320 (Ladungspumpen-Tabelle), C bis 510 (je 8 bit high/low).
// MiSTer (Cyclone V) hat einen fraktionalen Teiler und trifft jeden Takt.
//
// vsync_adjust: Main passt den HDMI-Pixeltakt an die Bildrate des Cores an.
// Die ganzzahlige PLL allein trifft ihn nur auf 30..170 ppm — ein doppeltes
// oder fehlendes Bild alle paar Minuten (Mega Drive 1080p: +166 ppm, etwa
// alle 100 s). pll_fit_totals verändert deshalb zusätzlich die Zeilenlänge
// (hfp, in Schritten von 2) und die Zeilenzahl (vfp) ein wenig und nimmt die
// Kombination, deren erreichbarer Takt am besten passt (meist < 1 ppm).
// Unter fast gleich guten (Abstand < 0,2 ppm) gewinnt die kleinste Änderung,
// eine Pixelspalte zählt dabei 16-mal so viel wie eine Zeile (vfp ändert
// MiSTer selbst auch, hfp ist ungewöhnlicher).
// Test: linux/main/test/test_pll_fit.cpp

#include <math.h>
#include <stdlib.h>
#include "pll_fit.h"

bool pll_fit_search(double Fout, uint32_t *pn, uint32_t *pm, uint32_t *pc)
{
	uint32_t best_n = 1, best_m = 0, best_c = 0;
	double best_err = 1e9;
	for (uint32_t n = 1; n <= 5; n++)
	{
		for (uint32_t m = 1; m <= 320; m++)
		{
			double fvco = 50.0 * m / n;
			if (fvco < 600.0 || fvco > 3200.0) continue;
			uint32_t c = (uint32_t)(fvco / Fout + 0.5);
			if (c < 2 || c > 510) continue;
			double err = fabs(fvco / c - Fout);
			// gleiche Abweichung: höherer VCO (weniger Jitter), N bleibt klein
			bool better = (err < best_err - 1e-9) ||
				(err < best_err + 1e-9 && n == best_n && m > best_m);
			if (better)
			{
				best_err = err;
				best_n = n; best_m = m; best_c = c;
			}
		}
	}
	*pn = best_n; *pm = best_m; *pc = best_c;
	return best_m != 0;
}

double pll_fit_freq(uint32_t n, uint32_t m, uint32_t c)
{
	return 50.0 * m / n / c;
}

bool pll_fit_totals(int H, int V, int hfp, int vfp, uint32_t vtime,
                    int *pdh, int *pdv, double *pppm)
{
	struct cand_t { int dh, dv; double ppm; } cand[25 * 13];
	int nc = 0;
	double min_ppm = 1e9;
	const double frame = vtime / 100000000.0;   // Sekunden je Bild des Cores
	if (!vtime) return false;

	// 1. alle Kombinationen bewerten
	for (int dh = -24; dh <= 24; dh += 2)
	{
		if (hfp + dh < 1) continue;
		for (int dv = -4; dv <= 8; dv++)
		{
			if (vfp + dv < 1) continue;
			double F = (H + dh) * (double)(V + dv) / frame / 1000000.0;
			uint32_t n, m, c;
			if (F < 2.0 || F > 300.0 || !pll_fit_search(F, &n, &m, &c)) continue;
			double ppm = fabs(pll_fit_freq(n, m, c) - F) / F * 1000000.0;
			cand[nc++] = { dh, dv, ppm };
			if (ppm < min_ppm) min_ppm = ppm;
		}
	}
	if (!nc) return false;

	// 2. unter den fast besten die kleinste Änderung
	int best = 0, best_cost = 1 << 30;
	for (int i = 0; i < nc; i++)
	{
		int cost = abs(cand[i].dh) * 16 + abs(cand[i].dv);
		if (cand[i].ppm <= min_ppm + 0.2 && cost < best_cost)
		{
			best = i; best_cost = cost;
		}
	}
	*pdh = cand[best].dh;
	*pdv = cand[best].dv;
	*pppm = cand[best].ppm;
	return true;
}
