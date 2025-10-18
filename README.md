# Parallel Minimum Spanning Tree (MST) using Borůvka's Algorithm 🌳

This project provides a massively parallel implementation of a Minimum Spanning Tree (MST) graph algorithm using NVIDIA CUDA. The implementation is based on **Borůvka's algorithm**, which is highly effective for parallel architectures.

---

## Algorithm Explained 🧠

The core logic utilizes **Borůvka's algorithm**. This algorithm works iteratively, starting with each vertex as its own component. In each iteration (or "superstep"):

1.  Every component finds its minimum-weight edge connecting it to a *different* component.
2.  These minimum-weight edges are added to the MST.
3.  The components connected by these edges are merged.

This process repeats until only one component remains, which represents the complete Minimum Spanning Tree. Its design allows for a high degree of parallelism, as the minimum edge for each component can be found concurrently.

---

## Requirements ⚙️

* **NVIDIA GPU**: A CUDA-enabled NVIDIA GPU is required to run the parallel implementation.
* **CUDA Toolkit**: The `nvcc` compiler must be installed and available in your system's PATH.
* **Environment**: This code can be run in any environment providing GPU access, such as Google Colab, Kaggle notebooks, or a local machine with an NVIDIA GPU.

---

## Compilation 🔨

To compile the CUDA source code, use the following command. This will create an executable file named `parallelMST.out`.

```bash
nvcc -std=c++17 parallelMST.cu -o parallelMST.out

