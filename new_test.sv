`timescale 1ns/1ps
`define DATA_WIDTH 16

interface fifo_if #(parameter DATA_WIDTH= `DATA_WIDTH
                )(
                input bit clk, rstn
                );
                logic wr_en;
                logic rd_en;
                logic [DATA_WIDTH-1:0] wdata;
                logic [DATA_WIDTH-1:0] rdata;
                logic full;
                logic empty;
endinterface

class transaction #(parameter DATA_WIDTH=`DATA_WIDTH);
        rand bit wr_en;
	rand bit rd_en;
	bit rstn;
        rand bit [DATA_WIDTH-1:0] wdata;


	bit [DATA_WIDTH-1:0] rdata;
        bit full;
        bit empty;
 
 	bit [DATA_WIDTH-1:0] exp_rdata;
        bit exp_full;
        bit exp_empty;
endclass

class generator;
        mailbox gen2drv;
        transaction tr; 
        int count;
        function new(mailbox gen2drv);
                this.gen2drv=gen2drv;
        endfunction
        task run;
                for(int i=0; i<count; i++) begin
                        tr=new();
		       	if (i % 2 ==0) begin
			 tr.randomize() with {
					 wr_en==1;
					 rd_en==0;
			};
                        end
			else begin
				tr.randomize() with {
					wr_en==0;
					rd_en==1;
					};
				end
			
                        $display("[%0t] GEN: i=%0d wr_en=%0b rd_en=%0b", $time, i, tr.wr_en, tr.rd_en);
			end
			gen2drv.put(tr);
        endtask

	task sim_run; 
	       	for(int i=0; i<count; i++) begin
                        tr=new();
                        if (i<5) begin
				tr.randomize with {
                                wr_en==1;
                                rd_en==0;
				};
                        end
                        else begin
				tr.randomize with {
                                wr_en==0;
                                rd_en==1;
				};
                        end
                        gen2drv.put(tr);
                end
        endtask
	task rd_wr_run; 
	       	for(int i=0; i<count; i++) begin
                        tr=new();
                        if (i<5) begin
				tr.randomize with {
                                wr_en==1;
                                rd_en==1;
				};
                        end
                        else begin
				tr.randomize with {
                                wr_en==1;
                                rd_en==0;
				};
                        end
                        gen2drv.put(tr);
                end
        endtask
	task full_run;
			for(int i=0; i<count; i++) begin
                        tr=new();
                        if (i<9) begin
				tr.randomize with {
                                wr_en==1;
                                rd_en==0;
				};
                        end
			else begin
				tr.randomize with{
					wr_en==0;
					rd_en==1;
					};
				end
			gen2drv.put(tr);
		end
	endtask
	task empty_run;
			for(int i=0; i<count; i++) begin
                        tr=new();
                        if (i<5) begin
				tr.randomize with {
                                wr_en==1;
                                rd_en==0;
				};
                        end
			else begin
				tr.randomize with{
					wr_en==0;
					rd_en==1;
					};
				end
			gen2drv.put(tr);
		end
	endtask
       
	task random_run;
                for(int i=0; i<count; i++) begin
                        tr=new();
			tr.randomize();	
                        $display("[%0t] GEN: i=%0d wr_en=%0b rd_en=%0b", $time, i, tr.wr_en, tr.rd_en);	
			gen2drv.put(tr);
		end
        endtask


		 
endclass


