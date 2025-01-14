module application_driver #(
    parameter int unsigned MASTER_NUMBER = 1,
    parameter int unsigned IS_HWPE = 1,
    parameter int unsigned DATA_WIDTH = 1,
    parameter int unsigned ADD_WIDTH = 1,
    parameter int unsigned APPL_DELAY = 2, //delay on the input signals //parameter ACQ_DELAY ?
    parameter int unsigned IW = 1
) (
    hci_core_intf.initiator        master,
    input logic                    rst_ni,
    input logic                    clear_i,
    input logic                    clk,
    output logic                   end_stimuli,
    output logic                   end_latency
);  

    initial begin: application_block // one application block for each master`s port must be instantiated in the tb

        int stim_fd, ret_code, stim_applied;
        logic [IW-1:0] id;
        string file_path;
        integer stim;
        logic wen, req;
        logic [DATA_WIDTH-1:0] data;
        logic [ADD_WIDTH-1:0]  add;
        logic last_wen;

        master.id = -1;
        master.add = '0;
        master.data = '0;
        master.req = 0;
        master.wen = 0;

        master.be = -1; //all bits are 1
        master.r_ready = 1;
        master.user = 0;
        
        end_stimuli = 1'b0;
        end_latency = 1'b0;

        wait (rst_ni);
        if(IS_HWPE) begin
            file_path = $sformatf("./verif/simvectors/stimuli_processed/master_hwpe_%0d.txt",MASTER_NUMBER);
        end else begin
            file_path = $sformatf("./verif/simvectors/stimuli_processed/master_log_%0d.txt",MASTER_NUMBER);
        end
        stim = $fopen(file_path, "r");
        if (stim == 0) begin
            $fatal("ERROR: Could not open stimuli file!");
        end
        @(posedge clk);
        while (!$feof(stim)) begin
            ret_code = $fscanf(stim, "%b %b %b %b %b\n",req, id, wen, data, add); 
            //cycle = $urandom_range(10,1);
            //repeat(cycle) @(posedge clk);
            #(APPL_DELAY);
            master.id = id;
            master.data = data;
            master.add = add;
            master.wen = wen;
            master.req = req;
            //#(ACQ_DELAY-APPL_DELAY);
            last_wen = wen;
            if(req) begin
                while(1) begin
                    @(posedge clk);
                    if(master.gnt) begin
                        master.id = '0;
                        master.data = '0;
                        master.add = '0;
                        master.wen = '0;
                        master.req = '0;
                        break;
                    end
                end
            end else begin
                @(posedge clk);
            end
        end
        end_stimuli = 1'b1;
        if(last_wen) begin
            while(1) begin
                @(posedge clk);
                if(master.r_valid) begin
                    end_latency = 1'b1;
                end
            end
        end else begin
            end_latency = 1'b1;
        end
        $fclose(stim);
    end
endmodule