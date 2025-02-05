module progress_bar #(
    parameter int unsigned TOT_CHECK = 1
) (
    input logic           rst_n,
    input int unsigned    n_checks
);

  initial begin
    wait(rst_n);
    $display("START!");
    wait(real'(n_checks)/TOT_CHECK >= 0.1);
    $display("10%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.2);
    $display("20%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.3);
    $display("30%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.4);
    $display("40%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.5);
    $display("50%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.6);
    $display("60%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.7);
    $display("70%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.8);
    $display("80%% completed...");
    wait(real'(n_checks)/TOT_CHECK >= 0.9);
    $display("90%% completed...");
    wait(real'(n_checks)/TOT_CHECK == 1);
    $display("100%% completed!");
  end

endmodule