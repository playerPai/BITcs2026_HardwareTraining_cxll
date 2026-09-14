综合单周期/五级流水线CPU与下板代码
用vivado打开.xpr文件:project/liucode_project.xpr
性能测试在sim/tb_cpu_performance.v的USER SETTING处切换single_cycle/pipeline
仿真默认顶层为tb_cpu_performance；下板综合顶层必须为top
tb_top用于仿真验证CPU到数码管的完整通路
上板默认CPU为pipeline；可在rtl/top.v中切换CPU_TYPE
UART集成演示默认115200/8N1，N5为接收、T4为发送
按S8复位后终端显示READY；发送12 3 105 1并附加回车，返回COUNT:4和SORTED:1 3 12 105
数码管先显示数量4，再依次循环显示1、3、12、105；最多16个非负整数
等待输入时数码管稳定显示0；S8释放稳定20ms后CPU才启动，避免复位乱码
UART演示必须保持CPU_STEP_CYCLES=1
tb_uart_mmio验证UART IP；tb_cpu_uart完成CPU+MMIO+UART端到端自动比对
需手动更换测试文件
板上显示每个指令运行后得到的结果
