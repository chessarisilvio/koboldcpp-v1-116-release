# Koboldcpp v1.116 Manual GPU Benchmark Instructions

## Overview
This document provides step-by-step instructions for manually benchmarking Koboldcpp v1.116 builds on different GPUs (Tesla P40 and RTX 3050) to measure tokens per second (tok/s) and VRAM usage.

## Prerequisites
1. Koboldcpp v1.116 source code downloaded and extracted
2. NVIDIA drivers installed (version compatible with CUDA 12.x)
3. CUDA toolkit installed (for building)
4. Build dependencies: cmake, make, gcc/g++
5. jq and bc for benchmark script (usually pre-installed on Ubuntu)

## Step 1: Build Koboldcpp for Target GPUs

### Option A: Using the provided build script (recommended)
```bash
# Make the build script executable
chmod +x build_koboldcpp.sh

# Run the build script
./build_koboldcpp.sh

# Select build options:
# 1) Build for Tesla P40 (sm_61)
# 2) Build for RTX 3050 (sm_86)
# 3) Build for both GPUs
# 4) Exit

# Example: To build for both GPUs, select option 3
```

### Option B: Manual build (for advanced users)
```bash
# For Tesla P40 (sm_61)
mkdir build_p40 && cd build_p40
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=61 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA_FAQS=ON
make -j$(nproc)
cd ..

# For RTX 3050 (sm_86)
mkdir build_3050 && cd build_3050
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_CUDA_FAQS=ON
make -j$(nproc)
cd ..
```

After building, you should have directories:
- `build_0/` containing koboldcpp binary for P40 (if selected)
- `build_1/` containing koboldcpp binary for RTX 3050 (if selected)

## Step 2: Prepare for Benchmarking

1. Ensure you have a GGUF model file available (e.g., a Llama 3 8B model)
2. Place the model file in the koboldcpp directory or note its path
3. Close any other GPU-intensive applications to free up VRAM
4. Verify GPU availability:
   ```bash
   nvidia-smi
   ```

## Step 3: Run Manual Benchmarks

### Using the automated test script
```bash
# Make the test script executable
chmod +x test_manuali.sh

# Run benchmark for all available builds
./test_manuali.sh

# Or specify specific builds:
# ./test_manuali.sh 0      # Test only P40 build
# ./test_manuali.sh 1      # Test only RTX 3050 build
# ./test_manuali.sh 0 1    # Test both builds
# ./test_manuali.sh all    # Test all builds
```

### Manual benchmark procedure (if you prefer to run commands individually)

#### For each build directory:
1. Start the koboldcpp server:
   ```bash
   # Example for P40 build (adjust port and model path as needed)
   ./build_0/koboldcpp --model /path/to/model.gguf --port 8080 --host 127.0.0.1 --ctx-size 2048 --n-gpu-layers 99
   ```

2. In another terminal, run the benchmark request:
   ```bash
   curl -s -X POST "http://127.0.0.1:8080/v1/completions" \
     -H "Content-Type: application/json" \
     -d '{
       "prompt": "Explain the theory of relativity in detail.",
       "max_tokens": 128,
       "temperature": 0.7,
       "top_p": 0.9,
       "stream": false
     }' | jq '.'
   ```

3. Monitor VRAM usage during the test:
   ```bash
   watch -n 0.5 "nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i 0"
   ```

4. Stop the server with Ctrl+C when done

## Step 4: Interpret Results

The benchmark script will output:
- **Tokens per second (tok/s)**: Higher is better performance
- **Max VRAM used**: Indicates memory efficiency
- **Time taken**: Total response time

### Expected Performance Characteristics:
- **Tesla P40 (sm_61)**: 24GB VRAM, good for large models, moderate tok/s
- **RTX 3050 (sm_86)**: 8GB VRAM, lower tok/s but sufficient for smaller models

## Step 5: Troubleshooting

### Common Issues:
1. **Server fails to start**: Check logs in the generated log file
2. **Connection refused**: Ensure server is running and port is correct
3. **Out of memory**: Reduce `--ctx-size` or `--n-gpu-layers`
4. **CUDA errors**: Verify CUDA architecture flags match your GPU

### Log Files:
- Server logs: `koboldcpp_server_*.log` (generated during test)
- VRAM logs: `vram_*.log` (generated during test)

## Step 6: Safety Notes

1. Always monitor GPU temperature during extended benchmarks
2. Ensure adequate cooling, especially for P40 which can run hot
3. Do not leave benchmarks running unattended for long periods
4. Stop tests immediately if you notice unusual behavior or overheating

## References
- Koboldcpp GitHub repository: https://github.com/LostRuins/koboldcpp
- GGUF model sources: Hugging Face, TheBloke, etc.
- CUDA compatibility: https://developer.nvidia.com/cuda-gpus

---
*Instructions generated for Koboldcpp v1.116 release benchmarking*