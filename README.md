# SynBOLD-DisCo

## Contents

* [Overview](#overview)
* [Dockerized Application](#dockerized-application)
* [Docker Instructions](#docker-instructions)
* [Singularity Instructions](#singularity-instructions)
* [Non-containerized Instructions](#non-containerized-instructions)
* [Flags](#flags)
* [Inputs](#inputs)
* [Outputs](#outputs)
* [After Running](#after-running)

## Overview

This repository implements the paper "SynBOLD-DisCo: Synthetic BOLD images for distortion correction of fMRI without additional calibration scans". 

This tool aims to enable susceptibility distortion correction with historical and/or limited datasets that do not include specific sequences for distortion correction (i.e. reverse phase-encoded scans). In short, we synthesize an "undistorted" BOLD image that matches the geometry of structural T1w images and also matches the contrast.
We can then use this 'undistorted' image in standard pipelines (i.e. TOPUP) and tell the algorithm that this synthetic image has an infinite bandwidth. Note that the processing below enables both image synthesis, and also synthesis + full pipeline correction, if desired. 

Please use the following citations to refer to this work:

Tian Yu, Leon Y. Cai, Victoria L. Morgan, Sarah E. Goodale, Dario J. Englot, Catherine E. Chang, Bennett A. Landman, and Kurt G. Schilling. "SynBOLD-DisCo: Synthetic BOLD images for distortion correction of fMRI without additional calibration scans". Submitted to SPIE Medical Imaging: Image Processing (2023).

## Dockerized Application
For deployment we provide a [Docker container](https://hub.docker.com/repository/docker/ytzero/synbold-disco) which uses the trained model to predict the undistorted BOLD image to be used in susceptability distortion correction for functional MRI. For those who prefer, Docker containers can be converted to Singularity containers (see below).

## Docker Instructions:

```
sudo docker run --rm \
-v $(pwd)/INPUTS/:/INPUTS/ \
-v $(pwd)/OUTPUTS:/OUTPUTS/ \
-v <path to license.txt>:/extra/freesurfer/license.txt \
--user $(id -u):$(id -g) \
ytzero/synbold-disco:v1.1
<flags>
```

* If within your current directory you have your INPUTS and OUTPUTS folder, you can run this command copy/paste with the only change being \<path to license.txt\> should point to the freesurfer license.txt file on your system.
* If INPUTS and OUTPUTS are not within your current directory, you will need to change $(pwd)/INPUTS/ to the full path to your input directory, and similarly for OUTPUTS.
* For Mac users, Docker defaults allows only 2Gb of RAM and 2 cores - we suggest giving Docker access to >8Gb of RAM 
* Additionally on MAC, if permissions issues prevent binding the path to the license.txt file, we suggest moving the freesurfer license.txt file to the current path and replacing the path line to " $(pwd)/license.txt:/extra/freesurfer/license.txt "

## Singularity Instructions

First, build the synbold.sif container in the current directory:

```
singularity pull docker://ytzero/synbold-disco:v1.1
```

Then, to run the synbold.sif container:

```
singularity run -e \
-B INPUTS/:/INPUTS \
-B OUTPUTS/:/OUTPUTS \
-B <path to license.txt>:/extra/freesurfer/license.txt \
<path to synbold.sif>
<flags>
```

* \<path to license.txt\> should point to freesurfer licesnse.txt file
* \<path to synbold.simg\> should point to the singularity container 

## Non-containerized Instructions

If you choose to run this in bash, the primary script is located in src/pipeline.sh. The paths in pipeline.sh are specific to the docker/singularity file systems, but the processing can be replicated using the scripts in src. These utilize freesurfer, FSL, ANTS, MRtrix3 and a python environment with pytorch, numpy and nibabel.

## Flags:

**--notopup**

Skip the application of FSL's topup susceptibility correction. As a default, we run topup for you, although you may want to run this on your own (for example with your own config file, or if you would like to utilize multiple BOLD's).

**--motion_corrected**

Lets the container know that supplied distorted bold images has already been motion corrected. As a default, we motion-correct the distorted image.

## Inputs

The INPUTS directory must contain the following:
* BOLD_d.nii.gz: the non-diffusion weighted image(s) (either raw or motion-corrected, see [Flags](#flags))
* T1.nii.gz: the T1-weighted image
* acqparams.txt: A text file that describes the acqusition parameters, and is described in detail on the FslWiki for topup (https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/topup). Briefly,
it describes the direction of distortion and tells TOPUP that the synthesized image has an effective echo spacing of 0 (infinite bandwidth). An example acqparams.txt is
displayed below, in which distortion is in the second dimension, note that the second row corresponds to the synthesized, undistorted, BOLD:
    ```
    $ cat acqparams.txt 
    0 1 0 0.062
    0 1 0 0.000
    ```

## Outputs

After running, the OUTPUTS directory contains the following preprocessing files:

* T1_mask.nii.gz: brain extracted (skull-stripped) T1 (a copy of the input if T1.nii.gz is already skull-stripped)
* T1_norm.nii.gz: normalized T1
* epi_reg_d.mat: epi_reg BOLD to T1 in FSL format
* epi_reg_d_ANTS.txt: epi_reg to T1 in ANTS format
* ANTS0GenericAffine.mat: Affine ANTs registration of T1_norm to/from MNI space
* ANTS1Warp.nii.gz: Deformable ANTs registration of T1_norm to/from MNI space  
* ANTS1InverseWarp.nii.gz: Inverse deformable ANTs registration of T1_norm to/from MNI space  
* T1_norm_lin_atlas_2_5.nii.gz: linear transform T1 to MNI   
* BOLD_d_3D_lin_atlas_2_5.nii.gz: linear transform distorted BOLD in MNI space   


The OUTPUTS directory also contains inferences (predictions) for each of five folds utilizing T1_norm_lin_atlas_2_5.nii.gz and BOLD_d_3D_lin_atlas_2_5 as inputs:


* BOLD_s_3D_lin_atlas_2_5_FOLD_1.nii.gz
* BOLD_s_3D_lin_atlas_2_5_FOLD_1.nii.gz 
* BOLD_s_3D_lin_atlas_2_5_FOLD_2.nii.gz
* BOLD_s_3D_lin_atlas_2_5_FOLD_3.nii.gz  
* BOLD_s_3D_lin_atlas_2_5_FOLD_4.nii.gz  
* BOLD_s_3D_lin_atlas_2_5_FOLD_5.nii.gz  

After inference the ensemble average is taken in atlas space:

* BOLD_s_3D_lin_atlas_2_5_merged.nii.gz  
* BOLD_s_3D_lin_atlas_2_5.nii.gz         

It is then moved to native space for the undistorted, synthetic output:

* BOLD_u_3D.nii.gz: Synthetic BOLD native space                      

The undistorted synthetic output, and a smoothed distorted input can then be stacked together for topup:

* BOLD_3D_smooth.nii.gz: smoothed BOLD
* BOLD_all.nii.gz: stack of distorted and synthetized image as input to topup        

Finally, the topup outputs to be used for eddy:

* topup_results_movpar.txt
* BOLD_u_3D.nii.gz.nii.gz
* BOLD_all.topup_log         
* topup_results_fieldcoef.nii.gz


## After Running

After running, we envision using the topup outputs directly with FSL's eddy command, exactly as would be done if a full set of reverse PE scans was acquired. For example:

```
eddy --imain=path/to/diffusiondata.nii.gz --mask=path/to/brainmask.nii.gz \
--acqp=path/to/acqparams.txt --index=path/to/index.txt \
--bvecs=path/to/bvecs.txt --bvals=path/to/bvals.txt 
--topup=path/to/OUTPUTS/topup --out=eddy_unwarped_images
```

where imain is the original diffusion data, mask is a brain mask, acqparams is from before, index is the traditional eddy index file which contains an index (most likely a 1) for every volume in the diffusion dataset, topup points to the output of the singularity/docker pipeline, and out is the eddy-corrected images utilizing the field coefficients from the previous step.

Alternatively, if you choose to run --notopup flag, the file you are interested in is BOLD_all. This is a concatenation of the real BOLD and the synthesized undistorted BOLD. We run topup with this file, although you may chose to do so utilizing your topup version or config file. 