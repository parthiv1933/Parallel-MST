
#include <chrono>
#include <cuda.h>
#include <fstream>
#include <iostream>
#include <math.h>
#include <vector>
#define MOD 1000000007

using namespace std;


//for weight convertion according to types
__global__ void edgeWeightCalculate (int *weight, char *type, int E,bool * validEdge){
    int eid = blockIdx.x*blockDim.x+threadIdx.x;
    
    if (eid<E){
      //validEdge[eid]=true;
      //green
        if(type[eid]=='g')
        {
          weight[eid]*=2;  
        }
        //department
        else if(type[eid]=='d')
        {
          weight[eid]*=3;  
        }
        //traffic        
        else if(type[eid]=='t')
        {
          weight[eid]*=5;  
        }
    }
}
	

//for find minimum outgoing edge's weight  for each vertex
__global__ void findMinEdgeWeight(int *s,int *d,int *w,volatile int *minWeight,volatile int *parent, int E,bool *validEdge){
    int eid = blockIdx.x*blockDim.x+threadIdx.x;
    if(eid<E){
        //if(!validEdge[eid]) return;
        //find actual component id
        int x=parent[s[eid]];
        int y=parent[d[eid]];
        //if not belongs to same component
        if(x!=y){
          //first check current edge weight is lesser or not
         if(minWeight[x]>w[eid]) {
          //then atomic compare and update to avoid data race
             atomicMin((int *)&minWeight[x],w[eid]);
         }  
         //same as above
         if(minWeight[y]>w[eid]) {
             atomicMin((int *)&minWeight[y],w[eid]);
         }
        }
        // else{
        //     validEdge[eid]=false;
        // }
    }
    
}
//for finding minimum outgoing  edge id for each vertex
__global__ void findMinEdgeId(int *s,int *d,int *w,volatile int *minWeight,volatile int *minEdgeId,volatile int *parent, int E,bool *validEdge){
    int eid = blockIdx.x*blockDim.x+threadIdx.x;
    if(eid<E){
        //if(!validEdge[eid]) return;
        //find actual component id
        int x=parent[s[eid]];
        int y=parent[d[eid]];
        //if not belongs to same component
        if(x!=y){
            //if minimu edge weight is same as edge's weight then it can be candidate minimum edge for particular vertex
            if(minWeight[x]==w[eid]){
                minEdgeId[x]=eid;
            }
            if(minWeight[y]==w[eid]){
                minEdgeId[y]=eid;
            }
        }
        // else{
        //     validEdge[eid]=false;
        // }
    }
}

//now we have minimum outgoing edge's id for all component so we can merge here
__global__ void mergeAndAddEdge(int *minEdgeId,volatile int *parent,int V,int *ds,int *dd,int *dw,long long int *dTW,unsigned int *dNOC,bool *validEdge){
    
    int vid = blockIdx.x*blockDim.x+threadIdx.x;
    if(vid<V){
        if(minEdgeId[vid]!=-1){
           int eid=minEdgeId[vid];
           int src=ds[eid];
           int dest=dd[eid];
           int weight= dw[eid];
           //finding component of source and destination and check if both are not same
           int rootS=parent[src];
           int rootD=parent[dest];
           if(rootS!=rootD){
            //here found small and large component according to vertex id
               int small = rootS<rootD?rootS:rootD;
               int large = rootS>rootD?rootS:rootD;
               //now here if possible then samll become parent of large vertex
               // if it's already done before then condition become false and no addition of duplicate edge
               if(atomicCAS((int *)&parent[large],large,small)==large){
                  
                  //atomically adding current edge weight to total MST weight
                   atomicAdd((unsigned long long int *)dTW, (unsigned long long int)weight);
                  //reduce total component by  1
                   atomicDec(dNOC,10000000);
                  //  validEdge[eid]=false;
               }
           }
        }
    }
}
   //intialization of minimum edge and calculate actual parent for next iteration     
__global__ void intializeMinEdgeAndfinalParentComponent(int *minWeight,int *minEdgeId,volatile int *parent, int V){
     int vid = blockIdx.x*blockDim.x+threadIdx.x;
     if(vid<V){
        //weight grater than 5*10e4 so 50005
        minWeight[vid]= 50005;
        //for checking if minimum edge not found so compare with -1
        minEdgeId[vid] = -1;
         

         //iterative path compration
         int lower=vid;
         int middle , upper;
         
         while(lower!=parent[lower]){
             middle= parent[lower];
            upper=parent[middle];
            //atomically path compration to avoid data race
            atomicCAS((int *)&parent[lower],middle,upper);
            lower=parent[lower];
         }
         
         
        }
    }




