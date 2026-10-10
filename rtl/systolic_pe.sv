// systolic_pe: MAC processing element
module systolic_pe #(
    parameter int DW    = 8,     // data path width (signed operands)
    parameter int ACC_W = 18     // accumulator width
)(
    input  logic clk,
    input  logic rst_n,
    input  logic init,                       // clear partial sum
    input  logic signed [DW-1:0]    a_in,    // from left / top edge
    input  logic signed [DW-1:0]    b_in,
    output logic signed [DW-1:0]    a_out,   // to next cell right / down
    output logic signed [DW-1:0]    b_out,
    output logic signed [ACC_W-1:0] acc      // partial result
);

    logic signed [DW-1:0]    a_r, b_r;
    logic signed [ACC_W-1:0] acc_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r   <= '0;
            b_r   <= '0;
            acc_r <= '0;
        end else begin
            a_r   <= a_in;
            b_r   <= b_in;
            if (init)
                acc_r <= '0;
            else
                acc_r <= acc_r + ($signed(a_r) * $signed(b_r));
        end
    end

    assign a_out = a_r;
    assign b_out = b_r;
    assign acc   = acc_r;

endmodule