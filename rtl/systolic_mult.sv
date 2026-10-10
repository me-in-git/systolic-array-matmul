// systolic_mult: NxN output-stationary systolic matrix multiplier
module systolic_mult #(
    parameter int N     = 4,                       // matrix dimension
    parameter int DW    = 8,                       // signed operand width
    parameter int ACC_W = 2*DW + $clog2(N)         // accumulator width
)(
    input  logic clk,
    input  logic rst_n,
    input  logic load_a,                           // capture a_row_in
    input  logic load_b,                           // capture b_col_in
    input  logic [N*DW-1:0] a_row_in,              // packed row  (one per load_a)
    input  logic [N*DW-1:0] b_col_in,              // packed column (one per load_b)
    input  logic start,
    output logic busy,
    output logic done,
    output logic [N*N*ACC_W-1:0] c_data
);

    // Matrix storage (loaded one row / one column at a time)
    logic signed [DW-1:0] a_mem [0:N-1][0:N-1];
    logic signed [DW-1:0] b_mem [0:N-1][0:N-1];
    logic [$clog2(N)-1:0]        wa, wb;     // write index (wraps 0..N-1)
    logic                        a_full, b_full; // all rows/cols captured

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wa      <= '0;
            wb      <= '0;
            a_full  <= 1'b0;
            b_full  <= 1'b0;
        end else begin
            if (load_a) begin
                for (int k = 0; k < N; k++)
                    a_mem[wa][k] <= $signed(a_row_in[k*DW +: DW]);
                a_full <= (wa == N-1);              // set when row N-1 written
                wa     <= (wa == N-1) ? '0 : wa + 1'b1;
            end
            if (load_b) begin
                for (int k = 0; k < N; k++)
                    b_mem[k][wb] <= $signed(b_col_in[k*DW +: DW]);
                b_full <= (wb == N-1);              // set when col N-1 written
                wb     <= (wb == N-1) ? '0 : wb + 1'b1;
            end
        end
    end

    // Feed controller: staggered wavefront generation
    typedef enum logic [1:0] { IDLE, RUN } state_t;
    state_t            state;
    logic              init_all;
    logic [$clog2(3*N+1)-1:0] t;

    // Flag needed by the PE grid below; assigned by the FSM.
    logic              run;

    always_comb init_all = run && (t == 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            t     <= '0;
        end else begin
            case (state)
                IDLE: if (start && a_full && b_full) begin
                          state <= RUN;
                          t     <= '0;
                      end
                RUN:  if (t == 3*N - 1) begin
                          state <= IDLE;
                          t     <= '0;
                      end else begin
                          t     <= t + 1'b1;
                      end
                default: state <= IDLE;
            endcase
        end
    end

    assign run  = (state == RUN);
    assign busy = run;

    // Staggered input wires: row i is delayed by i, column j by j.
    logic signed [DW-1:0] a_wire [0:N-1];
    logic signed [DW-1:0] b_wire [0:N-1];
    genvar i, j;

    for (i = 0; i < N; i++) begin : g_feed_a
        always_comb begin
            if (run && (t >= i) && (t < i + N))
                a_wire[i] = a_mem[i][t - i];
            else
                a_wire[i] = '0;
        end
    end

    for (j = 0; j < N; j++) begin : g_feed_b
        always_comb begin
            if (run && (t >= j) && (t < j + N))
                b_wire[j] = b_mem[t - j][j];
            else
                b_wire[j] = '0;
        end
    end

    // PE grid + interconnect (a: left->right, b: top->bottom)
    logic signed [DW-1:0]    a_link [0:N-1][0:N-1];
    logic signed [DW-1:0]    b_link [0:N-1][0:N-1];
    logic signed [ACC_W-1:0] acc    [0:N-1][0:N-1];

    for (i = 0; i < N; i++) begin : g_rows
        for (j = 0; j < N; j++) begin : g_cols
            systolic_pe #(.DW(DW), .ACC_W(ACC_W)) u_pe (
                .clk   (clk),
                .rst_n (rst_n),
                .init  (init_all),
                // edge cells take the skewed feed, others the neighbor
                .a_in  (j == 0 ? a_wire[i] : a_link[i][j > 0 ? j-1 : 0]),
                .b_in  (i == 0 ? b_wire[j] : b_link[i > 0 ? i-1 : 0][j]),
                .a_out (a_link[i][j]),
                .b_out (b_link[i][j]),
                .acc   (acc[i][j])
            );
        end
    end

    // Result read-out
    logic done_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_r <= 1'b0;
        end else begin
            done_r <= (state == RUN) && (t == 3*N - 1);
        end
    end
    assign done = done_r;

    for (i = 0; i < N; i++) begin : g_res
        for (j = 0; j < N; j++) begin : g_resc
            assign c_data[(i*N + j)*ACC_W +: ACC_W] = acc[i][j];
        end
    end

endmodule