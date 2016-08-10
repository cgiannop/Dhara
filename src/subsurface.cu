/*
// Copyright (C) 2016, HydroComplexity Group
// All rights reserved.
//
// Distributed Hydrologicc and Regional Analysis (DHARA) Model
// DHARA model is free software; you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation; either version 2.1 of the License, or
// (at your option) any later version.
//
// DHARA model is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the software; if not, see <http://www.gnu.org/licenses/>.
//
// Author: levuvietphong@gmail.com (Phong Le)
*/

#include "../include/main.h"
#include "../include/cusplib.h"
#include "../include/devconst.h"
#include "../include/global.h"


__device__ double maxcompssf (double a, double b)
{
    return (a < b) ? b : a;
}



__device__ void HydraulicConductivityAtInterface(double *knp1m, double *ke, double *kw, 
                double *kn, double *ks, double *ku, double *kd, int glob_ind, int i, int j, int k,
                int3 globsize)
{
    int sizex  = globsize.x;
    int sizey  = globsize.y;
    int sizez  = globsize.z;
    int sizexy = sizex * sizey;

    if ( k==0 || k==sizez-1 )
    {
        // top and bottom
        *ku = knp1m[glob_ind];
        *kd = knp1m[glob_ind];
    } else {
        *ku = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind+sizexy]);
        *kd = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind-sizexy]);
    }
    
    if ( j==0 || j==sizey-1 )
    {
        // north and south
        *kn = knp1m[glob_ind];
        *ks = knp1m[glob_ind];
    } else {
        *kn = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind+sizex]);
        *ks = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind-sizex]);
    }
    
    if ( i==0 || i==sizex-1 )
    {
        // east and west
        *ke = knp1m[glob_ind];
        *kw = knp1m[glob_ind];
    } else {
        *ke = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind+1]);
        *kw = 0.5 * (knp1m[glob_ind] + knp1m[glob_ind-1]);
    }
}



__device__ void SetUpBlockMatrixSubsurface(double *a3d, double *thetanp1m, double *cnp1m, 
                double dx2inv, double dy2inv, double dz2inv, double ke, double kw, double kn,
                double ks, double ku, double kd, int tid, int glob_ind, int k, int3 globsize)
{
    int sizexyz = globsize.x * globsize.y * globsize.z;

    // lower 3 diagonals
    a3d[0*sizexyz+tid] = dz2inv * kd;
    a3d[1*sizexyz+tid] = dy2inv * ks;
    a3d[2*sizexyz+tid] = dx2inv * kw;

    // main diagonal
    a3d[3*sizexyz+tid] = Ss/dt * thetanp1m[glob_ind]/poros + cnp1m[glob_ind]/dt 
                         - (ke+kw) * dx2inv - (kn+ks) * dy2inv - (ku+kd) * dz2inv;
    
    // upper 3 diagonals
    a3d[4*sizexyz+tid] = dx2inv * ke;
    a3d[5*sizexyz+tid] = dy2inv * kn;
    a3d[6*sizexyz+tid] = dz2inv * ku;
}



__device__ void SetUpRightHandSideSubsurface(double *rhs, double *thetan, double *thetanp1m, 
                double *psinp1m, double *psin, double ku, double kd, double *cnp1m, double *tr,
                int *trmap, double *root, int tid, int i, int j, int k, int glob_ind, 
                int3 globsize)
{
    int id2d = j*globsize.x+i;
    int proc = trmap[id2d];
    double trodz = -tr[id2d] * root[proc*globsize.z+k] * 3.6 / dz;
    rhs[tid] = Ss/dt * thetanp1m[glob_ind]/poros * psin[glob_ind] + cnp1m[glob_ind]/dt * psinp1m[glob_ind] - (ku - kd)/dz + (thetan[glob_ind] - thetanp1m[glob_ind])/dt + trodz/dt;
}



