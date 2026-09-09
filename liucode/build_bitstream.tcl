# Build the synthesizable board top through bitstream generation.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
set_property top top [get_filesets sources_1]
set_property strategy Performance_Explore [get_runs impl_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set run_status [get_property STATUS [get_runs impl_1]]
puts "BITSTREAM_STATUS: $run_status"
if {![string match "*Complete*" $run_status]} {
    error "Bitstream generation did not complete successfully"
}
