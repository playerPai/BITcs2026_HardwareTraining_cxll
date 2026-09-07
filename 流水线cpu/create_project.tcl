# Create the pipeline CPU Vivado project (simulation-oriented).
# Usage: first cd into this folder (the one containing PipelineCPU.v), then:
#   Tcl Console:  source create_project.tcl
#   or batch:     vivado -mode batch -source create_project.tcl
# NOTE: relative paths are used on purpose - always run from this folder.
set proj_dir PipelineProject

# Same FPGA part as the single-cycle project (xc7a35tcpg236-1)
create_project pipeline_cpu $proj_dir -part xc7a35tcpg236-1 -force

add_files -fileset sources_1 PipelineCPU.v
add_files -fileset sim_1     tb_pipeline.v

set_property top pipeline_top [current_fileset]
set_property top tb_pipeline  [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "==============================================="
puts " Project created at: $proj_dir"
puts " Open  PipelineProject/pipeline_cpu.xpr  in Vivado GUI,"
puts " then Run Behavioral Simulation (tb_pipeline is the top)."
puts " NOTE: imem loads inst.mem from the simulation working dir."
puts " Use  switch_test_pipeline.ps1  to change test programs."
puts "==============================================="