int main() {

    // Create a sample graph
    unsigned int V;
    // file >> V;
    cin>> V;
    int E;
    // file >> E;
    cin >> E;
    //vector<Edge> edges;
    int *src = new int[E];
    int *dest= new int[E];
    int *weight= new int[E];
    char *type= new char[E];
    int i=0;
    while (i<E) {
        string s;
        // file >> src[i] >> dest[i] >> weight[i];
        // file >> s;
        cin >> src[i] >> dest[i] >> weight[i];
        cin >> s;
        type[i]=s[0];
        i++;
    }
    
    unsigned int noOfComponent=V;
    long long int totalWeight=0;
    unsigned int *dNOC;
    long long int *dTW;
    

    int *ds,*dd,*dw;
    char *dt;
    bool *validEdge;
    
    cudaMalloc(&dNOC,sizeof(unsigned int));
    cudaMalloc(&dTW,sizeof(long long int));
    cudaMalloc(&ds,E*sizeof(int));
    cudaMalloc(&dd,E*sizeof(int));
    cudaMalloc(&dw,E*sizeof(int));
    cudaMalloc(&dt,E*sizeof(char));
    cudaMalloc(&validEdge,E*sizeof(bool));
    
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
    
    //valid Edge Initialization
    //since cuda not support direct intialization of boolean in memset so in kernel
    //cudaMemSet(validEdge,true,E*sizeof(bool));

    // minimum edge weight and id intialization
    
    //cudaMemSet(minWeight,50005,V*sizeof(int));
    //cudaMemSet(minEdgeId,-1,V*sizeof(int));
    //memSet suport byte level intialization so for non zero value it does not support

    //cudaMemSet(minEdgeId,-1,V*sizeof(int));
    //parent initialization
    int *hparent = new int[V];
    int *hminEdgeWeight = new int[V];
    int *hminEdgeId=  new int[V];
    for(i=0;i<V;i++){
    hminEdgeWeight[i]=50005; 
    hminEdgeId[i]=-1; 
    hparent[i]=i;
    }
    cudaMemcpy((void *)minWeight,hminEdgeWeight,V*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy((void *)minEdgeId,hminEdgeId,V*sizeof(int),cudaMemcpyHostToDevice);
    cudaMemcpy((void *)parent,hparent,V*sizeof(int),cudaMemcpyHostToDevice);
    
    

	int Eblock = ceil((E*1.0)/1024.0);
	int Vblock = ceil((V*1.0)/1024.0);
	
	
    
    // Answer should be calculated in Kernel. No operations should be performed here.
    // Only copy data to device, kernel call, copy data back to host, and print the answer.
    auto start = std::chrono::high_resolution_clock::now();
    // Kernel call(s) here
	
  //weight convertion according to edge type total E thread
	edgeWeightCalculate <<< Eblock,1024>>> (dw,dt,E,validEdge);
    
   while(true){
        

        
        //find minimum edge weight for each vertex total E thread
        findMinEdgeWeight<<<Eblock,1024>>> (ds,dd,dw,minWeight,parent,E,validEdge);
        //find minimum edge id for each vertex total E thread
        findMinEdgeId<<<Eblock,1024>>> (ds,dd,dw,minWeight,minEdgeId,parent,E,validEdge);
        
        //merge component and add edges in MST total V thread
       mergeAndAddEdge<<<Vblock,1024>>>((int *)minEdgeId, (int *)parent, V, ds, dd, dw, dTW, dNOC,validEdge);

        cudaMemcpy(&noOfComponent,dNOC,sizeof(unsigned int),cudaMemcpyDeviceToHost);
        
        //cout<<noOfComponent<<endl;
        //if Total Component Become 1 then MST successfully created
        if(noOfComponent<2){
            break;
        }
        
        //intialize all vertex's minedge weight and id and parent calculation  for next iteration
        
        intializeMinEdgeAndfinalParentComponent<<<Vblock,1024>>>((int *)minWeight, (int *)minEdgeId,parent,V);
    
    }
     

       

    

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed1 = end - start;
    
    cudaMemcpy(&totalWeight,dTW,sizeof(long long int),cudaMemcpyDeviceToHost);
     
    
    
    // Print only the total MST weight
    cout<<totalWeight%MOD<<endl;

    //cout << elapsed1.count() << " s\n";

    cudaFree(ds);
    cudaFree(dd);
    cudaFree(dw);
    cudaFree(dt);
    cudaFree(dTW);
    cudaFree(dNOC);
    cudaFree(validEdge);
    cudaFree((void *)parent);
    cudaFree((void *)minEdgeId);
    cudaFree((void *)minWeight);
    delete(src);
    delete(dest);
    delete(type);
    delete(weight);
    delete(hparent);
    delete(hminEdgeWeight);
    delete(hminEdgeId);

    return 0;
}