__device__ void SetUpBoundaryConditionsSubsurface(double *a3d, double *rhs, int *bbc, int *tbc,
                int *sbc, int *nbc, int *wbc, int *ebc, double kd, double ku, double ks,
                double kn, double kw, double ke, double dx2inv, double dy2inv, double dz2inv,
                double *Psi_t, double *Psi_b, double *Psi_s, double *Psi_n, double *Psi_w,
                double *Psi_e, double *qw, double *qe,  double *qs, double *qn, double *qt,
                double *qb, int tid, int i, int j, int k, int3 globsize)
{
    int sizex   = globsize.x;
    int sizey   = globsize.y;
    int sizez   = globsize.z;
    int sizexyz = sizex * sizey * sizez;
    int bi, bj, bk;

    // Mapping to real boundary faces
    bi = k * sizey + j;
    bj = k * sizex + i;
    bk = j * sizex + i;

    // Top face boundary conditions
    if (tbc[bk] == 0)
    {   
        // Dirichlet Boundary
        if (k == 1)
        {   
            // Inner points
            a3d[0 * sizexyz + tid] = 0.0;
            rhs[tid] -= dz2inv * kd * Psi_t[bk];
        }

        if (k == 0)
        {   
            // Outer points
            for (int r=0; r<7; r++) 
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_t[bk];
        }
    }
    else 
    {  
        // Neumann Boundary
        if (k == 0) 
        {
            a3d[3 * sizexyz + tid] += dz2inv * ku;
            rhs[tid] += (dz - qt[bk]*dz/ku) * dz2inv * ku;
        }
    }


    // Bottom face boundary conditions
    if (bbc[bk] == 0)
    {   
        // Dirichlet Boundary
        if (k == sizez-2)
        {
            a3d[6 * sizexyz + tid] = 0.0;
            rhs[tid] -= dz2inv * ku * Psi_b[bk];
        }
        if (k == sizez-1)
        {
            for (int r=0; r<7; r++)
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_b[bk];
        }
    }
    else 
    {  
        // Neumann Boundary
        if (k == sizez-1) 
        {
            qb[bk] = kd;
            a3d[3 * sizexyz + tid] += dz2inv * kd;
            rhs[tid] += (-dz + qb[bk] * dz / kd) * dz2inv * kd;
        }
    }


    // South face boundary conditions
    if (sbc[bj] == 0)
    {   
        // Dirichlet Boundary
        if (j == 1)
        {   
            // Inner points
            a3d[1 * sizexyz + tid] = 0.0;
            rhs[tid] -= dy2inv * kn * Psi_s[bj];
        }

        if (j == 0)
        {   
            // Outer points
            for (int r=0; r<7; r++)
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_s[bj];
        }
    }
    else 
    {   
        // Neumann Boundary
        if (j == 0)
        {   qs[bj] = ks;
            a3d[3 * sizexyz + tid] += dy2inv * ks;
            rhs[tid] += (-qs[bj] * dy / ks) * dy2inv * ks;
        }
    }


    // North face boundary conditions
    if (nbc[bj] == 0) 
    {   
        // Dirichlet Boundary
        if (j == sizey-2)
        {   // Inner points
            a3d[5 * sizexyz + tid] = 0.0;
            rhs[tid] -= dy2inv * ks * Psi_n[bj];
        }

        if (j == sizey-1)
        {   
            // Outer points
            for (int r=0; r<7; r++)
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_n[bj];
        }
    } 
    else
    {   
        // Neumann Boundary
        if (j == sizey-1) 
        {
            a3d[3 * sizexyz + tid] += dy2inv * kn;
            rhs[tid] += (qn[bj] * dy / kn) * dy2inv * kn;
        }
    }

    
    // West face boundary conditions
    if (wbc[bi] == 0)
    {
        if (i == 1)
        {   
            // Inner points
            a3d[2 * sizexyz + tid] = 0.0;
            rhs[tid] -= dx2inv * ke * Psi_w[bi];
        }

        if (i == 0)
        {   
            // Outer points
            for (int r=0; r<7; r++) 
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_w[bi];
        }
    }
    else
    {
        if (i == 0)
        {
            a3d[3 * sizexyz + tid] += dx2inv * kw;
            rhs[tid] += (-qw[bi] * dx / kw) * dx2inv * kw;
        }
    }


    // East face boundary conditions
    if (ebc[bi] == 0)
    {
        if (i == sizex-2)
        {   
            // Inner points
            a3d[4 * sizexyz + tid] = 0.0;
            rhs[tid] -= dx2inv * kw * Psi_e[bi];
        }

        if (i == sizex-1)
        {   
            // Outer points
            for (int r=0; r<7; r++) 
            {
                if (r == 3)
                    a3d[r * sizexyz + tid] = 1.0;
                else
                    a3d[r * sizexyz + tid] = 0.0;
            }
            rhs[tid] = Psi_e[bi];
        }
    }
    else
    {
        if (i == sizex-1)
        {
            a3d[3 * sizexyz + tid] += dx2inv * ke;
            rhs[tid] += (qe[bi] * dx / ke) * dx2inv * ke;
        }
    }
}


