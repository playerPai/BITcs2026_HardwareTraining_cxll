# Run with: vivado -mode batch -source create_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file join $script_dir project]

create_project liucode_project $project_dir -part xc7a35tcsg324-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [glob [file join $script_dir rtl *.v]]
add_files -fileset constrs_1 -norecurse [file join $script_dir constraints ees338.xdc]

foreach mem_file [glob [file join $script_dir programs *.mem]] {
    add_files -fileset sources_1 -norecurse $mem_file
    set_property file_type {Memory Initialization Files} [get_files [file tail $mem_file]]
}

add_files -fileset sim_1 -norecurse [glob [file join $script_dir sim *.v]]
set_property top top [get_filesets sources_1]
set_property top tb_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created: [file join $project_dir liucode_project.xpr]"
