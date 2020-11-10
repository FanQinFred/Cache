onbreak {quit -force}
onerror {quit -force}

asim -t 1ps +access +r +m+axi_crossbar_1x2 -L xpm -L generic_baseblocks_v2_1_0 -L axi_infrastructure_v1_1_0 -L axi_register_slice_v2_1_20 -L fifo_generator_v13_2_5 -L axi_data_fifo_v2_1_19 -L axi_crossbar_v2_1_21 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.axi_crossbar_1x2 xil_defaultlib.glbl

do {wave.do}

view wave
view structure

do {axi_crossbar_1x2.udo}

run -all

endsim

quit -force
