import subprocess
import csv

def write_power_tcl(dumpfile: str, report_file: str, filename: str = "power.tcl"):
    tcl_content = f"""\
set power_enable_analysis true
set power_analysis_mode time_based
set search_path "$search_path mapped lib cons rtl sim"

set target_library /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/timing/db/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_TT_0P80V_0P00V_0P00V_0P00V_25C.db
set link_library "* $target_library"

# Read the synthesized netlist
read_verilog top_mapped.v
current_design top
link_design

# Define simulation environment
set_units -time ps -resistance kOhm -capacitance fF -voltage V -current mA
create_clock -period 10000 -name CLK [get_ports i_clk]

# Read activity dump
read_vcd "{dumpfile}" -strip_path "tb_top/dut"

# Perform power analysis
check_power
set_power_analysis_options -waveform_format fsdb -waveform_output vcd
update_power

# Generate power report
report_power -hierarchy > {report_file}
"""
    with open(filename, "w") as f:
        f.write(tcl_content)


def generate_simv_command(
    conv_mode,
    input_size,
    input_channels,
    output_channels,
    output_size,
    stride,
    precision,
    layer_identifier,
    input_file,
    weight_file,
    mapped_file,
    dump_file
):
    p_mode = 0
    if precision == 4:
        p_mode = 1
    elif precision == 2:
        p_mode = 2

    cmd = (
        f"./simv "
        f"+CONV_MODE={conv_mode} "
        f"+INPUT_SIZE={input_size} "
        f"+INPUT_CHANNELS={input_channels} "
        f"+OUTPUT_CHANNELS={output_channels} "
        f"+OUTPUT_SIZE={output_size} "
        f"+STRIDE={stride} "
        f"+PRECISION={p_mode} "
        f"+LAYER_IDENTIFIER={layer_identifier} "
        f'+INPUT_FILE="{input_file}" '
        f'+WEIGHT_FILE="{weight_file}" '
        f'+MAPPED_FILE="{mapped_file}" '
        f'+DUMP_FILE="{dump_file}" '
    )
    return cmd


def main():
    csv_path = "vww/metadata.csv"

    spad_data_width = [32]
    addr_width = [13]
    dimension = [8]
    depth = [16]

    sim_command = "vcs -f ../filelist.txt -full64 -sverilog -debug_pp"
    subprocess.run(sim_command, shell=True)

    with open(csv_path, mode='r') as file:
        reader = csv.DictReader(file)
        for row in reader:
            identifier = row['Identifier']
            h = int(row['H/W'])
            w = int(row['H/W'])
            c_i = int(row['C'])
            c_o = int(row['Oc'])
            stride = int(row['Stride'])
            type = row['Type']
            
            # 0 for Pointwise and 1 for Depthwise
            conv_mode = 0 if type == "P" else 1

            out_size = h if type == "P" else ((h-3) // stride) + 1
            i_filename = f"vww/{spad_data_width}_bits/inputs/{identifier}.txt"
            w_filename = f"vww/{spad_data_width}_bits/weights/{identifier}.txt"
            mapped_file = f"data/sdf/{dimension}_{depth}_{spad_data_width}_mapped.sdf"


            for precision in [2, 4, 8]:
                dump_file = f"{dimension}_{depth}_{spad_data_width}_{identifier}_{precision}.dump"
                tb_cmd = generate_simv_command(
                    conv_mode,
                    h,
                    c_i,
                    c_o,
                    out_size,
                    stride,
                    precision,
                    identifier,
                    i_filename,
                    w_filename,
                    mapped_file,
                    dump_file
                )

                #print(tb_cmd)
                
                print(f"Processing {identifier} with {precision}-bit precision and dimensions {dimension}x{dimension}x{depth} and SPAD bus width {spad_data_width}\n")
                subprocess.run(tb_cmd, shell=True)

                with open("simulation_log.txt", "a") as log_file:
                    log_file.write(f"Finished {identifier} with {precision}-bit precision and dimensions {dimension}x{dimension}x{depth} and SPAD bus width {spad_data_width}\n")

                report_file = f"logs/{dimension}_{depth}_{spad_data_width}_{identifier}_{precision}_power.rpt"
                write_power_tcl(dump_file, report_file)

                cmd = f"dc_shell -f power.tcl -output_log_file logs/{dimension}_{depth}_{spad_data_width}_{identifier}_{precision}_power.log"

if __name__ == "__main__":
    main()
