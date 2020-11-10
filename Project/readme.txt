|--	doc									cache实验指导书；类sram接口相关文档。
|
|--	soc_axi_lite_loongson				带有直接映射写直达cache的Soc环境。需要同学们自己实现cache		
	|
	|--	rtl								Soc源代码及相关IP核
	|								
	|--	run_vivado						vivado工程
	|
	|--	testbench						仿真测试头文件
	|
	|-- ohhhh.wcfg						调试必备，提供的基础波形图。
|
|-- soft								soft为运行的软件环境，已经编译出coe等文件，不用修改；详情请参考文件内部readme_first.txt。
|
|--	traces								调试必备，traces下包含为仿真时进行对比的trace文件，不用修改


PS：
	soc_axi_lite_loonson包含vivado项目，双击soc_axi_lite_loongson\run_vivado\mycpu_prj1下的mycpu.xpr即可打开vivado工程(2019.3版本)，已经配置好soc环境。

	soc_axi_lite_loongson\rtl\myCPU包含CPU代码，替换其中的cache模块（i_cache.v和d_cache.v）后直接仿真即可。