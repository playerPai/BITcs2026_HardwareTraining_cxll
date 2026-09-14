# Run a selected simulation top (defaults to the top saved in the project).
# Examples:
#   vivado -mode batch -source sim_check.tcl
#   vivado -mode batch -source sim_check.tcl -tclargs tb_top
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
if {[llength $argv] > 0} {
    set_property top [lindex $argv 0] [get_filesets sim_1]
    update_compile_order -fileset sim_1
}
launch_simulation
run all
close_sim
