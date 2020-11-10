onbreak {quit -force}
onerror {quit -force}

asim -t 1ps +access +r +m+axi_clock_converter -L xpm -L axi_infrastructure_v1_1_0 -L fifo_generator_v13_2_5 -L axi_clock_converter_v2_1_19 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.axi_clock_converter xil_defaultlib.glbl

do {wave.do}

view wave
view structure

do {axi_clock_converter.udo}

run -all

endsim

quit -force
