#!/bin/bash

TOPUP=true
motion_corrected=false

for arg in "$@"
do
    case $arg in
        -nt|--notopup)
            TOPUP=false
	        ;;
        -mc|--motion_corrected)
            motion_corrected=true
            ;;
    esac
done

# setup freesurfer
source $FREESURFER_HOME/SetUpFreeSurfer.sh

cd /home/INPUTS

# check file existence
if [ ! -f T1.nii.gz ]; then
    echo "T1.nii.gz not found"
    exit 1
fi

if [ ! -f BOLD_d.nii.gz ]; then
    echo "BOLD_d.nii.gz not found"
    exit 1
fi

INPUTS_PATH=/home/INPUTS
RESULTS_PATH=/home/OUTPUTS
T1_ATLAS_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c.nii
T1_ATLAS_2_5_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c_2_5.nii
model_path=/home/Models
T1_PATH=$INPUTS_PATH/T1.nii.gz
BOLD_PATH=$RESULTS_PATH/BOLD_d.nii.gz
BOLD_d_mc=$RESULTS_PATH/BOLD_d_mc.nii.gz
BOLD_d_3D=$RESULTS_PATH/BOLD_d_3D.nii.gz


# always use sform
cp BOLD_d.nii.gz $BOLD_PATH
if [[ $(fslorient -getsformcode $BOLD_PATH) -eq 1 ]] && [[ $(fslorient -getqformcode $BOLD_PATH) -eq 1 ]]; then
    fslorient -setqformcode 0 $BOLD_PATH
fi

dimension=$(mrinfo $BOLD_PATH -ndim)

if [[ $dimension -eq 3 ]]; then
    cp $BOLD_PATH $BOLD_d_mc
    cp $BOLD_d_mc $BOLD_d_3D
elif [[ $dimension -eq 4 ]]; then
    if $motion_corrected; then
        cp $BOLD_PATH $BOLD_d_mc
        mrmath $BOLD_d_mc mean $BOLD_d_3D -axis 3 -force
    else
        mcflirt -in $BOLD_PATH -meanvol -out $RESULTS_PATH/rBOLD -plots
        mv $RESULTS_PATH/rBOLD.nii.gz $BOLD_d_mc
        mv $RESULTS_PATH/rBOLD_mean_reg.nii.gz $BOLD_d_3D
    fi
else
    echo "BOLD_d.nii.gz Incorrect Dimension"
fi

# Normalize T1
echo -------
echo Normalizing T1
mri_convert $T1_PATH ${RESULTS_PATH}/T1.mgz
mri_nu_correct.mni --i ${RESULTS_PATH}/T1.mgz --o ${RESULTS_PATH}/T1_N3.mgz --n 2
mri_convert ${RESULTS_PATH}/T1_N3.mgz ${RESULTS_PATH}/T1_N3.nii.gz
mri_normalize -g 1 -mprage ${RESULTS_PATH}/T1_N3.mgz ${RESULTS_PATH}/T1_norm.mgz
mri_convert ${RESULTS_PATH}/T1_norm.mgz ${RESULTS_PATH}/T1_norm.nii.gz

# Skull strip T1
echo -------
echo Skull stripping T1
bet $T1_PATH ${RESULTS_PATH}/T1_mask.nii.gz -R

# epi_reg distorted BOLD to T1; wont be perfect since BOLD is distorted
echo -------
echo epi_reg distorted BOLD to T1
epi_reg --epi=$BOLD_d_3D --t1=$T1_PATH --t1brain=${RESULTS_PATH}/T1_mask.nii.gz --out=${RESULTS_PATH}/epi_reg_d

# Convert FSL transform to ANTS transform
echo -------
echo converting FSL transform to ANTS transform
c3d_affine_tool -ref $T1_PATH -src $BOLD_d_3D ${RESULTS_PATH}/epi_reg_d.mat -fsl2ras -oitk ${RESULTS_PATH}/epi_reg_d_ANTS.txt

# ANTs register T1 to atlas
echo -------
echo ANTS syn registration
antsRegistrationSyNQuick.sh -d 3 -f $T1_ATLAS_PATH -m $T1_PATH -o ${RESULTS_PATH}/ANTS

