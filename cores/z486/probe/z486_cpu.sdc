# Ziel wie upstream (Profil production): 85 MHz
create_clock -name clk -period 11.765 [get_ports clk]
derive_clock_uncertainty
