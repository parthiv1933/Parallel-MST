
#include <chrono>
#include <cuda.h>
#include <fstream>
#include <iostream>
#include <math.h>
#include <vector>
#define MOD 1000000007

using namespace std;

__global__ void dkernel (){
}

__global__ void edgeWeightCalculate (int *weight, char *type, int E){
    int edgeid = blockIdx.x*blockDim.x+threadIdx.x;
    
    if (edgeid<E){
        if(type[edgeid]=='g')
        {
          weight[edgeid]*=2;  
        }
        else if(type[edgeid]=='d')
        {
          weight[edgeid]*=3;  
        }
        else if(type[edgeid]=='t')
        {
          weight[edgeid]*=5;  
        }
    }
}
	
__global__ void intializeMinEdge(int *minWeight,int *minEdgeId, int V){
    int nodeid = blockIdx.x*blockDim.x+threadIdx.x;
    if(nodeid<V){
        minWeight[nodeid]= 50005;
        minEdgeId[nodeid] = -1;
    }
}

__global__ void findMinEdgeWeight(int *s,int *d,int *w,volatile int *minWeight,volatile int *parent, int E){
    int eid = blockIdx.x*blockDim.x+threadIdx.x;
    if(eid<E){
        int x=parent[s[eid]];
        int y=parent[d[eid]];
        if(x!=y){
         if(minWeight[x]>w[eid]) {
             atomicMin((int *)&minWeight[x],w[eid]);
         }  
         if(minWeight[y]>w[eid]) {
             atomicMin((int *)&minWeight[y],w[eid]);
         }
        }
    }
    
}
__global__ void findMinEdgeId(int *s,int *d,int *w,volatile int *minWeight,volatile int *minEdgeId,volatile int *parent, int E){
    int eid = blockIdx.x*blockDim.x+threadIdx.x;
    if(eid<E){
        int x=parent[s[eid]];
        int y=parent[d[eid]];
        if(x!=y){
            if(minWeight[x]==w[eid]){
                minEdgeId[x]=eid;
            }
            if(minWeight[y]==w[eid]){
                minEdgeId[y]=eid;
            }
        }
    }
}


__global__ void mergeAndAddEdge(int *minEdgeId,volatile int *parent,int V,int *ds,int *dd,int *dw,long long int *dTW,unsigned int *dNOC){
    
    int vid = blockIdx.x*blockDim.x+threadIdx.x;
    if(vid<V){
        if(minEdgeId[vid]!=-1){
           int eid=minEdgeId[vid];
           int src=ds[eid];
           int dest=dd[eid];
           int weight= dw[eid];
           
           int rootS=parent[src];
           int rootD=parent[dest];
           if(rootS!=rootD){
               int small = rootS<rootD?rootS:rootD;
               int large = rootS>rootD?rootS:rootD;
               if(atomicCAS((int *)&parent[large],large,small)==large){
                   atomicAdd((unsigned long long int *)dTW, (unsigned long long int)weight);

                   atomicDec(dNOC,10000000);
               }
           }
        }
    }
}
        
__global__ void finalParentComponent(volatile int *parent, int V){
     int vid = blockIdx.x*blockDim.x+threadIdx.x;
     if(vid<V){
         
         int lower=vid;
         int middle , upper;
         
         while(lower!=parent[lower]){
             middle= parent[lower];
            upper=parent[middle];
            
            atomicCAS((int *)&parent[lower],middle,upper);
            lower=parent[lower];
         }
        }
    }




