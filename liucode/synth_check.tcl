# Optional synthesis check. Run from the liucode directory.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set run_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS: $run_status"
if {![string match "*Complete*" $run_status]} {
    error "Synthesis did not complete successfully"
}
