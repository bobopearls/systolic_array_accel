import numpy as np
import tflite
import os
import math

# 1. Hardware Parameters
SPAD_DATA_WIDTH = 32
SPAD_N = SPAD_DATA_WIDTH // 8  # 4 bytes per line

def sram_hex_to_mem_format(data, filename):
    flat_data = data.flatten().view(np.int8)
    with open(filename, 'w') as f:
        for i in range(0, len(flat_data), SPAD_N):
            group = flat_data[i:i + SPAD_N]
            if len(group) < SPAD_N:
                group = np.pad(group, (0, SPAD_N - len(group)), mode='constant')
            hex_string = ''.join(f"{int(x) & 0xff:02x}" for x in reversed(group))
            f.write(hex_string + '\n')

# --- NEW: Helper Functions for Quantization ---
def get_quantization_params(tensor):
    """Extracts scale and zero point lists from a TFLite tensor."""
    quant = tensor.Quantization()
    if quant is None:
        return None, None
    scales = [quant.Scale(i) for i in range(quant.ScaleLength())]
    zero_points = [quant.ZeroPoint(i) for i in range(quant.ZeroPointLength())]
    return scales, zero_points

def quantize_multiplier(real_multiplier, precision=16):
    """
    Converts a floating point multiplier to a 'precision'-bit fixed-point 
    multiplier and a shift value.
    """
    if real_multiplier == 0.0:
        return 0, 0
    
    # frexp splits a float into a mantissa in [0.5, 1.0) and an exponent
    significand, exponent = math.frexp(real_multiplier)
    
    # Map the [0.5, 1.0) mantissa to a precision-bit integer
    q = int(round(significand * (1 << precision)))
    
    # Handle rounding overflow edge case
    if q == (1 << precision):
        q //= 2
        exponent += 1
    # exponent here is negative, we return the positive value for right shift
    
    return q, -exponent

# 2. Load Model
model_path = r"C:\Users\Aaron\Documents\EEE196\person_detect.tflite"
destination_path = r"C:\Users\Aaron\Documents\EEE196\person_tflite_weights"
with open(model_path, 'rb') as f:
    buf = f.read()

model = tflite.Model.GetRootAsModel(buf, 0)
subgraph = model.Subgraphs(0)

os.makedirs(destination_path, exist_ok=True)

# 3. Build a tensor_index -> tensor lookup map
tensor_map = {}
for i in range(subgraph.TensorsLength()):
    tensor_map[i] = subgraph.Tensors(i)

# 4. Iterate over OPERATORS in execution order
layer_index = 0

for op_idx in range(subgraph.OperatorsLength()):
    op = subgraph.Operators(op_idx)

    # Get the opcode name
    opcode_idx = op.OpcodeIndex()
    opcode = model.OperatorCodes(opcode_idx)

    from tflite.BuiltinOperator import BuiltinOperator
    builtin_code = opcode.BuiltinCode()
    op_name = {
        BuiltinOperator.CONV_2D: "conv",
        BuiltinOperator.DEPTHWISE_CONV_2D: "dw",
    }.get(builtin_code, None)

    # Skip ops we don't care about
    if op_name is None:
        continue

    # Extract Input and Output Tensors to get their global scales
    in_tensor_idx = op.Inputs(0)
    out_tensor_idx = op.Outputs(0)
    in_tensor = tensor_map[in_tensor_idx]
    out_tensor = tensor_map[out_tensor_idx]
    
    in_scales, _ = get_quantization_params(in_tensor)
    out_scales, _ = get_quantization_params(out_tensor)
    
    # Fallback to 1.0 if not quantized to avoid crashing
    in_scale = in_scales[0] if in_scales else 1.0
    out_scale = out_scales[0] if out_scales else 1.0

    weight_tensor_idx = op.Inputs(1)
    weight_tensor = tensor_map[weight_tensor_idx]
    weight_shape = [weight_tensor.Shape(j) for j in range(weight_tensor.ShapeLength())]

    if op_name == "conv" and len(weight_shape) == 4 and weight_shape[1] == 1 and weight_shape[2] == 1:
        op_name = "pw"

    # --- NEW: Extract Per-Channel Scales and Convert to Fixed-Point ---
    w_scales, w_zero_points = get_quantization_params(weight_tensor)
    
    if w_scales:
        multipliers = []
        shifts = []
        
        for w_scale in w_scales:
            # Effective scale math: M = (S_in * S_w) / S_out
            effective_scale = (in_scale * w_scale) / out_scale
            m, s = quantize_multiplier(effective_scale, precision=16)
            multipliers.append(m)
            shifts.append(s)
            
        # Pack into numpy arrays with proper bit widths
        mult_array = np.array(multipliers, dtype=np.uint16)
        shift_array = np.array(shifts, dtype=np.uint8)
        
        # Save multipliers to memory format
        m_filename = f"layer{layer_index}_{op_name}_multipliers.mem"
        sram_hex_to_mem_format(mult_array, os.path.join(destination_path, m_filename))
        
        # Save shifts to memory format
        s_filename = f"layer{layer_index}_{op_name}_shifts.mem"
        sram_hex_to_mem_format(shift_array, os.path.join(destination_path, s_filename))
        
        print(f"Extracted: Multipliers and Shifts for {op_name} (Channels: {len(w_scales)})")

    # Extract weights
    w_buffer = model.Buffers(weight_tensor.Buffer())
    if w_buffer.DataLength() > 0:
        raw_weights = w_buffer.DataAsNumpy()
        w_filename = f"layer{layer_index}_{op_name}_weights.mem"
        sram_hex_to_mem_format(raw_weights, os.path.join(destination_path, w_filename))
        print(f"Extracted: {w_filename} | Shape: {weight_shape}")

    # Extract bias (input index 2), if present
    if op.InputsLength() > 2:
        bias_tensor_idx = op.Inputs(2)
        if bias_tensor_idx >= 0:
            bias_tensor = tensor_map[bias_tensor_idx]
            b_buffer = model.Buffers(bias_tensor.Buffer())
            if b_buffer.DataLength() > 0:
                raw_bias = b_buffer.DataAsNumpy()
                b_filename = f"layer{layer_index}_{op_name}_bias.mem"
                sram_hex_to_mem_format(raw_bias, os.path.join(destination_path, b_filename))
                print(f"Extracted: {b_filename}")

    layer_index += 1