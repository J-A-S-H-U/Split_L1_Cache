
module data_cache( clock, reset, trace_number, trace_address, data_read, data_write, data_hit, data_miss, test_mode, a );

  input logic test_mode;
  input bit a;
  input logic clock;
  input logic reset;
  input logic [3:0]  trace_number;       									// from trace file
  input logic [31:0] trace_address;	  									// Address from trace file
  output real data_read, data_write, data_hit, data_miss;
  typedef enum {Modified, Exclusive, Shared, Invalid} state;

  parameter ADDR_BITS = 32;											// Total Number of Address Bits
  parameter TOTAL_SETS = 16*1024;										// Total number of TOTAL_SETS
  parameter TOTAL_WAYS = 8;											// Total number of TOTAL_WAYS
  parameter CACHE_LINE_SIZE = 64; 										// Total number of bytes in cache line
  parameter BYTE_OFFSET_BITS = $clog2 (CACHE_LINE_SIZE);							// Number of byte offset bits
  parameter SET_SELECT_BITS = $clog2 (TOTAL_SETS);								// Number of byte offset bits
  parameter TAG_BITS = ADDR_BITS - (BYTE_OFFSET_BITS + SET_SELECT_BITS);					// Number of TAG bits
  parameter LRU_bits = $clog2 (TOTAL_WAYS);									// Number of LRU bits

  real data_hit_ratio; 												
  logic [LRU_bits-1:0] LRU[TOTAL_SETS-1:0][TOTAL_WAYS-1:0] = {default:3'b000};					// LRU bits per cache line - Default set to 000
  logic [TAG_BITS-1:0] TAG[TOTAL_SETS-1:0][TOTAL_WAYS-1:0];							// Tag bits per cache line
  bit valid[TOTAL_SETS-1:0][TOTAL_WAYS-1:0];
  bit dirty[TOTAL_SETS-1:0][TOTAL_WAYS-1:0];
  bit first_write_through [TOTAL_SETS -1: 0] [TOTAL_WAYS-1:0];

  state MESI[TOTAL_SETS-1 : 0][TOTAL_WAYS-1:0];
  int exit = 0;
  int valid_bit_count = 0;

  logic [BYTE_OFFSET_BITS- 1 :0] byte_offset;
  logic [SET_SELECT_BITS-1 :0] set_index;
  logic [TAG_BITS -1 :0] tag_index;

  assign byte_offset = trace_address [BYTE_OFFSET_BITS-1 :0];
  assign set_index = trace_address [BYTE_OFFSET_BITS + SET_SELECT_BITS-1 :BYTE_OFFSET_BITS];
  assign tag_index = trace_address [ADDR_BITS-1: BYTE_OFFSET_BITS + SET_SELECT_BITS];
  
  always@(a)
  begin
  display_cache_contents();
  display_report();
  end
  
  always_ff @(posedge clock, posedge reset)
    begin
      if(reset)
        begin
          data_read = 0;
          data_write = 0;
          data_hit = 0;
          data_miss = 0;
          foreach (MESI [x,y])
            begin
              TAG[x][y] = 0;
              MESI[x][y] = Invalid;
              LRU[x][y] = 3'b000;
              first_write_through[x][y] = 0;
              valid[x][y] = 0;
              dirty[x][y] = 0;
            end
        end

      else
        begin

          if (trace_number != 2)
            begin
              case(trace_number)
                0, 1, 3, 4:
                  begin
                    exit = 0;
                    for(int m=0 ; m<TOTAL_WAYS; m++)
                      begin
                        if(valid[set_index][m] == 1)
                          valid_bit_count = valid_bit_count +1;
                      end

                    for (int i = 0 ; i<TOTAL_WAYS ; i++)
                      begin
                        if ( (valid[set_index][i] == 0) && ( TAG[set_index][i] == tag_index) )
                          begin
				if(test_mode == 1'b1)
                                begin
					$display("------TAG BITS MATCH, HENCE HIT-------");
                           	 	$display("------Communication with L2------");
                            		$display("Data Cache : Write to L2 <%0h>", trace_address);
                            		$display(" ");
				end
                            	update_LRU(i);
                           	valid[set_index][i] = 1;
                           	dirty[set_index][i] = 0;
					
                         end
                     end

                    for(int m=0 ; m<TOTAL_WAYS; m++)
                      begin

                        ///////////////************************************ IF TAG BITS MATCH - HIT *********************************/////////////////////
                        if((exit==0 && valid[set_index][m] == 1) && ( TAG[set_index][m] == tag_index) )
                          begin
                            exit = 1;
                            data_hit = data_hit+1;
                            $display("------TAG BITS MATCH, HENCE HIT-------");

                            //////////////////////////////--------------------MODIFIED STATE -----------------------///////////////////////////////////

                            if (MESI[set_index][m] == Modified)
                              begin
                                if (trace_number == 0) 				// Read data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                    dirty[set_index][m]=1;
                                  end

                                else if (trace_number == 1)			// Write data request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write + 1;
                                    update_LRU(m);
				    
                                    if (first_write_through [set_index][m]==0)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("------Communication with L2------");
                                            $display("Data Cache : Write to L2 <%0h>", trace_address);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (trace_number == 3 || trace_number == 4)			// ( Invalidate command from L2 OR Snooping )

                                  begin
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
				    
                                    if(trace_number == 3)
                                      begin
                                        if(dirty[set_index][m] == 1)
                                          begin
                                            if(test_mode == 1'b1)
                                              begin
                                                $display("------Communication with L2------");
                                                $display("Data Cache : Write to L2 <%0h>", trace_address);
                                                $display(" ");
                                              end
                                            dirty[set_index][m]=0;
                                          end
                                      end
                                    if(trace_number == 4)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", trace_address);
                                            $display(" ");
					    $display("Data Cache : Read for Ownership from L2 <%0h>", trace_address);
                                          end
					  data_hit = data_hit-1;
                                      end
                                    valid[set_index][m] = 0;
				
                                  end
                              end

                            //////////////////////////////--------------------EXCLUSIVE STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Exclusive)
                              begin
                                if (trace_number == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                    dirty[set_index][m]=0;
                                  end

                                else if (trace_number == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write + 1;
                                    update_LRU(m);
			            
                                    if (first_write_through [set_index][m]==0)
				    begin
                                    	first_write_through [set_index][m]=1;
                                    	dirty[set_index][m]=1;
				    end
                                 end

                                else if (trace_number == 3 || trace_number == 4)		// ( 3 - Invalidate command from L2 or snooping) )
                                  begin
                                    
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Return to L2 <%0h>", trace_address);
                                            $display(" ");					    
                                          end
					  data_hit = data_hit-1;
                                      
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
				    valid[set_index][m] = 0;
                                  end
                              end

                            //////////////////////////////--------------------SHARED STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Shared)
                              begin
                                if (trace_number == 0) 				// Read data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    data_read = data_read + 1;
                                    update_LRU(m);
                                  end

                                else if (trace_number == 1)			// Write data req to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    data_write = data_write+1;
                                    update_LRU(m);
				     
                                    if (first_write_through [set_index][m]==0)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin

                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", trace_address);
                                            $display(" ");
                                          end

                                        first_write_through [set_index][m]=1;
                                      end
                                    dirty[set_index][m]=1;
                                  end

                                else if (trace_number == 3 || trace_number == 4)			// ( 3 - Invalidate command from L2 or Snooping )

                                  begin
                                    if(trace_number == 4)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : <%0h>", trace_address);
                                            $display(" ");
                                          end
                                      end
                                    MESI[set_index][m] = Invalid;
                                    update_LRU(m);
                                    valid[set_index][m] = 0;
                                  end
                              end
                          end  
                      end


                    ///////////////************************************ IF TAG BITS DON'T MATCH - MISS *********************************/////////////////////


                    if((valid_bit_count < TOTAL_WAYS) && (exit == 0))
                      begin
                        data_miss = data_miss+1;
                        $display("-----TAG BITS DONT MATCH - MISS-----");
                        for(int k=0; k<TOTAL_WAYS; k++)
                          begin
                            if(exit==0 && LRU[set_index][k] == 0 && valid[set_index][k] == 0)
                              begin
                                exit = 1;

                                if(trace_number == 0)
                                  begin
                                    MESI[set_index][k] = Exclusive;
                                    data_read = data_read+1;
                                    update_LRU(k);
				    
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k] = 0;
                                    if(test_mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Read from L2 <%0h>", trace_address);
                                        $display(" ");
                                      end
                                  end

                                else if(trace_number == 1)
                                  begin
                                    MESI[set_index][k] = Modified;
                                    data_write=data_write+1;
                                    update_LRU(k);
                                    TAG[set_index][k] = tag_index;
                                    valid[set_index][k] = 1;
                                    dirty[set_index][k]=1;
                                    if (first_write_through [set_index][k]==0)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("--------------Communication with L2--------------");
                                            $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", trace_address);
                                            $display("Data Cache : Write to L2 <%0h>", trace_address);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][k]=1;
                                      end
                                  end

                                else if(trace_number == 3)
                                  begin
                                    MESI[set_index][k] = Invalid;
                                    update_LRU(k); 
                                    valid[set_index][k] = 0;
                                  end

                                else if(trace_number == 4)
                                  begin
					if(test_mode == 1'b1)
                                          begin
                                   	 $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", trace_address);
                                  	end
				end
                              end
                          end
                      end

                    if((valid_bit_count==TOTAL_WAYS) && (exit == 0))
                      begin
                        data_miss = data_miss + 1;
                        $display("-----TAG BITS DONT MATCH - MISS-----");
                        for(int n=0; n<TOTAL_WAYS; n++)
                          begin
                            if(exit==0 && LRU [set_index][n] == 0)
                              begin
                                exit = 1;

                                if(trace_number == 0)
                                  begin
                                    MESI[set_index][n] = Exclusive;
                                    data_read = data_read+1;
                                    update_LRU(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n]=0;
                                    if(test_mode == 1'b1)
                                      begin
                                        $display("------Communication with L2------");
                                        $display("Data Cache : Write to L2 <%0h>", trace_address);
                                        $display("Data Cache : Read from L2 <%0h>", trace_address);
                                        $display(" ");
                                      end
                                  end

                                else if(trace_number == 1)
                                  begin
                                    MESI[set_index][n] = Modified;
                                    data_write=data_write+1;
                                    update_LRU(n);
                                    TAG[set_index][n] = tag_index;
                                    valid[set_index][n] = 1;
                                    dirty[set_index][n] = 1;
                                    if(test_mode == 1'b1)
                                      begin
                                        $display("---------------Communication with L2---------------");
                                        $display("Data Cache : Read for Ownership(RFO) from L2 <%0h>", trace_address);
                                        $display(" ");
                                      end

                                    if (first_write_through [set_index][n]==0)
                                      begin
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("-------Communication with L2-------");
                                            $display("Data Cache : Write to L2 <%0h>", trace_address);
                                            $display(" ");
                                          end
                                        first_write_through [set_index][n]=1;
                                      end
                                  end

                                else if(trace_number == 3)
                                  begin
                                    MESI[set_index][n] = Invalid;
                                    update_LRU(n); 
                                    valid[set_index][n] = 0;
                                  end

                                else if(trace_number == 4)
                                    $display("Cache for address <%0h> is miss, hence snooping an Read for Ownership(RFO) from other processor isn't possible.", trace_address);
                              end
                          end
                      end
                  end
                8:
                  begin
                    foreach (MESI [x,y])
                      begin
                        TAG[x][y] = 0;
                        MESI[x][y] = Invalid;
                        LRU[x][y] = 0;
                        first_write_through[x][y] = 0;
                        valid[x][y] = 0;
                        dirty[x][y] = 0;
                      end
                  end
                9:
		  begin
                    display_cache_contents();
                    display_report();
                  end
              endcase
            end
        end
      exit = 0;
      valid_bit_count = 0;
    end

  task update_LRU;
    input int a;
    for( int b =0 ; b < TOTAL_WAYS ; b++ )
      begin
        if(b != a)
          begin
            if (LRU [set_index] [b] > LRU [set_index] [a])
	       LRU [set_index] [b] = LRU [set_index] [b]-1;
	  end
      end
    LRU [set_index] [a] = TOTAL_WAYS-1;
  endtask

  task display_report;
    $display("-----DATA CACHE statistics-----");
    $display("Total Number of data reads  = %0d", data_read);
    $display("Total Number of data writes = %0d", data_write);
    $display("Total Number of data hits   = %0d", data_hit);
    $display("Total Number of data misses = %0d", data_miss);
    if ( data_hit + data_miss == 0 )
      $display ("Denominator cannot be zero (ie, data_miss and data_hit is zero)");
    else
      begin
        data_hit_ratio = ( data_hit * 100 / ( data_hit + data_miss ) );
        $display("DATA CACHE HIT ratio = %f", data_hit_ratio);
        $display(" ");
      end
  endtask

  task display_cache_contents;
    $display("--------------------------------------------------------------------------------Contents of DATA CACHE--------------------------------------------------------------------------------");
    $display("TRACE ADDRESS = %0h", trace_address);
    $display("SET NUMBER   = %0h", set_index);
    $display("TAG7 = %0h\t\t TAG6 = %0h\t\t TAG5 = %0h\t\t TAG4 = %0h\t\t TAG3 = %0h\t\t TAG2 = %0h\t\t TAG1 = %0h\t\t TAG0 = %0h", TAG[set_index][7], TAG[set_index][6], TAG[set_index][5], TAG[set_index][4], TAG[set_index][3], TAG[set_index][2], TAG[set_index][1], TAG[set_index][0]);
    $display("STATE7 = %0d\t STATE6 = %0d\t STATE5 = %0d\t STATE4 = %0d\t STATE3 = %0d\t STATE2 = %0d\t STATE1 = %0d\t STATE0 = %0d" ,MESI[set_index][7].name, MESI[set_index][6].name, MESI[set_index][5].name, MESI[set_index][4].name, MESI[set_index][3].name, MESI[set_index][2].name, MESI[set_index][1].name, MESI[set_index][0].name);
    $display("LRU7 = %0d\t\t LRU6 = %0d\t\t LRU5 = %0d\t\t LRU4 = %0d\t\t LRU3 = %0d\t\t LRU2 = %0d\t\t LRU1 = %0d\t\t LRU0 = %0d", LRU[set_index][7], LRU[set_index][6], LRU[set_index][5], LRU[set_index][4], LRU[set_index][3], LRU[set_index][2], LRU[set_index][1], LRU[set_index][0]);
    $display("DIRTY7 = %0d\t\t DIRTY6 = %0d\t\t DIRTY5 = %0d\t\t DIRTY4 = %0d\t\t DIRTY3 = %0d\t\t DIRTY2 = %0d\t\t DIRTY1 = %0d\t\t DIRTY0 = %0d", dirty[set_index][7], dirty[set_index][6], dirty[set_index][5], dirty[set_index][4], dirty[set_index][3], dirty[set_index][2], dirty[set_index][1], dirty[set_index][0]);
    $display("VALID7 = %0d\t\t VALID6 = %0d\t\t VALID5 = %0d\t\t VALID4 = %0d\t\t VALID3 = %0d\t\t VALID2 = %0d\t\t VALID1 = %0d\t\t VALID0 = %0d", valid[set_index][7], valid[set_index][6], valid[set_index][5], valid[set_index][4], valid[set_index][3], valid[set_index][2], valid[set_index][1], valid[set_index][0]);
    $display(" ");
  endtask

endmodule


module instruction_cache( clock, reset, trace_number, trace_address , instruction_read, instruction_write, instruction_hit, instruction_miss, test_mode, a);

  input logic test_mode;
  input bit a;
  input logic clock;
  input logic reset;
  input logic [3:0]  trace_number;       								// from trace file
  input logic [31:0] trace_address;	  								// Address from trace file

  output real instruction_read, instruction_write, instruction_hit, instruction_miss;

  typedef enum {Modified, Exclusive, Shared, Invalid} state;

  parameter ADDR_BITS = 32;										// Number of Address Bits
  parameter TOTAL_SETS = 16*1024;									// Total number of TOTAL_SETS
  parameter TOTAL_WAYS = 4;										// Total number of TOTAL_WAYS
  parameter CACHE_LINE_SIZE = 64; 									// Width of cache line in bytes
  parameter BYTE_OFFSET_BITS = $clog2 (CACHE_LINE_SIZE);						// Number of byte offset bits
  parameter SET_SELECT_BITS = $clog2 (TOTAL_SETS);							// Number of byte offset bits
  parameter TAG_BITS = ADDR_BITS - (BYTE_OFFSET_BITS + SET_SELECT_BITS);				// Number of TAG bits
  parameter LRU_bits = $clog2 (TOTAL_WAYS);								// Number of LRU bits

  real instruction_hit_ratio; 									

  logic [LRU_bits-1:0] LRU[TOTAL_SETS-1:0][TOTAL_WAYS-1:0] = {default:2'b00};				// LRU bits per cache line - Default set to 00
  logic [TAG_BITS-1:0] TAG[TOTAL_SETS-1:0][TOTAL_WAYS-1:0];						// TAG bits per cache line
  bit valid[TOTAL_SETS-1:0][TOTAL_WAYS-1:0];
  bit first_write_through [TOTAL_SETS -1: 0] [TOTAL_WAYS-1:0];

  state MESI[TOTAL_SETS-1 : 0][TOTAL_WAYS-1:0];

  int exit=0;
  int valid_bit_count = 0;

  logic [BYTE_OFFSET_BITS- 1 :0] byte_offset;
  logic [SET_SELECT_BITS-1 :0] set_index;
  logic [TAG_BITS -1 :0] tag_index;

  assign byte_offset = trace_address [BYTE_OFFSET_BITS-1 :0];
  assign set_index = trace_address [BYTE_OFFSET_BITS + SET_SELECT_BITS-1 :BYTE_OFFSET_BITS];
  assign tag_index = trace_address [ADDR_BITS-1: BYTE_OFFSET_BITS + SET_SELECT_BITS];
 
  always@(a)
  begin
  display_cache_contents();
  display_report();
  end 
  
  always_ff @(posedge clock, posedge reset)
    begin
      if(reset)
        begin
          instruction_read = 0;
          instruction_write = 0;
          instruction_hit = 0;
          instruction_miss = 0;
          foreach (MESI [x,y])
            begin
              TAG[x][y]=0;
              MESI[x][y] = Invalid;
              LRU[x][y] = 2'b00;
              first_write_through[x][y] = 0;
              valid[x][y] = 0;
            end
        end
      else
        begin
          if (trace_number != 0 && trace_number != 1 && trace_number != 3 && trace_number != 4)
            begin

              case(trace_number)
                2:
                  begin
                    exit = 0;
                    for(int m=0 ; m<TOTAL_WAYS; m++)
                      begin
                        if(valid[set_index][m] == 1)
                          valid_bit_count = valid_bit_count + 1;

                        ///////////////************************************ IF TAG BITS MATCH - HIT *********************************/////////////////////
                        if((exit==0 && valid[set_index][m] == 1) && ( TAG[set_index][m] == tag_index))
                          begin
                            exit = 1;
                            instruction_hit = instruction_hit+1;
                            $display("------TAG BITS MATCH, HENCE HIT-------");

                            //////////////////////////////--------------------MODIFIED STATE-----------------------///////////////////////////////////

                            if (MESI[set_index][m] == Modified)
                              begin
                                if (trace_number == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Modified;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
                              end

                            //////////////////////////////--------------------EXCLUSIVE STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Exclusive)
                              begin
                                if (trace_number == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
                              end

                            //////////////////////////////--------------------SHARED STATE-----------------------///////////////////////////////////

                            else if (MESI[set_index][m] == Shared)
                              begin
                                if (trace_number == 2) 				// Read  request to L1 data cache
                                  begin
                                    MESI[set_index][m] = Shared;
                                    instruction_read = instruction_read+1;
                                    update_LRU(m);
                                  end
			      end 
                          end

                        ///////////////************************************ IF TAGS BITS DON'T MATCH - MISS *********************************/////////////////////


                        if((valid_bit_count < TOTAL_WAYS) && (exit == 0))
                          begin
                            instruction_miss = instruction_miss+1;
                            $display("------TAG BITS DONT MATCH, HENCE MISS-------");
                            for(int k=0; k<TOTAL_WAYS; k++)
                              begin
                                if(exit==0 && LRU[set_index][k] == 0 && valid[set_index][k] == 0)
                                  begin
                                    exit = 1;

                                    if(trace_number == 2)
                                      begin
                                        MESI[set_index][k] = Exclusive;
                                        instruction_read = instruction_read+1;
                                        update_LRU(k);
                                        TAG[set_index][k] = tag_index;
                                        valid[set_index][k] = 1;
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("--Communication with L2--");
                                            $display("Read from L2 <%0h>", trace_address);
                                            $display(" ");
                                          end
                                      end
                                  end
                              end
                          end

                        if((valid_bit_count==TOTAL_WAYS) && (exit == 0))
                          begin
                            instruction_miss = instruction_miss+1;
                            $display("------TAG BITS DONT MATCH, HENCE MISS-------");
                            for(int n=0; n<TOTAL_WAYS; n++)
                              begin
                                if(exit==0 && LRU [set_index][n] == 0)
                                  begin
                                    exit = 1;

                                    if(trace_number == 2)
                                      begin
                                        MESI[set_index][n] = Exclusive;
                                        instruction_read = instruction_read+1;
                                        update_LRU(n);
                                        TAG[set_index][n] = tag_index;
                                        valid[set_index][n] = 1;
                                        if(test_mode == 1'b1)
                                          begin
                                            $display("--Communication with L2--");
                                            $display("Write to L2 <%0h>", trace_address);
                                            $display("Read from L2 <%0h>", trace_address);
                                            $display(" ");
                                          end
                                      end
                                  end
                              end
                          end
                      end
                  end

                8:

                  begin
                    foreach (MESI [x,y])
                      begin
                        TAG[x][y] = 0;
                        MESI[x][y] = Invalid;
                        LRU[x][y] = 0;
                        first_write_through[x][y] = 0;
                        valid[x][y] = 0;
                      end
                  end

                9:

                  begin
                    display_cache_contents();
                    display_report();
                  end
              endcase
            end
        end
      exit=0;
      valid_bit_count=0;
    end

task update_LRU;
    input int a;
    for( int b =0 ; b < TOTAL_WAYS ; b++ )
      begin
        if(b != a)
          begin
            if (LRU [set_index] [b] > LRU [set_index] [a])
	       LRU [set_index] [b] = LRU [set_index] [b]-1;
          end
      end
    LRU [set_index] [a] = TOTAL_WAYS-1;
  endtask

  task display_report;
    $display("---INSTRUCTION CACHE statistics---");
    $display("Total Number of instruction reads  = %0d", instruction_read);
    $display("Total Number of instruction writes = %0d", instruction_write);
    $display("Total Number of instruction hits   = %0d", instruction_hit);
    $display("Total Number of instruction misses = %0d", instruction_miss);
    if (instruction_hit+instruction_miss == 0)
      $display ("Denominator cannot be zero (ie, data_miss and data_hit is zero)");
    else
      begin
        instruction_hit_ratio = ( instruction_hit * 100 / ( instruction_hit + instruction_miss ) );
        $display("Instruction Cache HIT ratio = %f", instruction_hit_ratio);
        $display(" ");
      end
  endtask

  task display_cache_contents;
    $display("-------------------------------Contents of INSTRUCTION CACHE-------------------------------");
    $display("TRACE Address = %0h", trace_address);
    $display("SET NUMBER          = %0h", set_index);
    $display("TAG3 = %0h\t\t TAG2 = %0h\t\t TAG1 = %0h\t\t TAG0 = %0h", TAG[set_index][3], TAG[set_index][2], TAG[set_index][1], TAG[set_index][0]);
    $display("STATE3 = %0d\t STATE2 = %0d\t STATE1 = %0d\t STATE0 = %0d" , MESI[set_index][3].name, MESI[set_index][2].name, MESI[set_index][1].name, MESI[set_index][0].name);
    $display("LRU3 = %0d\t\t LRU2 = %0d\t\t LRU1 = %0d\t\t LRU0 = %0d", LRU[set_index][3], LRU[set_index][2], LRU[set_index][1], LRU[set_index][0]);
    $display("VALID3 = %0d\t\t VALID2 = %0d\t\t VALID1 = %0d\t\t VALID0 = %0d", valid[set_index][3], valid[set_index][2], valid[set_index][1], valid[set_index][0]);
    $display(" ");
  endtask

endmodule
