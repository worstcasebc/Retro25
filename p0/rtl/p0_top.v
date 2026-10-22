// SPDX-License-Identifier: GPL-3.0-or-later
// p0_top — Top-Level des P0-Versuchs „Core-Wechsel aus Linux“.
//
// Zweck:  Drei Mini-Cores, die Linux im HPS-first-Betrieb abwechselnd ins
//         FPGA lädt. Alle drei haben dieselben Pins und dasselbe HPS-System
//         (qsys_top aus dem C64-Projekt, mit den Brücken c64_m0 und disk_m0);
//         sie unterscheiden sich nur in der Logik — und Variante C zusätzlich
//         in einer PLL. Die Revision im Quartus-Projekt setzt genau eines der
//         Makros P0_VARIANT_A, P0_VARIANT_B, P0_VARIANT_C.
//           A   LEDR[3:0] Lauflicht (clk_100), ID "R25A"
//           B   LEDR[3:0] blinken gemeinsam mit 2 Hz (clk_100), ID "R25B"
//           C   LEDR[3:0] zählen binär, Takt aus eigener PLL pll_c64
//               (31,5 MHz aus CLOCK0_50), ID "R25C"
//           LEDR[7]   Herzschlag 1 Hz: A/B direkt aus CLOCK0_50, C aus der
//                     PLL — so ist CLOCK0_50 in allen Varianten benutzt
//           LEDR[6:4] aus
//         Linux liest über die LW-Bridge (Basis 0x2000_0000):
//           0x2001_0100  p0_regs an c64_m0: ID, SCRATCH, UPTIME, STATUS
//           0x2001_4000  p0_regs an disk_m0 (ID "R25-"), damit Lesezugriffe
//                        dort nicht hängen bleiben
// Takte:  clk_100 = 100 MHz aus pll (GHRD, an CLOCK2_50) für Brücke und
//         Register; in C zusätzlich clk_c = 31,5 MHz aus pll_c64.
// Reset:  ninit_done aus dem HPS-System, je Taktdomäne synchronisiert.
//         Die LEDs sind low-aktiv.

`default_nettype none

module p0_top (
    input  wire        CLOCK0_50,
    input  wire        CLOCK2_50,
    input  wire [1:0]  KEY,
    input  wire [3:0]  SW,
    output wire [7:0]  LEDR,

    // Speicher des HPS (läuft über Pins des FPGA)
    input  wire        LPDDR4A_REFCLK_p,
    output wire        LPDDR4A_CS_n,
    output wire [5:0]  LPDDR4A_CA,
    output wire        LPDDR4A_CK,
    output wire        LPDDR4A_CKE,
    output wire        LPDDR4A_CK_n,
    inout  wire [3:0]  LPDDR4A_DM,
    inout  wire [31:0] LPDDR4A_DQ,
    inout  wire [3:0]  LPDDR4A_DQS,
    inout  wire [3:0]  LPDDR4A_DQS_n,
    output wire        LPDDR4A_RESET_n,
    input  wire        LPDDR4A_RZQ,

    // Anschlüsse des HPS: Netzwerk, SD-Karte, UART, USB, I2C, Taster, LED
    input  wire        HPS_CLK_25,
    output wire        HPS_ENET_MDC,
    inout  wire        HPS_ENET_MDIO,
    input  wire        HPS_ENET_RX_CLK,
    input  wire        HPS_ENET_RX_CTL,
    input  wire [3:0]  HPS_ENET_RX_DATA,
    output wire        HPS_ENET_TX_CLK,
    output wire        HPS_ENET_TX_CTL,
    output wire [3:0]  HPS_ENET_TX_DATA,
    inout  wire        HPS_GSENSOR_I2C_EN,
    inout  wire        HPS_GSENSOR_INT,
    inout  wire        HPS_I2C_SCL,
    inout  wire        HPS_I2C_SDA,
    inout  wire        HPS_KEY,
    inout  wire        HPS_LED,
    output wire        HPS_SD_CLK,
    inout  wire        HPS_SD_CMD,
    inout  wire [3:0]  HPS_SD_DATA,
    input  wire        HPS_UART_RX,
    output wire        HPS_UART_TX,
    input  wire        HPS_USB_CLK,
    inout  wire [7:0]  HPS_USB_DATA,
    input  wire        HPS_USB_DIR,
    input  wire        HPS_USB_NXT,
    output wire        HPS_USB_STP
);

`ifdef P0_VARIANT_A
    localparam [31:0] CORE_ID = 32'h5232_3541;   // "R25A"
