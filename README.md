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

## Overview

![Overview](https://github.com/MASILab/SynBOLD-DisCo/raw/main/overview.png)

This repository implements the paper ["SynBOLD-DisCo: Synthetic BOLD images for distortion correction of fMRI without additional calibration scans"](https://www.biorxiv.org/content/10.1101/2022.09.13.507794v1).

This tool aims to enable susceptibility distortion correction with historical and/or limited datasets that do not include specific sequences for distortion correction (i.e. reverse phase-encoded scans). In short, we generate a "synthetic, undistorted" BOLD image that matches the geometry of structural T1w images and also matches the contrast. We can then use this synthetic image in standard pipelines (i.e. TOPUP) and tell the algorithm that this synthetic image has an infinite bandwidth. Note that the processing below enables both image synthesis, and also synthesis + full pipeline correction, if desired. 

Please use the following citation to refer to this work:

Tian Yu*, Leon Y. Cai*, Victoria L. Morgan, Sarah E. Goodale, Dario J. Englot, Catherine E. Chang, Bennett A. Landman, and Kurt G. Schilling. "SynBOLD-DisCo: Synthetic BOLD images for distortion correction of fMRI without additional calibration scans". Submitted to SPIE Medical Imaging: Image Processing (2023). *Equal first authorship

## Dockerized Application
For deployment we provide a [Docker container](https://hub.docker.com/repository/docker/ytzero/synbold-disco) which uses the trained models to generate a synthetic BOLD image to be used in susceptability distortion correction for functional MRI. For those who prefer, Docker containers can be converted to Singularity containers (see below).

## Docker Instructions:

```bash
sudo docker run --rm \
-v $(pwd)/INPUTS/:/INPUTS/ \
-v $(pwd)/OUTPUTS:/OUTPUTS/ \
-v <path to license.txt>:/opt/freesurfer/license.txt \
-v /tmp:/tmp \
--user $(id -u):$(id -g) \
ytzero/synbold-disco:v1.4
<flags>
```

* If within your current directory you have your INPUTS and OUTPUTS folder, you can run this command copy/paste with the only change being \<path to license.txt\> should point to the freesurfer license.txt file on your system.
* If INPUTS and OUTPUTS are not within your current directory, you will need to change $(pwd)/INPUTS/ to the full path to your input directory, and similarly for OUTPUTS.
* \<path to license.txt\> should point to freesurfer license.txt file
* For Mac users, Docker defaults allows only 2Gb of RAM and 2 cores - we suggest giving Docker access to >8Gb of RAM 
* Additionally on MAC, if permissions issues prevent binding the path to the license.txt file, we suggest moving the freesurfer license.txt file to the current path and replacing the path line to " $(pwd)/license.txt:/opt/freesurfer/license.txt "
* To customize the pipeline, bind your script to the container and set it as the entry point using the command below. Replace /path/to/host/script with your scripts path in your computer, /path/in/container/script with the desired container path.

```bash
docker run -v 
/path/to/host/script:/path/in/container/script 
--entrypoint /path/in/container/script 
ytzero/synbold-disco:v1.4
```


## Singularity Instructions

First, build the synbold-disco.sif container in the current directory:

```
singularity pull docker://ytzero/synbold-disco:v1.4
```

Then, to run the synbold-disco.sif container:

```bash
singularity run -e \
-B $(pwd)/INPUTS/:/INPUTS \
-B $(pwd)/OUTPUTS/:/OUTPUTS \
-B <path to license.txt>:/opt/freesurfer/license.txt \
-B /tmp \
<path to synbold-disco.sif>
<flags>
```

* If within your current directory you have your INPUTS and OUTPUTS folder, you can run this command copy/paste with the only change being \<path to license.txt\> should point to the freesurfer license.txt file on your system.
* If INPUTS and OUTPUTS are not within your current directory, you will need to change $(pwd)/INPUTS/ to the full path to your input directory, and similarly for OUTPUTS.
* \<path to license.txt\> should point to freesurfer license.txt file
* \<path to synbold-disco.sif\> should point to the singularity container

## Non-containerized Instructions

If you choose to run this in bash, the primary script is located in src/pipeline.sh. The paths in pipeline.sh are specific to the docker/singularity file systems, but the processing can be replicated using the scripts in src. These utilize freesurfer, FSL, ANTS, MRtrix3 and a python environment with pytorch, numpy and nibabel.

## Flags:

**--no_topup**

Skip the application of FSL's topup susceptibility correction. As a default, we run topup for you.

**--motion_corrected**

Indicates that the supplied distorted BOLD image has already undergone motion correction. By default, our pipeline will apply motion correction to the distorted image. If you wish to preprocess your data prior to this (e.g., slice timing, motion correction, etc.), it is recommended to use this flag.

**--skull_stripped**

Lets the container know the supplied T1 has already been skull-stripped. As a default, we assume it is not skull stripped. *Please note this feature requires a well-stripped T1 as stripping artifacts can affect performance.*

**--no_smoothing**

By default, Gaussian kernel with standard deviation 1.15 mm were applied to BOLD_d to match the smoothness of the synthetic image. This flag alters the default behavior and skip the smoothing step.

**--custom_cnf**

User can configurate their own cnf file for topup.

**--total_readout_time**

User can specify readout time, in seconds, by adding a desired number after (with a space) this flag. Any argument after this flag will be saved as the new total_readout_time. By default, the readout time of distortion BOLD image is 0.05. 


## Inputs

The INPUTS directory must contain the following:

* BOLD_d.nii.gz: the distorted BOLD image, phase encoded on the anterior-posterior axis (either raw 4D, motion corrected 4D, or averaged 3D, see [Flags](#flags))
* T1.nii.gz: the T1-weighted image (either raw, or skull-stripped, see [Flags](#flags))

## Outputs

After running, the OUTPUTS directory contains the following preprocessing files:

* BOLD_d_mc.nii.gz: motion corrected 4D input if not --motion_corrected, otherwise a copy of the input
* BOLD_d_3D.nii.gz: average of BOLD_d_mc.nii.gz if input is 4D, otherwise a copy of the input
* T1_mask.nii.gz: brain extracted (skull-stripped) T1 if input is not stripped, otherwise a copy of the input
* T1_norm.nii.gz: normalized T1
* epi_reg_d.mat: epi_reg BOLD to T1 in FSL format
* epi_reg_d_ANTS.txt: epi_reg to T1 in ANTS format
* ANTS0GenericAffine.mat: Affine ANTs registration of T1_norm to/from MNI space
* ANTS1Warp.nii.gz: Deformable ANTs registration of T1_norm to/from MNI space  
* ANTS1InverseWarp.nii.gz: Inverse deformable ANTs registration of T1_norm to/from MNI space  
* T1_norm_lin_atlas_2_5.nii.gz: linear transform T1 to MNI
* BOLD_d_3D_lin_atlas_2_5.nii.gz: linear transform distorted BOLD in MNI space
* output.log: Logs of the pipeline

The OUTPUTS directory also contains inferences (predictions) for each of five folds utilizing T1_norm_lin_atlas_2_5.nii.gz and BOLD_d_3D_lin_atlas_2_5 as inputs:

* BOLD_s_3D_lin_atlas_2_5_FOLD_1.nii.gz 
* BOLD_s_3D_lin_atlas_2_5_FOLD_2.nii.gz
* BOLD_s_3D_lin_atlas_2_5_FOLD_3.nii.gz  
* BOLD_s_3D_lin_atlas_2_5_FOLD_4.nii.gz  
* BOLD_s_3D_lin_atlas_2_5_FOLD_5.nii.gz  

After inference the ensemble average is taken in atlas space:

* BOLD_s_3D_lin_atlas_2_5_merged.nii.gz  
* BOLD_s_3D_lin_atlas_2_5.nii.gz         

It is then moved to native space for the undistorted, synthetic output:

* BOLD_s_3D.nii.gz: Synthetic BOLD native space              

The undistorted synthetic output, and a smoothed distorted input can then be stacked together for topup:

* BOLD_d_3D_smooth.nii.gz: smoothed BOLD_d_3D.nii.gz
* BOLD_all.nii.gz: stack of BOLD_d_3D_smooth.nii.gz and BOLD_s_3D.nii.gz for input to topup        

Finally, the topup outputs if --notopup is not flagged:

* BOLD_all_topup.nii.gz: the topped-up version of BOLD_all output from topup
* topup_results_movpar.txt: topup parameters
* topup_results_field.nii.gz: The estimated field in Hz. The information is same as topup_results_fieldcoef.nii.gz but
  this file contains the acutal voxel values.
* topup_results_fieldcoef.nii.gz: topup field coefficients
* BOLD_u.nii.gz: topup applied to BOLD_d_mc (the final distortion corrected BOLD image)
* BOLD_u_3D.nii.gz: average of BOLD_u.nii.gz