class driver;
        mailbox gen2drv;
        virtual fifo_if #(`DATA_WIDTH) vif;
        transaction tr;

        function new(mailbox gen2drv, virtual fifo_if #(`DATA_WIDTH) vif);
                this.gen2drv=gen2drv;
                this.vif=vif;
        endfunction

        task run;
                forever begin
                        @(posedge vif.clk);
                        gen2drv.get(tr);
                        vif.wr_en<=tr.wr_en;
                        vif.rd_en<=tr.rd_en;
                        vif.wdata<=tr.wdata;
                end
        endtask
endclass


class monitor;
        mailbox mon2sb;
        mailbox mon2ref;
        virtual fifo_if #(`DATA_WIDTH) vif;

        function new(mailbox mon2sb, mailbox mon2ref, virtual fifo_if #(`DATA_WIDTH) vif);
                this.mon2sb=mon2sb;
                this.mon2ref=mon2ref;
                this.vif=vif;
        endfunction

        task run;
                forever begin

                        transaction #(`DATA_WIDTH) mon_tr;
                        mon_tr=new();

                        @(posedge vif.clk);


                        if (!vif.rstn)
                                continue;

                        mon_tr.wr_en=vif.wr_en;
                        mon_tr.rd_en=vif.rd_en;


                        if(vif.wr_en) begin
                                mon_tr.wdata=vif.wdata;
                        end

                        if(vif.rd_en) begin
                                mon_tr.rdata=vif.rdata;
                        end

                        mon_tr.full=vif.full;
                        mon_tr.empty=vif.empty;
			mon_tr.rstn=vif.rstn;
                        mon2sb.put(mon_tr);
                        mon2ref.put(mon_tr);
                end
        endtask
endclass

class reference #(parameter DEPTH=8);
        mailbox mon2ref;
        mailbox ref2sb;
        bit [`DATA_WIDTH-1:0] q[$];
        bit [`DATA_WIDTH-1:0] last_rdata;

        function new(mailbox mon2ref, mailbox ref2sb);
                this.mon2ref=mon2ref;
                this.ref2sb=ref2sb;
      		last_rdata= '0;
      	endfunction

        task run;
                forever begin
                        transaction #(`DATA_WIDTH) tr;
                        mon2ref.get(tr);
				
			if(!tr.rstn) begin
				q.delete();
				last_rdata= '0;
				continue;
			end
                        if (tr.wr_en && q.size() < DEPTH) begin
                                q.push_front(tr.wdata);
                        end

                        else if (tr.rd_en && q.size() > 0) begin
                                last_rdata=q.pop_back();
                        end
			else if (tr.rd_en && q.size() == 0) begin
				last_rdata= '0;
			end
                        
			tr.exp_rdata=tr.rd_en ? last_rdata : '0;
			tr.exp_full=(q.size()==DEPTH);
                        tr.exp_empty=(q.size()==0);

                        ref2sb.put(tr);
                end
        endtask
endclass

class scoreboard;

        mailbox mon2sb;
        mailbox ref2sb;

        int compare_count;
        int pass;
        int fail;

        function new(mailbox mon2sb, mailbox ref2sb);
                this.mon2sb=mon2sb;
                this.ref2sb=ref2sb;
        endfunction

        task run;
                forever begin
                        transaction tr_act, tr_exp;
                        mon2sb.get(tr_act);
                        ref2sb.get(tr_exp);

                        if (tr_act.rdata==tr_exp.exp_rdata) begin
                                $display("[%0t] WDATA=%0d, wr_en=%0d, rd_en=%0d, RDATA=%0d, exp_rdata=%0d, EMPTY=%0d, FULL=%0d",
                                        $time, tr_act.wdata, tr_act.wr_en, tr_act.rd_en, tr_act.rdata, tr_exp.exp_rdata, tr_act.empty, tr_act.full);
                                        pass++;
                        end
                        else begin
                                $display("[%0t] WDATA=%0d, wr_en=%0d, rd_en=%0d, RDATA=%0d, exp_rdata=%0d, EMPTY=%0d, FULL=%0d",
                                        $time, tr_act.wdata, tr_act.wr_en, tr_act.rd_en, tr_act.rdata, tr_exp.exp_rdata, tr_act.empty, tr_act.full);
                                        fail++;
                        end
                        compare_count++;
                end
        endtask

        task report;
                $display("[%0t] Pass Count = %0d, Fail Count= %0d, Total test count= %0d", $time, pass, fail, pass+fail);
        endtask
endclass

class agent;

	driver drv;
        monitor mon;
        generator gen;

        mailbox gen2drv;
        virtual fifo_if #(`DATA_WIDTH) vif;

        function new(mailbox mon2sb, mailbox mon2ref, virtual fifo_if #(`DATA_WIDTH) vif);
                gen2drv=new();

                drv=new(gen2drv, vif);
                mon=new(mon2sb, mon2ref, vif);
                gen=new(gen2drv);
        endfunction

        task run;
                fork
                        drv.run();
                        mon.run();
                        gen.run();
		join_any
        endtask

	 task sim_run;
                fork
                        drv.run();
                        mon.run();
                        gen.sim_run();
		join_none
        endtask
	
       	task rd_wr_run;
                fork
                        drv.run();
                        mon.run();
                        gen.rd_wr_run();
		join_none
        endtask
       
	task full_run;
                fork
                        drv.run();
                        mon.run();
                        gen.full_run();
		join_none
        endtask

	task empty_run;
                fork
                        drv.run();
                        mon.run();
                        gen.empty_run();
		join_none
        endtask

	task random_run;
                fork
                        drv.run();
                        mon.run();
                        gen.random_run();
		join_none
        endtask





endclass

class env;
        agent agt;
        scoreboard sb;
        reference rf;

        mailbox mon2ref;
        mailbox mon2sb;
        mailbox ref2sb;

        function new(virtual fifo_if #(`DATA_WIDTH) vif);

                mon2sb=new();
                mon2ref=new();
                ref2sb=new();

                agt=new(mon2sb, mon2ref, vif);
                sb=new(mon2sb, ref2sb);
                rf=new(mon2ref, ref2sb);
        endfunction

        task run;
                fork
                        agt.run();
                        sb.run();
                        rf.run();
		join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask 
	
	task sim_run;
                fork
                        agt.sim_run();
                        sb.run();
                        rf.run();
                join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask

	task rd_wr_run;
                fork
                        agt.rd_wr_run();
                        sb.run();
                        rf.run();
                join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask
	task full_run;
                fork
                        agt.full_run();
                        sb.run();
                        rf.run();
                join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask
	task empty_run;
                fork
                        agt.empty_run();
                        sb.run();
                        rf.run();
                join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask
	task random_run;
                fork
                        agt.random_run();
                        sb.run();
                        rf.run();
                join_none
                wait(sb.compare_count == agt.gen.count);
        $display("[%0t] ENV: WAIT CONDITION SATISFIED", $time);
      
                $finish;
        endtask



endclass

class base_test;

        env env_o;
        virtual fifo_if #(`DATA_WIDTH) vif;

	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		this.vif=vif;
		env_o=new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=10;
	endtask

	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
                env_o.agt.gen.count=10;
                wait(vif.rstn == 1'b1);
                env_o.run();
	endtask
endclass


class reset_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=10;
	endtask
	
	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
               /* env_o.agt.gen.count=10;*/
                wait(vif.rstn == 1'b1);
	
	$display("[%0t] DEBUG: gen.count=%0d", $time, env_o.agt.gen.count);
	fork
		env_o.run();
		begin
			repeat(4) @(posedge vif.clk);
			$display("Asserting reset at %t", $time);
			vif.rstn<=0;
			repeat(2) @(posedge vif.clk);
			
			if(!vif.empty)
				$display("FAIL");
			else $display("PASS");
			$display("Deasserting reset at %t", $time);
			vif.rstn<=1;
		end
	join
	
	endtask
endclass

class sim_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=11;
	endtask
	
	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
               /* env_o.agt.gen.count=10;*/
                wait(vif.rstn == 1'b1);
	
	$display("[%0t] DEBUG: gen.count=%0d", $time, env_o.agt.gen.count);
		env_o.sim_run();
	
	endtask
endclass
class rd_wr_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=11;
	endtask
	
	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
               /* env_o.agt.gen.count=10;*/
                wait(vif.rstn == 1'b1);
	
	$display("[%0t] DEBUG: gen.count=%0d", $time, env_o.agt.gen.count);
		env_o.rd_wr_run();
	
	endtask
endclass
class full_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=20;
	endtask
	
	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
                wait(vif.rstn == 1'b1);
	
	$display("[%0t] DEBUG: gen.count=%0d", $time, env_o.agt.gen.count);
		env_o.full_run();
	
	endtask
endclass

class empty_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=15;
	endtask

	virtual task run;
		$display("[%0t] TEST INITIATED", $time);
		test_count();
		wait(vif.rstn == 1'b1);

		$display("[%0t] TERMINATING", $time);
		env_o.empty_run();
	endtask
endclass

class random_test extends base_test;
	function new(virtual fifo_if #(`DATA_WIDTH) vif);
		super.new(vif);
	endfunction

	virtual task test_count;
		env_o.agt.gen.count=11;
	endtask
	
	virtual task run;
		$display("[%0t] TEST STARTED", $time);
		test_count();
               /* env_o.agt.gen.count=10;*/
                wait(vif.rstn == 1'b1);
	
	$display("[%0t] DEBUG: gen.count=%0d", $time, env_o.agt.gen.count);
		env_o.random_run();
	
	endtask
endclass


program test_top(fifo_if vif);
        
	base_test t;

	initial begin
		if ($test$plusargs("RESET_TEST")) begin
			reset_test rt;
			rt=new(vif);
			t=rt;
		end
		else if ($test$plusargs("SIM_TEST"))  begin
		       sim_test st;
		       st=new(vif);
		       t=st;
		end
		else if ($test$plusargs("RD_WR_TEST")) begin
			rd_wr_test rdst;
			rdst=new(vif);
			t=rdst;
		end
		else if ($test$plusargs("FULL_TEST")) begin
			full_test fst;
			fst=new(vif);
			t=fst;
		end	
		else if ($test$plusargs("EMPTY_TEST")) begin
			empty_test est;
			est=new(vif);
			t=est;
		end
		else if ($test$plusargs("RANDOM")) begin
			random_test rnd;
			rnd=new(vif);
			t=rnd;
		end

		else begin
		       base_test bt;
	       		bt=new(vif);
			t=bt;
		end

	       t.run();
	
        end
endprogram

module tb_top;

        bit clk;
        bit rstn;

        always #5 clk=~clk;

        fifo_if #(`DATA_WIDTH) vif(clk, rstn);

        sync_fifo DUT(.clk(vif.clk), .rstn(vif.rstn), .wr_en(vif.wr_en), .rd_en(vif.rd_en), .wdata(vif.wdata), .rdata(vif.rdata), .full(vif.full), .empty(vif.empty));
        test_top t1(vif);

        initial begin
                clk=0;
                rstn=0;
                #22;
                rstn=1;
        end
endmodule

                              
                                                                                                                                                                                                                                                                                                                    