`elsif P0_VARIANT_B
    localparam [31:0] CORE_ID = 32'h5232_3542;   // "R25B"
`elsif P0_VARIANT_C
    localparam [31:0] CORE_ID = 32'h5232_3543;   // "R25C"
`else
    // Ohne Makro bricht die Übersetzung hier bewusst ab.
    P0_VARIANT_fehlt_in_der_Revision missing_variant ();
`endif

    // --- Takte und Reset ----------------------------------------------------
    wire ninit_done;
    wire clk_100;

    pll u_pll_hps (
        .refclk   (CLOCK2_50),
        .locked   (),
        .rst      (ninit_done),
        .outclk_0 (clk_100)
    );

    wire rst_av;

    sync_2ff u_sync_rst_av (
        .clk      (clk_100),
        .d_async  (ninit_done),
        .d_sync_q (rst_av)
    );

    // --- LEDs der Varianten (1 = an) ---------------------------------------
    reg  [3:0] pattern_q;
    wire       heartbeat;

`ifdef P0_VARIANT_C
    wire clk_c;
    wire pll_c_locked;

    pll_c64 u_pll_c64 (
        .refclk   (CLOCK0_50),
        .rst      (ninit_done),
        .outclk_0 (clk_c),
        .outclk_1 (),
        .locked   (pll_c_locked)
    );

    wire rst_c_n;

    sync_2ff u_sync_rst_c (
        .clk      (clk_c),
        .d_async  (pll_c_locked & ~ninit_done),
        .d_sync_q (rst_c_n)
    );

    // Zähler: 31,5 MHz / 2^23 = 3,75 Schritte pro Sekunde
    reg [26:0] count_c_q;

    always @(posedge clk_c) begin
        if (!rst_c_n) count_c_q <= 27'd0;
        else          count_c_q <= count_c_q + 27'd1;
    end

    always @(posedge clk_c) pattern_q <= count_c_q[26:23];
    assign heartbeat = count_c_q[24];   // 31,5 MHz / 2^25 ≈ 0,94 Hz
`else
    // Herzschlag direkt aus CLOCK0_50: 50 MHz / 2^26 ≈ 0,75 Hz
    reg [25:0] count_50_q = 26'd0;

    always @(posedge CLOCK0_50) count_50_q <= count_50_q + 26'd1;
    assign heartbeat = count_50_q[25];

    reg [24:0] tick_q;      // 100 MHz / 25 000 000 = 4 Schritte pro Sekunde

    always @(posedge clk_100) begin
        if (rst_av) begin
            tick_q    <= 25'd0;
            pattern_q <= 4'b0001;
        end else if (tick_q == 25'd24_999_999) begin
            tick_q <= 25'd0;
    `ifdef P0_VARIANT_A
            pattern_q <= {pattern_q[2:0], pattern_q[3]};   // Lauflicht, 4 Schritte/s
    `else
            pattern_q <= (pattern_q == 4'b1111) ? 4'b0000 : 4'b1111;  // 2 Hz
    `endif
        end else begin
            tick_q <= tick_q + 25'd1;
        end
    end
`endif

    assign LEDR = ~{heartbeat, 3'b000, pattern_q};   // low-aktiv

    // --- Register an den Brücken ------------------------------------------
    wire [1:0] key_q;
    wire [3:0] sw_q;

    sync_2ff #(.WIDTH(6)) u_sync_in (
        .clk      (clk_100),
        .d_async  ({~KEY, SW}),
        .d_sync_q ({key_q, sw_q})
    );

    wire [31:0] status = {24'd0, 2'b00, key_q, sw_q};

    wire [3:0]  c64_m0_address;
    wire        c64_m0_write;
    wire [31:0] c64_m0_writedata;
    wire [3:0]  c64_m0_byteenable;
    wire        c64_m0_read;
    wire [31:0] c64_m0_readdata;
    wire        c64_m0_readdatavalid;
    wire        c64_m0_waitrequest;

    p0_regs #(.ID(CORE_ID)) u_regs (
        .clk               (clk_100),
        .rst               (rst_av),
        .avs_address       (c64_m0_address[3:2]),
        .avs_write         (c64_m0_write),
        .avs_writedata     (c64_m0_writedata),
        .avs_byteenable    (c64_m0_byteenable),
        .avs_read          (c64_m0_read),
        .avs_readdata      (c64_m0_readdata),
        .avs_readdatavalid (c64_m0_readdatavalid),
        .avs_waitrequest   (c64_m0_waitrequest),
        .status            (status)
    );

    wire [13:0] disk_m0_address;
    wire        disk_m0_write;
    wire [31:0] disk_m0_writedata;
    wire [3:0]  disk_m0_byteenable;
    wire        disk_m0_read;
    wire [31:0] disk_m0_readdata;
    wire        disk_m0_readdatavalid;
    wire        disk_m0_waitrequest;

    p0_regs #(.ID(32'h5232_352D)) u_regs_disk (   // "R25-"
        .clk               (clk_100),
        .rst               (rst_av),
        .avs_address       (disk_m0_address[3:2]),
        .avs_write         (disk_m0_write),
        .avs_writedata     (disk_m0_writedata),
        .avs_byteenable    (disk_m0_byteenable),
        .avs_read          (disk_m0_read),
        .avs_readdata      (disk_m0_readdata),
        .avs_readdatavalid (disk_m0_readdatavalid),
        .avs_waitrequest   (disk_m0_waitrequest),
        .status            (status)
    );

    // --- HPS-System (wie im C64-Projekt, quartus_hps) ------------------------
    wire [2:0] hps_led;

    qsys_top u_qsys_top (
        .disk_m0_waitrequest                   (disk_m0_waitrequest),
        .disk_m0_readdata                      (disk_m0_readdata),
        .disk_m0_readdatavalid                 (disk_m0_readdatavalid),
        .disk_m0_burstcount                    (),
        .disk_m0_writedata                     (disk_m0_writedata),
        .disk_m0_address                       (disk_m0_address),
        .disk_m0_write                         (disk_m0_write),
        .disk_m0_read                          (disk_m0_read),
        .disk_m0_byteenable                    (disk_m0_byteenable),
        .disk_m0_debugaccess                   (),
        .c64_m0_waitrequest                    (c64_m0_waitrequest),
        .c64_m0_readdata                       (c64_m0_readdata),
        .c64_m0_readdatavalid                  (c64_m0_readdatavalid),
        .c64_m0_burstcount                     (),
        .c64_m0_writedata                      (c64_m0_writedata),
        .c64_m0_address                        (c64_m0_address),
        .c64_m0_write                          (c64_m0_write),
        .c64_m0_read                           (c64_m0_read),
        .c64_m0_byteenable                     (c64_m0_byteenable),
        .c64_m0_debugaccess                    (),

        .clk_100_clk                           (clk_100),
        .reset_reset_n                         (~ninit_done),
        .ninit_done_ninit_done                 (ninit_done),
        .led_pio_external_connection_in_port   (hps_led),
        .led_pio_external_connection_out_port  (hps_led),
        .dipsw_pio_external_connection_export  (4'b0000),
        .button_pio_external_connection_export (4'b1111),

        .hps_io_hps_osc_clk                    (HPS_CLK_25),
        .emif_hps_emif_mem_0_mem_cs            (LPDDR4A_CS_n),
        .emif_hps_emif_mem_0_mem_ca            (LPDDR4A_CA),
        .emif_hps_emif_mem_0_mem_cke           (LPDDR4A_CKE),
        .emif_hps_emif_mem_0_mem_dq            (LPDDR4A_DQ),
        .emif_hps_emif_mem_0_mem_dqs_t         (LPDDR4A_DQS),
        .emif_hps_emif_mem_0_mem_dqs_c         (LPDDR4A_DQS_n),
        .emif_hps_emif_mem_0_mem_dmi           (LPDDR4A_DM),
        .emif_hps_emif_mem_ck_0_mem_ck_t       (LPDDR4A_CK),
        .emif_hps_emif_mem_ck_0_mem_ck_c       (LPDDR4A_CK_n),
        .emif_hps_emif_mem_reset_n_mem_reset_n (LPDDR4A_RESET_n),
        .emif_hps_emif_oct_0_oct_rzqin         (LPDDR4A_RZQ),
        .emif_hps_emif_ref_clk_0_clk           (LPDDR4A_REFCLK_p),
        .hps_io_emac0_tx_clk                   (HPS_ENET_TX_CLK),
        .hps_io_emac0_rx_clk                   (HPS_ENET_RX_CLK),
        .hps_io_emac0_tx_ctl                   (HPS_ENET_TX_CTL),
        .hps_io_emac0_rx_ctl                   (HPS_ENET_RX_CTL),
        .hps_io_emac0_txd0                     (HPS_ENET_TX_DATA[0]),
        .hps_io_emac0_txd1                     (HPS_ENET_TX_DATA[1]),
        .hps_io_emac0_txd2                     (HPS_ENET_TX_DATA[2]),
        .hps_io_emac0_txd3                     (HPS_ENET_TX_DATA[3]),
        .hps_io_emac0_rxd0                     (HPS_ENET_RX_DATA[0]),
        .hps_io_emac0_rxd1                     (HPS_ENET_RX_DATA[1]),
        .hps_io_emac0_rxd2                     (HPS_ENET_RX_DATA[2]),
        .hps_io_emac0_rxd3                     (HPS_ENET_RX_DATA[3]),
        .hps_io_mdio0_mdio                     (HPS_ENET_MDIO),
        .hps_io_mdio0_mdc                      (HPS_ENET_MDC),
        .hps_io_sdmmc_cclk                     (HPS_SD_CLK),
        .hps_io_sdmmc_cmd                      (HPS_SD_CMD),
        .hps_io_sdmmc_data0                    (HPS_SD_DATA[0]),
        .hps_io_sdmmc_data1                    (HPS_SD_DATA[1]),
        .hps_io_sdmmc_data2                    (HPS_SD_DATA[2]),
        .hps_io_sdmmc_data3                    (HPS_SD_DATA[3]),
        .hps_io_uart1_rx                       (HPS_UART_RX),
        .hps_io_uart1_tx                       (HPS_UART_TX),
        .hps_io_usb0_clk                       (HPS_USB_CLK),
        .hps_io_usb0_stp                       (HPS_USB_STP),
        .hps_io_usb0_dir                       (HPS_USB_DIR),
        .hps_io_usb0_nxt                       (HPS_USB_NXT),
        .hps_io_usb0_data0                     (HPS_USB_DATA[0]),
        .hps_io_usb0_data1                     (HPS_USB_DATA[1]),
        .hps_io_usb0_data2                     (HPS_USB_DATA[2]),
        .hps_io_usb0_data3                     (HPS_USB_DATA[3]),
        .hps_io_usb0_data4                     (HPS_USB_DATA[4]),
        .hps_io_usb0_data5                     (HPS_USB_DATA[5]),
        .hps_io_usb0_data6                     (HPS_USB_DATA[6]),
        .hps_io_usb0_data7                     (HPS_USB_DATA[7]),
        .hps_io_i2c1_sda                       (HPS_I2C_SDA),
        .hps_io_i2c1_scl                       (HPS_I2C_SCL),
        .hps_io_gpio28                         (HPS_GSENSOR_INT),
        .hps_io_gpio34                         (HPS_GSENSOR_I2C_EN),
        .hps_io_gpio40                         (HPS_KEY),
        .hps_io_gpio41                         (HPS_LED)
    );

endmodule

`default_nettype wire
