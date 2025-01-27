module compute_througput_and_simtime #(
    parameter int unsigned         N_MASTER,
    parameter int unsigned         N_TRANSACTION_LOG,
    parameter int unsigned         CLK_PERIOD,
    parameter int unsigned         DATA_WIDTH,
    parameter int unsigned         N_MASTER_REAL,
    parameter int unsigned         N_HWPE_REAL,
    parameter int unsigned         N_TRANSACTION_HWPE,
    parameter int unsigned         HWPE_WIDTH
) (
    input logic [0:N_MASTER-1]     END_STIMULI,
    input logic [0:N_MASTER-1]     END_LATENCY,
    input logic                    rst_n,
    input logic                    clk,
    output real                    troughput_real,
    output real                    tot_latency,
    output real                    latency_per_master[N_MASTER]
);  

//througput
  initial begin
    time                 start_time, end_time;
    real                 tot_time,tot_data;
    troughput_real = -1;
    wait(rst_n);
    #(CLK_PERIOD/100);
    @(posedge clk);
    start_time = $time;
    wait(&END_STIMULI);
    end_time = $time;
    tot_time = (end_time - start_time)/CLK_PERIOD; // ns
    tot_data = ((N_TRANSACTION_LOG * DATA_WIDTH) * (N_MASTER_REAL - N_HWPE_REAL) + (N_TRANSACTION_HWPE * HWPE_WIDTH * DATA_WIDTH) * N_HWPE_REAL); // bit
    troughput_real = tot_data/tot_time; // Gbps
  end
//simtime
  generate
    for(genvar ii=0;ii<N_MASTER;ii++) begin
      initial begin
        time                 start_time, end_time;
        latency_per_master[ii] = 0;
        wait(rst_n);
        #(CLK_PERIOD/100);
        @(posedge clk);
        start_time = $time;
        wait(END_LATENCY[ii]);
        end_time = $time;
        latency_per_master[ii] = (end_time - start_time)/CLK_PERIOD;
      end
    end
  endgenerate

  initial begin
      time                 start_time, end_time;
      tot_latency = 0;
      wait(rst_n);
      #(CLK_PERIOD/100);
      @(posedge clk);
      start_time = $time;
      wait(&END_LATENCY);
      end_time = $time;
      tot_latency = (end_time - start_time)/CLK_PERIOD;

  end

endmodule