// tb_systolic: compares C against a software reference
module tb_systolic;

    parameter  int N     = 4;     // override with iverilog -Ptb_systolic.N=<n>
    localparam int DW    = 8;
    localparam int ACC_W = 2*DW + $clog2(N);

    logic clk = 0;
    logic rst_n = 0;
    logic load_a = 0, load_b = 0, start = 0;
    logic [N*DW-1:0] a_row_in = '0, b_col_in = '0;
    logic busy, done;
    logic [N*N*ACC_W-1:0] c_data;

    systolic_mult #(.N(N), .DW(DW)) dut (
        .clk(clk), .rst_n(rst_n),
        .load_a(load_a), .load_b(load_b),
        .a_row_in(a_row_in), .b_col_in(b_col_in),
        .start(start), .busy(busy), .done(done), .c_data(c_data)
    );

    always #5 clk = ~clk;

    integer a_mat [0:N-1][0:N-1];
    integer b_mat [0:N-1][0:N-1];
    integer m_mat [0:N-1][0:N-1];
    integer ref_mat [0:N-1][0:N-1];

    integer failures = 0;
    integer checks   = 0;

    integer i, j, k;

    // Load helpers
    task automatic load_A;
        begin
            for (i = 0; i < N; i++) begin
                a_row_in = '0;
                for (k = 0; k < N; k++)
                    a_row_in[k*DW +: DW] = a_mat[i][k][DW-1:0];
                load_a = 1;
                @(posedge clk);
                #1;                 // settle before changing stimulus
                load_a = 0;
                a_row_in = '0;
            end
        end
    endtask

    task automatic load_B;
        begin
            for (j = 0; j < N; j++) begin
                b_col_in = '0;
                for (k = 0; k < N; k++)
                    b_col_in[k*DW +: DW] = b_mat[k][j][DW-1:0];
                load_b = 1;
                @(posedge clk);
                #1;                 // settle before changing stimulus
                load_b = 0;
                b_col_in = '0;
            end
        end
    endtask

    // Software reference model: ref_mat = a_mat * b_mat
    task automatic compute_ref;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++) begin
                    ref_mat[i][j] = 0;
                    for (k = 0; k < N; k++)
                        ref_mat[i][j] += a_mat[i][k] * b_mat[k][j];
                end
        end
    endtask

    // Run one multiply and verify every word against the reference
    integer got;
    integer cyc;
    integer timed_out;
    task automatic run_and_check;
        input [255:0] tag;
        begin
            compute_ref;
            start = 1;
            @(posedge clk);
            #1;                     // settle before changing stimulus
            start = 0;

            cyc = 0;
            timed_out = 0;
            // count edges from start to done; check after #1 so done is settled
            while (done !== 1'b1 && !timed_out) begin
                @(posedge clk);
                cyc++;
                #1;
                if (cyc > 200) timed_out = 1;
            end

            if (timed_out) begin
                $display("FAIL: %0s timed out (done never asserted)", tag);
                failures++;
            end else begin
                for (i = 0; i < N; i++)
                    for (j = 0; j < N; j++) begin
                        got = $signed(c_data[(i*N+j)*ACC_W +: ACC_W]);
                        checks++;
                        if (got !== ref_mat[i][j]) begin
                            $display("FAIL: %0s C[%0d][%0d] = %0d, expect %0d",
                                     tag, i, j, got, ref_mat[i][j]);
                            failures++;
                        end
                    end
                $display("PASS: %0s (%0d cycles from start)", tag, cyc);
            end
        end
    endtask

    // Matrix generators (fill m_mat; caller copies to a_mat / b_mat)
    task automatic set_identity;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++)
                    m_mat[i][j] = (i == j) ? 1 : 0;
        end
    endtask

    task automatic set_zero;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++)
                    m_mat[i][j] = 0;
        end
    endtask

    task automatic set_ones;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++)
                    m_mat[i][j] = 1;
        end
    endtask

    integer v;
    task automatic set_random;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++) begin
                    v = $unsigned($random) % 256;
                    if (v >= 128) v = v - 256;
                    m_mat[i][j] = v;
                end
        end
    endtask

    task automatic copy_to_a;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++)
                    a_mat[i][j] = m_mat[i][j];
        end
    endtask

    task automatic copy_to_b;
        begin
            for (i = 0; i < N; i++)
                for (j = 0; j < N; j++)
                    b_mat[i][j] = m_mat[i][j];
        end
    endtask

    // Test sequence
    initial begin
        rst_n = 0;
        #(40);
        rst_n = 1;

        // 1: identity * identity
        set_identity; copy_to_a;
        set_identity; copy_to_b;
        load_A; load_B;
        run_and_check("I * I");

        // 2: identity * B => B
        set_identity; copy_to_a;
        set_random;   copy_to_b;
        load_A; load_B;
        run_and_check("I * B");

        // 2b: A * identity => A
        set_random;   copy_to_a;
        set_identity; copy_to_b;
        load_A; load_B;
        run_and_check("A * I");

        // 3: zero * B => 0
        set_zero;   copy_to_a;
        set_random; copy_to_b;
        load_A; load_B;
        run_and_check("0 * B");

        // 4: ones * B => row sums
        set_ones;   copy_to_a;
        set_random; copy_to_b;
        load_A; load_B;
        run_and_check("1 * B");

        // 5: random pair, run twice (same results => acc reset works)
        set_random; copy_to_a;
        set_random; copy_to_b;
        load_A; load_B;
        run_and_check("R * R (run1)");
        run_and_check("R * R (run2)");

        // 6: different pair immediately after (no stale accumulation)
        set_random; copy_to_a;
        set_random; copy_to_b;
        load_A; load_B;
        run_and_check("R' * R' (reuse)");

        if (failures === 0)
            $display("=== SYSTOLIC TEST: %0d checks, ALL PASS ===", checks);
        else
            $display("=== SYSTOLIC TEST: %0d checks, %0d FAILURES ===", checks, failures);
        $finish;
    end

endmodule