# Parallel-MST
parallelize Minimum Spanning Tree Graph Algorithm (implemented idea of Borůvka's algorithm for MST for massive parallelism)

->Make sure you have Nvidea GPU device (colab,kaggle,krutrim could be used).
-> run command: nvcc -std=c++17 parallelMST.cu -o parallelMST.out 
                ./parallelMST <input/1

->compare outcome with output/1

