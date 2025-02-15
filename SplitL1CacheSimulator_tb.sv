
module cache_simulator_testbench;

  logic test_mode;
  bit a = 0;
  logic clock = 0;
  logic reset = 0;
  logic [3:0] trace_number;
  logic [31:0] trace_address;
  int filename;
  string line;
  string tracefile;
  int read_file;

  data_cache data_cache_dut ( .clock(clock), .reset(reset), .trace_number(trace_number), .trace_address(trace_address), .test_mode(test_mode), .a(a) );
  instruction_cache instruction_cache_dut ( .clock(clock), .reset(reset), .trace_number(trace_number), .trace_address(trace_address), .test_mode(test_mode), .a(a));

  always #5 clock =~ clock;

  initial
    begin
      @(negedge clock);
      reset = 1;
      @(negedge clock);
      reset = 0;

      if ($value$plusargs("Tracefile=%s", tracefile))
      filename = $fopen(tracefile,"r");
      
      if(filename==0)
        begin
          $display("Trace file not found");
          $stop;
        end

      if ($test$plusargs("Mode"))
    	test_mode=0;
      else
    	test_mode=1;

      while(!$feof(filename))
        @(negedge clock)
        begin
          read_file = $fgets( line , filename );
          $display("         ");
          $display("%s",line);

          read_file = $sscanf(line,"%d %h", trace_number, trace_address);
          if(read_file != 2)
            begin
              $display("Trace filename formatting is incorrect");
              trace_number=4'bx;
            end
        end
      $fclose(filename);
	a = 1;
      #25
      $stop;
    end
endmodule