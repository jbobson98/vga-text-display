/* Display Tile Block Ram -----------------------------------------
*   [DUAL PORT BLOCK RAM]
*   The VGA display can be divided into tiles of WxH where each
*   tile will display a single ascii character. This BRAM stores
*   which ascii character is mapped to which tile.
-----------------------------------------------------------------*/

module display_tile_bram #(
    parameter DATA_WIDTH = 8,   // 8-bits for ascii code
    parameter ADDR_WIDTH = 13
)(
    input wire clk,
    input wire write_enable,
    input wire [ADDR_WIDTH-1 : 0] addr_a, addr_b,
    input wire [DATA_WIDTH-1 : 0] data_in_a,
    output wire [DATA_WIDTH-1 : 0] data_out_a, data_out_b
);

(* ram_style = "block" *) reg [DATA_WIDTH-1 : 0] bram [2**ADDR_WIDTH-1 : 0];
(* rw_addr_collision= "yes" *) // allow write value to pass through in the case of a collision


reg [ADDR_WIDTH-1 : 0] addr_a_reg, addr_b_reg;

assign data_out_a = bram[addr_a_reg];
assign data_out_b = bram[addr_b_reg];

always @(posedge clk) begin
    if(write_enable) bram[addr_a] <= data_in_a;
    addr_a_reg <= addr_a;
    addr_b_reg <= addr_b;
end

endmodule