/**
 * @brief      Send transpiration from root process to entire domain on device
 *
 * @param      TR        Transpiration rate for entire domain
 * @param      TRroot    Transpiration collected at master process
 * @param      TRmap     Map of process on the domain
 * @param[in]  globsize  Size of the global domain
 */
__global__ void SendTranspirationToGrids(double *TR, double *TRroot, int *TRmap, int3 globsize)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int sizexy = globsize.x * globsize.y;    
    int ind;

    while (tid < sizexy)
    {
        ind = TRmap[tid];
        TR[tid] = TRroot[ind];

        // Update threads if vector is long
        tid += blockDim.x * gridDim.x;
    }    
}


__global__ void SetUpLinearSystemsSubsurface(double *a3d, double *rhs, double *psinp1m, 
                double *psin, double *thetanp1m, double *thetan, double *knp1m, double *cnp1m, 
                int *wbc, int *ebc, int *sbc, int *nbc, int *tbc, int *bbc, double *psi_w,
                double *psi_e, double *psi_s, double *psi_n, double *psi_t, double *psi_b,
                double *qw, double *qe, double *qs, double *qn, double *qt, double *qb, 
                double *tr, int *trmap, double *root, int3 globsize)
{
    int tid     = threadIdx.x + blockIdx.x * blockDim.x;
    int sizex   = globsize.x;
    int sizey   = globsize.y;
    int sizez   = globsize.z;
    int sizexy  = sizex * sizey;
    int sizexyz = sizex * sizey * sizez;

    int i, j, k, glob_ind;
    double dx2inv, dy2inv, dz2inv;
    double ke, kw, kn, ks, ku, kd;

    while (tid < sizexyz)
    {
        k = tid / sizexy;
        j = ( tid % sizexy ) / sizex;
        i = ( tid % sizexy ) % sizex;

        dx2inv = -1.0/(dx*dx);
        dy2inv = -1.0/(dy*dy);
        dz2inv = -1.0/(dz*dz);

        // Mapping to real 3D domain
        glob_ind = k * sizexy + j * sizex + i;

        HydraulicConductivityAtInterface(knp1m, &ke, &kw, &kn, &ks, &ku, &kd, glob_ind, i, j, k,
                                         globsize);

        SetUpBlockMatrixSubsurface(a3d, thetanp1m, cnp1m, dx2inv, dy2inv, dz2inv, ke, kw, kn, ks,
                                   ku, kd, tid, glob_ind, k, globsize);

        SetUpRightHandSideSubsurface(rhs, thetan, thetanp1m, psinp1m, psin, ku, kd, cnp1m, tr,
                                     trmap, root, tid, i, j, k, glob_ind, globsize);

        SetUpBoundaryConditionsSubsurface(a3d, rhs, bbc, tbc, sbc, nbc, wbc, ebc, 
                                          kd, ku, ks, kn, kw, ke, dx2inv, dy2inv, dz2inv,
                                          psi_t, psi_b, psi_s, psi_n, psi_w, psi_e, 
                                          qw, qe,  qs, qn, qt, qb, tid, i, j, k, globsize);

        __syncthreads();    // All thread must sync at this point
        tid += blockDim.x * gridDim.x;
    }
}


__global__ void GetIterationDifference( double *psinp1m, double *psinp1mp1, double* deltam, 
                int3 globsize)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int sizexyz = globsize.x * globsize.y * globsize.z;

    while (tid < sizexyz){
        deltam[tid] = abs(psinp1mp1[tid] - psinp1m[tid]);
        
        // Update threads if vector is long
        tid += blockDim.x * gridDim.x;
    }
}



__global__ void ModifiedPicardUpdate(double *psinp1m, double *psinp1mp1, int3 globsize)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int sizexyz = globsize.x * globsize.y * globsize.z;    

    while (tid < sizexyz){
        psinp1m[tid] = am * psinp1m[tid] + (1-am) * psinp1mp1[tid];

        // Update threads if vector is long
        tid += blockDim.x * gridDim.x;
    }
}



__global__ void SubsurfaceEstimateInfiltrationPonding(double *psinp1mp1, double *knp1m, 
                double *qt, double *qss, double *psi_top, double *ph, int *tbc, int3 globsize)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    int sizex = globsize.x;
    int sizey = globsize.y;

    while (tid < sizex * sizey) {
        if (tbc[tid] == 1) 
        {  
            // Flux boundary
            qss[tid] = qt[tid];
            ph[tid]  = 0.0;
        }
        else
        {
            // Pressure head boundary
            qss[tid] = -knp1m[tid] * (psinp1mp1[tid] - psi_top[tid] - dz) / dz;
            ph[tid]  = maxcompssf(psi_top[tid] - qss[tid]*dt, 0.0);
        }

        tid += blockDim.x * gridDim.x;
    }
}


