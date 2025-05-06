import subprocess
import csv

def write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth):
    header = f"""
    `define DATA_WIDTH {8}
    `define SPAD_DATA_WIDTH {spad_data_width}
    `define SPAD_N {spad_data_width // 8}
    `define ADDR_WIDTH {addr_width}
    `define ROWS {rows}
    `define COLUMNS {cols}
    `define MISO_DEPTH {miso_depth}
    `define MPP_DEPTH {mpp_depth}"""

    with open("../rtl/global.svh", "w") as file:
        file.write(header)

    print("global.svh file has been generated.")


def write_compile_tcl(dimension, spad_width):
    """
    Generate a Synopsys Design Compiler script (compile.tcl)
    with the given array dimension and SPAD width.
    """
    tcl_template = """set search_path "$search_path mapped lib cons rtl"
set target_library /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/timing/db/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_TT_0P80V_0P00V_0P00V_0P00V_25C.db
set link_library "* $target_library"

read_file ./rtl/ -autoread -recursive -format sverilog -top top
current_design top
link
check_design > logs/{dimension}_{spad_width}_check_design.log
source timing.con
check_timing > logs/{dimension}_{spad_width}_check_timing.log
compile
report_constraint -all_violators > logs/{dimension}_{spad_width}_constraint_report.log
report_area -hierarchy > logs/{dimension}_{spad_width}_area_report.log
report_timing > logs/{dimension}_{spad_width}_timing_report.log
report_power -hierarchy > logs/{dimension}_{spad_width}_power_report.log
write_file -format verilog -hierarchy -output mapped/{dimension}_{spad_width}_mapped.v
write_file -format ddc -hierarchy -output mapped/{dimension}_{spad_width}_mapped.ddc
write_sdf mapped/{dimension}_{spad_width}_mapped.sdf
write_sdc mapped/{dimension}_{spad_width}_mapped.sdc
quit
"""
    with open("compile.tcl", "w") as f:
        f.write(tcl_template.format(dimension=dimension, spad_width=spad_width))


def extract_slack(timing_report_path):
    """
    Extracts the 'slack (MET)' value from a timing report file.
    Returns the float value of slack or None if not found.
    """
    try:
        with open(timing_report_path, 'r', encoding='utf-8') as f:
            for line in f:
                if "slack (MET)" in line:
                    return float(line.strip().split()[-1])
    except Exception as e:
        print(f"Error reading timing report {timing_report_path}: {e}")
    return None

def extract_area_data(area_log_path):
    """
    Extracts area data and component-level breakdown from the area report.

    Parameters:
        area_log_path (str): Path to the area report log.
        d (int): Systolic array dimension.
        spad_data_width (int): Width of SPAD.
        components (list): List of (name, identifier) tuples.

    Returns:
        list: Row of area data including total and per-component info.
    """
    components = [
        ("Controller", "top_controller_inst"),
        ("Input SPAD", "ir_inst/ir_spad"), 
        ("Input Router", "ir_inst"), 
        ("Weight SPAD", "wr_inst/wr_spad"),
        ("Weight Router", "wr_inst"),
        ("Output Router", "or_inst"),
        ("Output SPAD", "or_spad"),
        ("Systolic Array", "systolic_array_inst"),
    ]

    result_row = []
    spad_cache = {}

    try:
        with open(area_log_path, 'r', encoding='utf-8') as file:
            area_data = file.readlines()
            combi_area = float(area_data[21].split()[-1])
            buffinv_area = float(area_data[22].split()[-1])
            noncombi_area = float(area_data[23].split()[-1])
            total_area = float(area_data[27].split()[-1])

            result_row = [combi_area, buffinv_area, noncombi_area, total_area]

            for name, identifier in components:
                area_info = next((line.strip() for line in area_data if identifier in line), None)
                if area_info:
                    text = area_info.split()
                    area = float(text[1])
                    percent = float(text[2])

                    if name in ["Input SPAD", "Weight SPAD"]:
                        spad_cache[name] = (area, percent)

                    if name == "Input Router" and "Input SPAD" in spad_cache:
                        area -= spad_cache["Input SPAD"][0]
                        percent -= spad_cache["Input SPAD"][1]

                    if name == "Weight Router" and "Weight SPAD" in spad_cache:
                        area -= spad_cache["Weight SPAD"][0]
                        percent -= spad_cache["Weight SPAD"][1]

                    result_row.extend([area, percent])
                else:
                    result_row.extend(["N/A", "N/A"])
                
            return result_row

    except Exception as e:
        print(f"Error reading area report: {area_log_path}: {e}")

    return None

