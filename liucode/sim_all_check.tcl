# Run all five CPU programs, then restore tb_top as the default simulation top.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
set_property top tb_cpu_all [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
run all
close_sim
set_property top tb_top [get_filesets sim_1]
update_compile_order -fileset sim_1
