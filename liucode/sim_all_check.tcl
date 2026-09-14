# Run all five single-cycle CPU programs, then restore the performance top.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
set_property top tb_cpu_all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
close_sim
set_property top tb_cpu_performance [get_filesets sim_1]
update_compile_order -fileset sim_1