void GatherTranspirationDomain(ProjectClass *project, VerticalCanopyClass *vertcanopies,
                               SubsurfaceFlowClass *subsurface_host, 
                               SubsurfaceFlowClass *subsurface_dev,
                               int rank, int procsize, int3 globsize, int3 domsize, int2 topolsize,
                               int2 topolindex, MPI_Comm *cartComm)
{
    int isroot = rank == MPI_MASTER_RANK;

    MPI_Gather(vertcanopies->TR_can, 1, MPI_DOUBLE, subsurface_host->TR_root, 1, MPI_DOUBLE, 0, *cartComm);

    if (isroot)
    {
        SafeCudaCall( cudaMemcpy(subsurface_dev->TR_root, subsurface_host->TR_root, 
                  procsize*sizeof(double), cudaMemcpyHostToDevice) );

        SendTranspirationToGrids<<<TSZ,BSZ>>>(subsurface_dev->TR, subsurface_dev->TR_root,
                                subsurface_dev->TRmap, globsize);
        cudaCheckError("SendTranspirationToGrids");
    }

}



/**
 * @brief      Run the subsurface flow model in device
 *
 * @param      timeforcings     Class including time forcings info
 * @param      overland_host    Overland flow class in host memory
 * @param      overland_dev     Overland flow class in device memory
 * @param      subsurface_host  Subsurface flow class in host memory
 * @param      subsurface_dev   Subsurface flow class in device memory
 * @param      a3d_cusp         Left hand side matrix A in cusp format
 * @param      psinp1mp1_cusp   Pressure head at n+1,m+1 in cusp format
 * @param      rhs3d_cusp       Right hand side vector b in cusp format
 * @param      id3d             The identity for linear system solver
 * @param      deltam_cusp      The difference between 2 iters in cusp format
 * @param      maxError         The maximum error of vector difference
 * @param[in]  rank             Global rank of the current MPI process
 * @param[in]  procsize         Total number of MPI processes available
 * @param[in]  globsize         Size of the global domain
 * @param[in]  t                Current time step running
 * @param[in]  num_steps        The number steps for simulation
 */
