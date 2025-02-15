vlib work
vlog -reportprogress 300 -work work data_cache.sv +acc
vlog -reportprogress 300 -work work instruction_cache.sv +acc
vsim -voptargs="+acc" work.cache_simulator_testbench +Tracefile=test.txt
run -all