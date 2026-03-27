# Set Current Directory to your PS-CNN repo
set SRCDIR "C:/Users/Aaron/Documents/EEE196/ps-cnn-accelerator"
cd $SRCDIR

# -------------------------
# 2. Add RTL source files
# -------------------------
# Add all Verilog/SystemVerilog files in rtl folder
add_files -scan_for_includes ./rtl

# Optional: Add additional memory files if required
# add_files ./memory/some_memory_file.mem

# -------------------------
# 3. Add constraints
# -------------------------
# Arty A7-35T constraints
add_files -fileset constrs_1 ./constraints/arty7_a35t.xdc
set_property target_constrs_file [format %s%s $SRCDIR "/constraints/arty7_a35t.xdc"] [current_fileset -constrset]

# -------------------------
# 4. Add simulation/testbench files (optional)
# -------------------------
# Create simulation fileset
create_fileset -simset sim_1
add_files -fileset sim_1 ./sim/tb_top.v
# If you have other testbenches, add them similarly:
# add_files -fileset sim_1 ./sim/tb_other.v

# Set the top module for simulation
set_property top tb_top [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# -------------------------
# 5. Set top module for synthesis
# -------------------------
# Replace 'top_module_name' with your actual top module from RTL
# set_property top top_module_name [current_fileset], to do this, check what the module name actuall is in the code
set_property top top [current_fileset]

# -------------------------
# 6. Add IP files if any
# -------------------------
# If your PS-CNN repo uses Xilinx IP cores, you can add them like this:
# add_files { ./vivado-ip-src/some_ip/some_ip.xci }

# -------------------------
# 7. Synthesis and Implementation
# -------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

write_bitstream -force "$SRCDIR/ps_cnn_accel.bit"

puts "PS-CNN p