void SubsurfaceFlowModel(TimeForcingClass * &timeforcings, OverlandFlowClass * &overland_host,
                         OverlandFlowClass * &overland_dev, SubsurfaceFlowClass * &subsurface_host,
                         SubsurfaceFlowClass * &subsurface_dev, cuspdev_diamat &a3d_cusp,
                         cuspdev_1d &psinp1mp1_cusp, cuspdev_1d &rhs3d_cusp, cuspdev_idoper &id3d,
                         cuspdev_1d &deltam_cusp, thrustdev_iter &maxError, int rank, int procsize,
                         int3 globsize, int t, int num_steps)
{
    int sizexy  = globsize.x * globsize.y;
    int sizexyz = globsize.x * globsize.y * globsize.z;
    int maxiter = subsurface_host->maxiter;
    int picardmethod = subsurface_host->picardmethod;

    int runflag, niter;
    double stop_tol;

    SafeCudaCall( cudaMemcpy(subsurface_dev->psinp1m, subsurface_dev->psin,
                             sizexyz*sizeof(double), cudaMemcpyDeviceToDevice) );

    runflag = 0;
    niter = 0;

    EstimateFluxes<<<TSZ,BSZ>>>(overland_dev->ph, overland_dev->hpoten, overland_dev->qcapa,
                  subsurface_dev->psinp1m, subsurface_dev->knp1m, timeforcings->ppt[t], 
                  0., globsize);
    cudaCheckError("EstimateFluxes");

    while (runflag == 0 && niter < maxiter)
    {
        // Convert pressure head (psi) to moisture (theta)
        vanGenuchten<<<TSZ,BSZ>>>(subsurface_dev->cnp1m, subsurface_dev->thetanp1m,
                    subsurface_dev->ksat, subsurface_dev->knp1m, subsurface_dev->psinp1m,
                    globsize );
        cudaCheckError("vanGenuchten");

        // Boundary switching
        IdentifyTopBoundary<<<TSZ,BSZ>>>(overland_dev->hpoten, overland_dev->qcapa,
                           subsurface_dev->bct, subsurface_dev->bcqt,
                           subsurface_dev->psinp1m, subsurface_dev->bcpsit, globsize );
        cudaCheckError("IdentifyTopBoundary");

        // Set A, b, and boundary conditions
        SetUpLinearSystemsSubsurface<<<TSZ, BSZ>>>(subsurface_dev->a3d, subsurface_dev->rhs3d,
                                    subsurface_dev->psinp1m, subsurface_dev->psin,
                                    subsurface_dev->thetanp1m, subsurface_dev->thetan,
                                    subsurface_dev->knp1m, subsurface_dev->cnp1m,
                                    subsurface_dev->bcw, subsurface_dev->bce,
                                    subsurface_dev->bcs, subsurface_dev->bcn,
                                    subsurface_dev->bct,subsurface_dev->bcb,
                                    subsurface_dev->bcpsiw, subsurface_dev->bcpsie,
                                    subsurface_dev->bcpsis, subsurface_dev->bcpsin,
                                    subsurface_dev->bcpsit, subsurface_dev->bcpsib,
                                    subsurface_dev->bcqw, subsurface_dev->bcqe,
                                    subsurface_dev->bcqs, subsurface_dev->bcqn,
                                    subsurface_dev->bcqt, subsurface_dev->bcqb, 
                                    subsurface_dev->TR, subsurface_dev->TRmap, 
                                    subsurface_dev->rda, globsize );
        cudaCheckError("SetUpLinearSystemsSubsurface");

        // Solve linear systems
        cusp::monitor <double> monitor(rhs3d_cusp, 100, 1e-8);
        cusp::krylov::bicgstab(a3d_cusp, psinp1mp1_cusp, rhs3d_cusp, monitor, id3d);

        // Again, convert psi to theta
        vanGenuchten<<<TSZ,BSZ>>>(subsurface_dev->cnp1m, subsurface_dev->thetanp1mp1,
                                  subsurface_dev->ksat, subsurface_dev->knp1m,
                                  subsurface_dev->psinp1mp1, globsize );
        cudaCheckError("vanGenuchten");

        niter += 1;

        // Get the difference between 2 iterations and find maxError
        if (picardmethod == 0)
        {   
            // use pressure as primary
            GetIterationDifference<<<TSZ,BSZ>>>(subsurface_dev->psinp1m, subsurface_dev->psinp1mp1,
                                  subsurface_dev->deltam, globsize );
            cudaCheckError("GetIterationDifference_psi");
            stop_tol = subsurface_host->tolerance_psi;
        } else {
            // use moisture as primary
            GetIterationDifference<<<TSZ,BSZ>>>(subsurface_dev->thetanp1m,
                                  subsurface_dev->thetanp1mp1, subsurface_dev->deltam, globsize );
            cudaCheckError("GetIterationDifference_theta");
            stop_tol = subsurface_host->tolerance_theta;
        }

        maxError = thrust::max_element(deltam_cusp.begin(), deltam_cusp.end());

        // check the maximum error to test convergence
        if (*maxError < stop_tol)
        {
            // converged
            runflag = 1;
        } else {
            // not convereged yet, update and repeat
            ModifiedPicardUpdate<<<TSZ,BSZ>>>(subsurface_dev->psinp1m, subsurface_dev->psinp1mp1,
                                globsize);
            cudaCheckError("ModifiedPicardUpdate");
        }
    }

    // Estimate infiltration to soil
    SubsurfaceEstimateInfiltrationPonding<<<TSZ,BSZ>>>(subsurface_dev->psinp1mp1, 
                                         subsurface_dev->knp1m, subsurface_dev->bcqt,
                                         subsurface_dev->qss, subsurface_dev->bcpsit, 
                                         overland_dev->ph, subsurface_dev->bct, globsize);
    cudaCheckError("SubsurfaceEstimateInfiltrationPonding");

    SafeCudaCall( cudaMemcpy(overland_dev->waterdepth, overland_dev->ph, 
                             sizexy*sizeof(double), cudaMemcpyDeviceToDevice) );

    SafeCudaCall( cudaMemcpy(subsurface_dev->psin, subsurface_dev->psinp1mp1,
                             sizexyz*sizeof(double), cudaMemcpyDeviceToDevice) );

    SafeCudaCall( cudaMemcpy(subsurface_dev->thetan, subsurface_dev->thetanp1m, 
                             sizexyz*sizeof(double), cudaMemcpyDeviceToDevice) );

    SafeCudaCall( cudaMemcpy(subsurface_dev->psiout, subsurface_dev->psin, 
                             sizexyz*sizeof(double), cudaMemcpyDeviceToHost) );

    SafeCudaCall( cudaMemcpy(subsurface_dev->thetaout, subsurface_dev->thetan, 
                             sizexyz*sizeof(double), cudaMemcpyDeviceToHost) );
}