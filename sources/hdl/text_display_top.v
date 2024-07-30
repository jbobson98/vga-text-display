module text_display_top (
    input wire clk_in,
    input wire rst_in,
    input wire up_in,
    input wire down_in,
    input wire left_in,
    input wire right_in,
    input wire center_in,
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
wire rst_sync, up_sync, down_sync, left_sync, right_sync, center_sync;
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
wire tile_bram_we;
wire [TILE_ADDR_WIDTH-1 : 0] tile_bram_addr_a, tile_bram_addr_b;
wire [ASCII_BITS-1 : 0] tile_bram_data_in_a, tile_bram_data_out_a, tile_bram_data_out_b;
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

// Handle cursor position update
always @(posedge clk_75mhz, posedge rst_sync) begin
    if(rst_sync) begin
        cursor_x <= 0;
        cursor_y <= 0;
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


// Handle Ram Adressing
assign tile_bram_addr_b = pixel_tile_addr;
assign ascii_bram_addr = {tile_bram_data_out_b, vga_y_coord[3:0]};
always @(posedge clk_75mhz) begin
    if(on_cursor) begin
        vga_color_in <= 12'b111111111111;
    end else begin
        if(ascii_bram_row_out[vga_x_coord[2:0]]) begin
            vga_color_in <= 12'b111111111111;
        end else begin
            vga_color_in <= 12'b000000001111;
        end
    end
end

// Handle Writing values
assign tile_bram_we = center_sync;
assign tile_bram_addr_a = cursor_tile_addr;
assign tile_bram_data_in_a = 8'h41;




endmodule