int main() {

  ifstream file("/content/drive/MyDrive/assignment3/test1.txt");
  if(!file){
    cout<<"error"<<endl;
    return 1;
  }
    // Create a sample graph
    unsigned int V;
    file >> V;
    int E;
    file >> E;
    //vector<Edge> edges;
    int *src = new int[E];
    int *dest= new int[E];
    int *weight= new int[E];
    char *type= new char[E];
    int i=0;
    while (i<E) {
        string s;
        file >> src[i] >> dest[i] >> weight[i];
        file >> s;
        type[i]=s[0];
        i++;
    }
    
    unsigned int noOfComponent=V;
    long long int totalWeight=0;
    unsigned int *dNOC;
    long long int *dTW;
    

    int *ds,*dd,*dw;
    char *dt;
    cudaMalloc(&dNOC,sizeof(unsigned int));
    cudaMalloc(&dTW,sizeof(long long int));
    cudaMalloc(&ds,E*sizeof(int));
    cudaMalloc(&dd,E*sizeof(int));
    cudaMalloc(&dw,E*sizeof(int));
    cudaMalloc(&dt,E*sizeof(char));
    
    cudaMemcpy(dNOC,&noOfComponent,sizeof(unsigned int),cudaMemcpyHostToDevice);
    cudaMemcpy(dTW,&totalWeight,sizeof(long long int),cudaMemcpyHostToDevice);
    cudaMemcpy(ds,src,E*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy(dd,dest,E*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy(dw,weight,E*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy(dt,type,E*sizeof(char),cudaMemcpyHostToDevice);

    volatile int *minWeight , *minEdgeId , *parent;
    
    cudaMalloc(&minWeight,V*sizeof(int));
    cudaMalloc(&minEdgeId,V*sizeof(int));
    cudaMalloc(&parent,V*sizeof(int));
    
    //parent initialization
    int *hparent = new int[V];
    for(i=0;i<V;i++) hparent[i]=i;
    
    cudaMemcpy((void *)parent,hparent,V*sizeof(int),cudaMemcpyHostToDevice);
    
    

	int Eblock = (E+1023)/1024;
	int Vblock = (V+1023)/1024;
	
	
    
    // Answer should be calculated in Kernel. No operations should be performed here.
    // Only copy data to device, kernel call, copy data back to host, and print the answer.
    auto start = std::chrono::high_resolution_clock::now();
    // Kernel call(s) here
	
	edgeWeightCalculate <<< Eblock,1024>>> (dw,dt,E);
    
   while(noOfComponent>1){
        //intialize all vertex's minedge weight and id
        intializeMinEdge <<<Vblock,1024>>> ((int *)minWeight, (int *)minEdgeId, V);

        
        //find minimum edge weight for each vertex
        findMinEdgeWeight<<<Eblock,1024>>> (ds,dd,dw,minWeight,parent,E);
        //find minimum edge id for each vertex
        findMinEdgeId<<<Eblock,1024>>> (ds,dd,dw,minWeight,minEdgeId,parent,E);
        
        //merge component and add edges in MST 
       mergeAndAddEdge<<<Vblock,1024>>>((int *)minEdgeId, (int *)parent, V, ds, dd, dw, dTW, dNOC);

        
        finalParentComponent<<<Vblock,1024>>>(parent,V);
        
        cudaMemcpy(&noOfComponent,dNOC,sizeof(unsigned int),cudaMemcpyDeviceToHost);
        cout<<noOfComponent<<endl;
        
    }
     

       /* for(int x=0;x<20;x++){
          intializeMinEdge <<<Vblock,1024>>> ((int *)minWeight, (int *)minEdgeId, V);
        //find minimum edge weight for each vertex
        findMinEdgeWeight<<<Eblock,1024>>> (ds,dd,dw,minWeight,parent,E);
        //find minimum edge id for each vertex
        findMinEdgeId<<<Eblock,1024>>> (ds,dd,dw,minWeight,minEdgeId,parent,E);
        mergeAndAddEdge<<<Vblock,1024>>>((int *)minEdgeId, (int *)parent, V, ds, dd, dw, dTW, dNOC);

       int * minw = new int[V];
       cudaMemcpy(minw,(void *)minWeight,sizeof(int)*V,cudaMemcpyDeviceToHost);
       mergeAndAddEdge<<<Vblock,1024>>>((int *)minEdgeId, (int *)parent, V, ds, dd, dw, dTW, dNOC);
       for(int j=0;j<V;j++){
        cout<<j<<" "<<minw[j]<<endl;
       }
        }*/

    

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed1 = end - start;
    
     cudaMemcpy(&totalWeight,dTW,sizeof(long long int),cudaMemcpyDeviceToHost);
     
     cout<<totalWeight%MOD<<endl;
    
    // Print only the total MST weight


    cout << elapsed1.count() << " s\n";
    return 0;
}
