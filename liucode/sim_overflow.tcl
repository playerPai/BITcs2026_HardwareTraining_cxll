# sim_overflow.tcl
# 一键运行溢出判断仿真（流水线 tb_overflow + 单周期 tb_overflow_sc）。
# 用法:
#   vivado -mode batch -source sim_overflow.tcl
# 说明:
#   - 自动把 liucode/sim 下的两个 tb 加入 sim_1（若尚未加入）
#   - 自动把 overflow_test.mem 复制到 xsim 运行目录
#   - 依次以 tb_overflow / tb_overflow_sc 为 top 运行，跑完恢复原 top
set script_dir [file dirname [file normalize [info script]]]
puts "===> ovf sim: script_dir = $script_dir"

# 工程尚不存在（队友全新 clone）时先一键重建
set xpr_path [file join $script_dir project liucode_project.xpr]
if {[file exists $xpr_path]} {
    open_project $xpr_path
} else {
    puts "===> 未找到工程，先运行 create_project.tcl 重建"
    source [file join $script_dir create_project.tcl]
}

# 1) 确保 tb 文件在 sim_1 fileset 中
foreach tb [list tb_overflow.v tb_overflow_sc.v] {
    set tb_path [file join $script_dir sim $tb]
    if {[llength [get_files -quiet $tb]] == 0} {
        add_files -fileset sim_1 -norecurse $tb_path
        puts "===> added $tb to sim_1"
    } else {
        puts "===> $tb already in project"
    }
}

# 2) 确保 overflow_test.mem 在 xsim 运行目录（$readmemh 相对路径）
set mem_src [file join $script_dir programs overflow_test.mem]
set xsim_dir [file join $script_dir project liucode_project.sim sim_1 behav xsim]
file mkdir $xsim_dir
file copy -force $mem_src [file join $xsim_dir overflow_test.mem]
puts "===> overflow_test.mem copied to $xsim_dir"

# 3) 跑流水线版
set_property top tb_overflow [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
close_sim

# 4) 跑单周期版
set_property top tb_overflow_sc [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
close_sim

# 5) 恢复默认 top（与 create_project.tcl 一致）
set_property top tb_cpu_performance [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "===> ovf sim done. tops restored to tb_cpu_performance."