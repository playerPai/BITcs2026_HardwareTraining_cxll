# Run the default end-to-end simulation from the generated project.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]
launch_simulation
run all
close_sim