# Apply linear transform to normalized T1 to get it into atlas space
echo -------
echo Apply linear transform to T1
antsApplyTransforms -d 3 -i ${RESULTS_PATH}/T1_norm.nii.gz -r $T1_ATLAS_2_5_PATH -n BSpline -t ${RESULTS_PATH}/ANTS0GenericAffine.mat -o ${RESULTS_PATH}/T1_norm_lin_atlas_2_5.nii.gz

# Apply linear transform to N3 T1 to get it into atlas space
echo -------
echo Apply linear transform to T1 N3
antsApplyTransforms -d 3 -i ${RESULTS_PATH}/T1_N3.nii.gz -r $T1_ATLAS_2_5_PATH -n BSpline -t ${RESULTS_PATH}/ANTS0GenericAffine.mat -o ${RESULTS_PATH}/T1_N3_lin_atlas_2_5.nii.gz

# Apply linear transform to distorted BOLD to get it into atlas space
echo -------
echo Apply linear transform to distorted BOLD
antsApplyTransforms -d 3 -i $BOLD_d_3D -r $T1_ATLAS_2_5_PATH -n BSpline -t ${RESULTS_PATH}/ANTS0GenericAffine.mat -t ${RESULTS_PATH}/epi_reg_d_ANTS.txt -o ${RESULTS_PATH}/BOLD_d_3D_lin_atlas_2_5.nii.gz

cd $RESULTS_PATH
# Run inference
NUM_FOLDS=5
for i in $(seq 1 $NUM_FOLDS);
do 
  echo Performing inference on FOLD: "$i"
  python3 /home/inference.py T1_norm_lin_atlas_2_5.nii.gz BOLD_d_3D_lin_atlas_2_5.nii.gz BOLD_s_3D_lin_atlas_2_5_FOLD_$i.nii.gz $model_path/num_fold_${i}_total_folds_5_seed_1_num_epochs_120_lr_0.0001_betas_\(0.9,\ 0.999\)_weight_decay_1e-05_num_epoch_*.pth
done

# Take mean
echo Taking ensemble average
fslmerge -t BOLD_s_3D_lin_atlas_2_5_merged.nii.gz BOLD_s_3D_lin_atlas_2_5_FOLD_*.nii.gz
fslmaths BOLD_s_3D_lin_atlas_2_5_merged.nii.gz -Tmean BOLD_s_3D_lin_atlas_2_5.nii.gz

# Apply inverse xform to undistorted BOLD
echo Applying inverse xform to undistorted BOLD
antsApplyTransforms -d 3 -i BOLD_s_3D_lin_atlas_2_5.nii.gz -r $BOLD_d_3D -n BSpline -t [epi_reg_d_ANTS.txt,1] -t [ANTS0GenericAffine.mat,1] -o BOLD_s_3D.nii.gz

# Smooth image
echo Applying slight smoothing to distorted BOLD
fslmaths $BOLD_d_3D -s 1.15 BOLD_d_3D_smoothed.nii.gz

fslmerge -t BOLD_all BOLD_d_3D_smoothed.nii.gz BOLD_s_3D.nii.gz

if $TOPUP; then
    echo -e "0 1 0 1\n0 1 0 0" > acqparams.txt
    topup -v --imain=BOLD_all.nii.gz --datain=acqparams.txt --config=b02b0.cnf --iout=BOLD_all_topup --out=topup_results --subsamp=1,1,1,1,1,1,1,1,1 --miter=10,10,10,10,10,20,20,30,30 --lambda=0.00033,0.000067,0.0000067,0.000001,0.00000033,0.000000033,0.0000000033,0.000000000033,0.00000000000067 --scale=0
    applytopup --imain=$BOLD_d_mc --datain=acqparams.txt --inindex=1 --topup=topup_results --out=BOLD_u --method=jac

    dimension=$(mrinfo BOLD_u.nii.gz -ndim)
    echo $dimension

    if [[ $dimension -eq 4 ]]; then
        mrmath BOLD_u.nii.gz mean BOLD_u_3D.nii.gz -axis 3 -force
    elif [[ $dimension -eq 3 ]]; then
        cp BOLD_u.nii.gz BOLD_u_3D.nii.gz
    else
        echo "BOLD_u.nii.gz doesn't have correct dimension"
    fi
fi