def extract_power_data(power_report_path):
    """
    Extracts power data from a Synopsys power report.

    Returns a list: [internal_power_mw, switching_power_mw, leakage_power_mw, total_power_mw]
    or ['N/A', ...] if extraction fails.
    """
    try:
        with open(power_report_path, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip().startswith("Total"):
                    parts = line.strip().split()
                    internal = convert_to_mw(parts[1], parts[2])
                    switching = convert_to_mw(parts[3], parts[4])
                    leakage = convert_to_mw(parts[5], parts[6])
                    total = convert_to_mw(parts[7], parts[8])
                    return [internal, switching, leakage, total]
    except Exception as e:
        print(f"Error reading power report {power_report_path}: {e}")
    
    return None

def convert_to_mw(value_str, unit_str):
    """
    Converts a power string with unit to mW.
    e.g., "460.5394", "uW" -> 0.4605394
          "10.0710", "mW" -> 10.0710
    """
    value = float(value_str)
    if unit_str.lower() == 'uw':
        return value / 1000.0
    elif unit_str.lower() == 'mw':
        return value
    else:
        raise ValueError(f"Unknown power unit: {unit_str}")

def main():
    # 32-bit, 64-bit, 128-bit, 256-bit, 512-bit
    spad_sizing = [(32,13), (64,12), (128,11), (256,10), (512,9)]
    dimensions = [16, 32, 64, 128]

    components = [
        ("Controller", "top_controller_inst"),
        ("Input SPAD", "ir_inst/ir_spad"), 
        ("Input Router", "ir_inst"), 
        ("Weight SPAD", "wr_inst/wr_spad"),
        ("Weight Router", "wr_inst"),
        ("Output Router", "or_inst"),
        ("Output SPAD", "or_spad"),
        ("Systolic Array", "systolic_array_inst"),
    ]

    # Prepare CSV headers
    headers = ["Dimension", "SPAD_Width", "Combinational Area", "Buffer/Inverter Area", "Noncombinational Area", "Total Area"]
    for name, _ in components:
        headers.append(f"{name} Area")
        headers.append(f"{name} %")
    
    headers.append("Slack (MET)")
    headers.extend(["Internal Power (mW)", "Switching Power (mW)", "Leakage Power (mW)", "Total Power (mW)"])

    # Write CSV
    with open("synthesis_area_report.csv", mode="w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(headers)

        for d in dimensions:
            for spad_data_width, addr_width in spad_sizing:
                rows = cols = miso_depth = d
                mpp_depth = 9

                write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth)
                write_compile_tcl(d, spad_data_width)

                # Run synthesis
                sim_command = "dc_shell -f compile.tcl -output_log_file logs/compile.log"
                subprocess.run(sim_command, shell=True)
                print(f"Synthesis completed for {d}x{d}x{d} with SPAD width {spad_data_width}")

                area_log_path = f"logs/{d}_{spad_data_width}_area_report.log"
                area_data = extract_area_data(area_log_path)

                slack_log_path = f"logs/{d}_{spad_data_width}_timing_report.log"
                slack_data = extract_slack(slack_log_path)

                power_log_path = f"logs/{d}_{spad_data_width}_power_report.log"
                power_data = extract_power_data(power_log_path)

                row = [d, spad_data_width] + area_data + [slack_data] + power_data
                writer.writerow(row)
                print("Row written to CSV:", row)
                print(f"Report extracted for {d}x{d}x{d} with SPAD width {spad_data_width}")

if __name__ == "__main__":
    main()