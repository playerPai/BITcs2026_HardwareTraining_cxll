# Build the current source tree in-process and place stable artifacts in output/.
# Run from liucode with:
#   vivado -mode batch -source build_bitstream.tcl
set script_dir [file dirname [file normalize [info script]]]
set output_dir [file join $script_dir output]
file mkdir $output_dir

create_project -in_memory -part xc7a35tcsg324-1
set_property target_language Verilog [current_project]

foreach mem_file [glob [file join $script_dir programs *.mem]] {
    read_mem $mem_file
}
foreach rtl_file [glob [file join $script_dir rtl *.v]] {
    read_verilog $rtl_file
}
read_xdc [file join $script_dir constraints ees338.xdc]

synth_design -top top -part xc7a35tcsg324-1
opt_design
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore

set timing_file [file join $output_dir uart_sort_pipeline_100mhz_timing.rpt]
set route_file [file join $output_dir uart_sort_pipeline_100mhz_route.rpt]
set drc_file [file join $output_dir uart_sort_pipeline_100mhz_drc.rpt]
set bit_file [file join $output_dir uart_sort_pipeline_100mhz.bit]
report_timing_summary -file $timing_file
report_route_status -file $route_file
report_drc -file $drc_file

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set worst_slack [get_property SLACK $worst_path]
puts "POST_ROUTE_WNS_NS: $worst_slack"
if {$worst_slack < 0.0} {
    error "100 MHz timing requirement was not met"
}

write_bitstream -force $bit_file
puts "BITSTREAM_STATUS: COMPLETE"
puts "BITSTREAM_FILE: $bit_file"
