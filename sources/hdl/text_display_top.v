module text_display_top (
    input wire clk_in,
    input wire rst_in,
    input wire up_in,
    input wire down_in,
    input wire left_in,
    input wire right_in,
    input wire center_in,
    input wire keyboard_en,
    input wire ps2_clk,
    input wire ps2_data,
    output wire vga_hsync_o,
    output wire vga_vsync_o,
    output wire [11:0] vga_color_o // [4'bRED, 4'bGREEN, 4'bBLUE] 
);

/* Create required clocks */
wire clk_100mhz, clk_25mhz, clk_75mhz, locked;
clk_generator clocks (
    .clk_100mhz(clk_100mhz),
    .clk_25mhz(clk_25mhz),
    .clk_75mhz(clk_75mhz),
    .reset(1'b0),
    .locked(locked),
    .clk_in1(clk_in)
);

/* Debounce and synchronize buttons */
wire rst_sync, up_sync, down_sync, left_sync, right_sync, center_sync, keyboard_en_sync;
debouncer #(.CLK_FREQ(75_000_000)) reset_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(rst_in), .btn_out(rst_sync));
debouncer #(.CLK_FREQ(75_000_000)) up_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(up_in), .btn_out(up_sync));
debouncer #(.CLK_FREQ(75_000_000)) down_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(down_in), .btn_out(down_sync));
debouncer #(.CLK_FREQ(75_000_000)) left_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(left_in), .btn_out(left_sync));
debouncer #(.CLK_FREQ(75_000_000)) right_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(right_in), .btn_out(right_sync));
debouncer #(.CLK_FREQ(75_000_000)) center_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(center_in), .btn_out(center_sync));
debouncer #(.CLK_FREQ(75_000_000)) keyboard_en_debouncer 
    (.clk(clk_75mhz), .rst(1'b0), .btn_in(keyboard_en), .btn_out(keyboard_en_sync));

/* Instantiate VGA core (1280x720 @60Hz) */
reg [11:0] vga_color_in;
wire [15:0] vga_x_coord, vga_y_coord;
vga_core vga (
    .clk(clk_75mhz),
    .rst(rst_sync),
    .color_in(vga_color_in),
    .hsync(vga_hsync_o),
    .vsync(vga_vsync_o),
    .color_o(vga_color_o),
    .x_coord(vga_x_coord),
    .y_coord(vga_y_coord)
);

/* Instantiate PS2 Receiver */
wire ps2_rx_done;
wire [7:0] ps2_rx_data;
ps2_scanner PS2Recv (
    .clk(clk_75mhz),
    .rst(rst_sync),
    .ps2_clk(ps2_clk),
    .ps2_data(ps2_data),
    .rx_done(ps2_rx_done),
    .rx_data_o(ps2_rx_data)
);

/* Instantiate ASCII BRAM (8x16 pixels) */
wire [11:0] ascii_bram_addr;
wire [7:0] ascii_bram_row_out;
ascii_bram asciiBRAM (
    .clk(clk_75mhz),
    .addr(ascii_bram_addr),
    .data(ascii_bram_row_out)
);

/* Instantiate Display Tile BRAM */
localparam integer DISP_WIDTH = 1280;
localparam integer DISP_HEIGHT = 720;
localparam integer TILE_WIDTH = 8;
localparam integer TILE_HEIGHT = 16;
localparam integer NUM_TILES = (DISP_WIDTH*DISP_HEIGHT) / (TILE_WIDTH*TILE_HEIGHT);
localparam integer ASCII_BITS = 8;
localparam integer TILE_ADDR_WIDTH = $clog2(NUM_TILES + 1) + 1;
reg tile_bram_we;
wire [TILE_ADDR_WIDTH-1 : 0] tile_bram_addr_a, tile_bram_addr_b;
wire [ASCII_BITS-1 : 0] tile_bram_data_out_a, tile_bram_data_out_b;
reg [ASCII_BITS-1 : 0] tile_bram_data_in_a;
display_tile_bram #(
    .DATA_WIDTH(ASCII_BITS),
    .ADDR_WIDTH(TILE_ADDR_WIDTH)
) tileBRAM (
    .clk(clk_75mhz),
    .write_enable(tile_bram_we),
    .addr_a(tile_bram_addr_a),
    .addr_b(tile_bram_addr_b),
    .data_in_a(tile_bram_data_in_a),
    .data_out_a(tile_bram_data_out_a),
    .data_out_b(tile_bram_data_out_b)
);

// Pixel -> Tile Addressing
wire [TILE_ADDR_WIDTH-1 : 0] pixel_tile_addr;
assign pixel_tile_addr = {vga_y_coord[9:4], vga_x_coord[10:3]};

// Cursor -> Tile Addressing
wire [TILE_ADDR_WIDTH-1 : 0] cursor_tile_addr;
reg [15:0] cursor_x, cursor_y;
assign cursor_tile_addr = {cursor_y[9:4], cursor_x[10:3]};

// Rising edge detectors for debounced buttons
wire up_pulse, down_pulse, left_pulse, right_pulse, center_pulse;
posedge_detector edgeUP (.clk(clk_75mhz), .signal(up_sync), .edge_pulse(up_pulse));
posedge_detector edgeDOWN (.clk(clk_75mhz), .signal(down_sync), .edge_pulse(down_pulse));
posedge_detector edgeLEFT (.clk(clk_75mhz), .signal(left_sync), .edge_pulse(left_pulse));
posedge_detector edgeRIGHT (.clk(clk_75mhz), .signal(right_sync), .edge_pulse(right_pulse));
posedge_detector edgeCENTER (.clk(clk_75mhz), .signal(center_sync), .edge_pulse(center_pulse));

// PS2 Ignore Key Release
reg ps2_ignore_next;
always @(posedge clk_75mhz, posedge rst_sync) begin
    if(rst_sync) begin
        ps2_ignore_next <= 0;
    end else begin
        if(ps2_rx_done) begin
            if(ps2_rx_data == 8'hF0) begin
                ps2_ignore_next <= 1;
            end else begin
                ps2_ignore_next <= 0;
            end
        end
    end
end

// Handle cursor position update
always @(posedge clk_75mhz, posedge rst_sync) begin
    if(rst_sync) begin
        cursor_x <= 0;
        cursor_y <= 0;
    end else begin
        if(keyboard_en_sync) begin
            if(ps2_rx_done && !ps2_ignore_next) begin
                case(ps2_rx_data)
                    8'h75: if(cursor_y >= TILE_HEIGHT) // up arrow
                            cursor_y <= cursor_y - TILE_HEIGHT;
                    8'h72: if(cursor_y <= (DISP_HEIGHT-1) - TILE_HEIGHT) // down arrow
                            cursor_y <= cursor_y + TILE_HEIGHT;
                    8'h6B: if(cursor_x >= TILE_WIDTH) // left arrow
                            cursor_x <= cursor_x - TILE_WIDTH;
                    8'h74,8'h29,8'h1C,8'h32,8'h21,8'h23,
                    8'h24,8'h2b,8'h34,8'h33,8'h43,8'h3b,
                    8'h42,8'h4b,8'h3a,8'h31,8'h44,8'h4d,
                    8'h15,8'h2d,8'h1b,8'h2c,8'h3c,8'h2a,
                    8'h1d,8'h22,8'h35,8'h1a: 
                        if(cursor_x <= (DISP_WIDTH-1) - TILE_WIDTH) // right arrow
                            cursor_x <= cursor_x + TILE_WIDTH;
                    8'h5a: begin // enter pressed
                                cursor_x <= 0;
                                if(cursor_y <= (DISP_HEIGHT-1) - TILE_HEIGHT)
                                    cursor_y <= cursor_y + TILE_HEIGHT;
                            end
                endcase
            end
        end else begin
            case({up_pulse, down_pulse, left_pulse, right_pulse, center_pulse})
                5'b10000: if(cursor_y >= TILE_HEIGHT)
                            cursor_y <= cursor_y - TILE_HEIGHT;
                5'b01000: if(cursor_y <= (DISP_HEIGHT-1) - TILE_HEIGHT)
                            cursor_y <= cursor_y + TILE_HEIGHT;
                5'b00100: if(cursor_x >= TILE_WIDTH)
                            cursor_x <= cursor_x - TILE_WIDTH;
                5'b00010: if(cursor_x <= (DISP_WIDTH-1) - TILE_WIDTH)
                            cursor_x <= cursor_x + TILE_WIDTH;
            endcase
        end
    end
end

// Check if current pixel being rendered overlaps with current cursor location
reg on_cursor;
always @(*) begin
    if((vga_x_coord >= cursor_x) && (vga_x_coord <= cursor_x + TILE_WIDTH) && 
       (vga_y_coord >= cursor_y) && (vga_y_coord <= cursor_y + TILE_HEIGHT))
    begin
        on_cursor = 1'b1;
    end else begin
        on_cursor = 1'b0;
    end
end

// Handle memory delays
reg [15:0] pix_x_delayed_1, pix_x_delayed_2, pix_y_delayed_1, pix_y_delayed_2;
always @(posedge clk_75mhz, posedge rst_sync) begin
    if(rst_sync) begin
        pix_x_delayed_1 <= 0;
        pix_y_delayed_1 <= 0;
        pix_x_delayed_2 <= 0;
        pix_y_delayed_2 <= 0;
    end else begin
        pix_x_delayed_1 <= vga_x_coord;
        pix_y_delayed_1 <= vga_y_coord;
        pix_x_delayed_2 <= pix_x_delayed_1;
        pix_y_delayed_2 <= pix_y_delayed_1;
    end
end

// Handle Ram Adressing
assign tile_bram_addr_b = pixel_tile_addr;
assign ascii_bram_addr = {tile_bram_data_out_b, vga_y_coord[3:0]};

always @(posedge clk_75mhz) begin
    if(on_cursor) begin
        vga_color_in <= 12'b000011110000;
    end else begin
        if(ascii_bram_row_out[~pix_x_delayed_2[2:0]]) begin
            vga_color_in <= 12'b000011110000;
        end else begin
            vga_color_in <= 12'b000000000000;
        end
    end
end

// Handle Writing values
assign tile_bram_addr_a = cursor_tile_addr;
always @(*) begin
    if(keyboard_en_sync) begin
        if(ps2_rx_done & !ps2_ignore_next) begin
            case(ps2_rx_data)
                8'h29: begin // space
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h00;
                       end            
                8'h1C: begin // A
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h41;
                       end
                8'h32: begin // B
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h42;
                       end
                8'h21: begin // C
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h43;
                       end
                8'h23: begin // D
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h44;
                       end
                8'h24: begin // E
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h45;
                       end
                8'h2b: begin // F
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h46;
                       end
                8'h34: begin // G
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h47;
                       end
                8'h33: begin // H
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h48;
                       end
                8'h43: begin // I
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h49;
                       end
                8'h3b: begin // J
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4a;
                       end
                8'h42: begin // K
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4b;
                       end
                8'h4b: begin // L
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4c;
                       end
                8'h3a: begin // M
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4d;
                       end
                8'h31: begin // N
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4e;
                       end
                8'h44: begin // O
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h4f;
                       end
                8'h4d: begin // P
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h50;
                       end
                8'h15: begin // Q
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h51;
                       end
                8'h2d: begin // R
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h52;
                       end
                8'h1b: begin // S
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h53;
                       end
                8'h2c: begin // T
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h54;
                       end
                8'h3c: begin // U
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h55;
                       end
                8'h2a: begin // V
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h56;
                       end
                8'h1d: begin // W
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h57;
                       end
                8'h22: begin // X
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h58;
                       end
                8'h35: begin // Y
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h59;
                       end
                8'h1a: begin // Z
                            tile_bram_we = 1;
                            tile_bram_data_in_a = 8'h5a;
                       end
                default: begin 
                            tile_bram_we = 0;
                            tile_bram_data_in_a = 8'h00;
                         end
            endcase
        end else begin
            tile_bram_we = 0;
            tile_bram_data_in_a = 8'h00;
        end
    end else begin
        tile_bram_we = center_sync;
        tile_bram_data_in_a = 8'h41;
    end
end


endmodule
