// SPDX-License-Identifier: GPL-3.0-or-later
// pll_fit.h (DE25) — ganzzahlige HDMI-PLL des Agilex 5, siehe pll_fit.cpp.
#ifndef PLL_FIT_H
#define PLL_FIT_H

#include <stdint.h>

// beste Einstellung Fpix = 50 MHz * M / (N * C) für Fout (MHz);
// false = kein gültiger Wert im Bereich
bool pll_fit_search(double Fout, uint32_t *n, uint32_t *m, uint32_t *c);

// Pixeltakt einer Einstellung (MHz)
double pll_fit_freq(uint32_t n, uint32_t m, uint32_t c);

// Zeilenlänge und Zeilenzahl für vsync_adjust anpassen: sucht dh (hfp) und
// dv (vfp), mit denen ein erreichbarer Pixeltakt die Bildrate des Cores
// (vtime: Bilddauer in Takten zu 100 MHz) am besten trifft.
// htotal/vtotal: bisherige Summen; hfp/vfp: bisherige Front-Porches (dürfen
// nicht unter 1 fallen). Ergebnis: *dh, *dv, *ppm (Restabweichung der PLL).
bool pll_fit_totals(int htotal, int vtotal, int hfp, int vfp, uint32_t vtime,
                    int *dh, int *dv, double *ppm);

#endif
