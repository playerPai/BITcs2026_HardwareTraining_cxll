# Add the UART integration files to an already-created Vivado project.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir project liucode_project.xpr]

set uart_rtl [file join $script_dir rtl uart_mmio.v]
set display_rtl [file join $script_dir rtl display_sequence_mmio.v]
set uart_mem [file join $script_dir programs uart_sort_demo.mem]
set uart_tb  [file join $script_dir sim tb_uart_mmio.v]
set soc_tb   [file join $script_dir sim tb_cpu_uart.v]

if {[llength [get_files -quiet [file tail $uart_rtl]]] == 0} {
    add_files -fileset sources_1 -norecurse $uart_rtl
}
if {[llength [get_files -quiet [file tail $display_rtl]]] == 0} {
    add_files -fileset sources_1 -norecurse $display_rtl
}
if {[llength [get_files -quiet [file tail $uart_mem]]] == 0} {
    add_files -fileset sources_1 -norecurse $uart_mem
    set_property file_type {Memory Initialization Files} \
        [get_files [file tail $uart_mem]]
}
foreach tb_file [list $uart_tb $soc_tb] {
    if {[llength [get_files -quiet [file tail $tb_file]]] == 0} {
        add_files -fileset sim_1 -norecurse $tb_file
    }
}

set_property top top [get_filesets sources_1]
set_property top tb_cpu_uart [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "UART_PROJECT_UPDATE: COMPLETE"
close_project
