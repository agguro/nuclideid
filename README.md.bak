# `nuclideid` — Bare-Metal Data Ingestion & GPU Decay Solver

A minimalist, high-performance runtime pipeline engineered in pure x86_64 Assembly (AT&T syntax) and raw NVIDIA PTX (Parallel Thread Execution). The system ingests live nuclear data directly from the IAEA via raw network sockets, structures it in-memory, executes a parallel Bitonic Merge Sort on the GPU, and performs hardware-accelerated parameter inference (Adam Optimizer) on target decay curves.

---

## Architecture & Pipeline

[IAEA Web API] 
      | (Raw TCP Socket Ingestion via Linux System Calls)
      v
[nuclidedb_generator.s] 
      | (In-Memory CSV Parser & Fixed/Float Conversions)
      v
[bitonic_sort.ptx] 
      | (GPU Kernel: 32-byte Vectorized Merge Sort)
      v
   [isotopes.db] (Persistent flat-file binary database on disk)
      |
      +------------------------+
      v                        v
  [data.bin]           [learn_decay.s] (Zero-Copy Double File mmap)
  (Sample Data)                |
      |                        v
      +---------------> [adam_decay_solver.ptx]
                        (GPU Kernel: 5000 Epochs Adam Gradient Descent)
                               |
                               v
                        [Nuclide Identification Output]

---

## Record Layout (isotopes.db)

The database consists of a contiguous array of exactly 4096 records, each padded and aligned to a 32-byte boundary to guarantee optimal coalescing for GPU global memory transactions:

* Offset 0x00 - 0x03 [float32]: k_val -> Decay constant (lambda = ln(2) / T_1/2)
* Offset 0x04 - 0x07 [uint32] : A     -> Mass number
* Offset 0x08 - 0x0B [uint32] : Z     -> Atomic number (Protons)
* Offset 0x0C - 0x1F [char[20]]: symbol -> Null-terminated ASCII string containing isotope identifier

---

## System Requirements & Toolchain

* OS: GNU/Linux (Debian-based recommended, headless compute cluster or server).
* Assembler & Linker: GNU as (configured for 64-bit AT&T syntax) and standard ld.
* GPU Toolchain: NVIDIA CUDA Toolkit (requiring standalone /usr/bin/ptxas and /usr/bin/nvdisasm).
* Hardware Target: NVIDIA GPU (Pascal Architecture sm_61 or newer).

---

## Compilation & Project Management

The system leverages a recursive Makefile layout that automatically links appropriate assembler include paths (-I) and isolates environment builds into specific targets.

### Assemble and Link Host & Kernels (Debug Mode)
$ make

### Complete Clean (Wipes objects, binaries, and temporary build caches)
$ make clean

### Build Artifacts:
* Host Binaries: Placed inside ./bin/debug/x86_64/
* GPU Cubins: Compiled into ./build/debug/kernels/
* SASS Dumps: Disassembled GPU machine instructions (.sass) are dumped directly alongside .cubin targets for strict ISA inspection.

---

## Runtime Execution

### 1. Ingest Data and Generate Sorted Isotope Database
This component initiates a raw socket to the IAEA, stream-parses the binary payload, spins up a bare-metal CUDA driver context, transfers the layout, sorts it via the GPU bitonic pipeline, and saves the binary image to disk:
$ ./bin/debug/x86_64/nuclidedb_generator/nuclidedb_generator

### 2. Run Decay Inference and Target Identification
Maps both isotopes.db and your analytical tracking file (data.bin) through a zero-copy virtual memory space, launches the Adam decay engine on the GPU for 5000 convergence steps, and performs a native CPU binary search to instantly identify the isotope:
$ ./bin/debug/x86_64/learn_decay/learn_decay

---

## Guardrails & Hardware Validation

CRITICAL - CUDA Initialization Sentinel Check:
Both nuclidedb_generator and learn_decay incorporate a strict ABI-compliant driver checkpoint right after _start. If executed on a system missing the underlying NVIDIA driver stack or physical hardware nodes (such as testing on a development workstation instead of the production server cluster), the assembly code bypasses driver-level panic loops and terminates gracefully via exit-code 1, printing a high-visibility error message directly to stderr.
