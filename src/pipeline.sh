#!/bin/bash

exec &> /OUTPUTS/output.log

total_readout_time=0.05

TOPUP=true
motion_corrected=false
skull_stripped=false
custom_cnf=false
no_smoothing=false

echo "Flag(s) received:"
if [ $# -eq 0 ]; then
    echo "  None"
fi

for ((i=1; i<=$#; i++)); do
    arg="${!i}"
    echo "  $arg"
    
    case $arg in
        -nt|--no_topup)
            TOPUP=false
            ;;
        -mc|--motion_corrected)
            motion_corrected=true
            ;;
        -ss|--skull_stripped)
            skull_stripped=true
            ;;
        --custom_cnf)
            custom_cnf=true
            ;;
        --no_smoothing)
            no_smoothing=true
            ;;
        --total_readout_time)
            ((i++))
            if [ $i -le $# ]; then
                total_readout_time=${!i}
            else
                echo "Error: Missing value for --total_readout_time"
                exit 1
            fi
            ;;
    esac
done

echo "Flags for this run:"
echo "  TOPUP: $TOPUP"
echo "  Motion Corrected: $motion_corrected"
echo "  Skull Stripped: $skull_stripped"
echo "  Custom Cnf: $custom_cnf"
echo "  No Smoothing: $no_smoothing"
echo "  Total Readout Time: $total_readout_time"

# setup freesurfer
source $FREESURFER_HOME/SetUpFreeSurfer.sh
source activate /opt/miniconda3

cd /INPUTS

# check file existence
if [ ! -f T1.nii.gz ]; then
    echo "T1.nii.gz not found"
    exit 1
fi

if [ ! -f BOLD_d.nii.gz ]; then
    echo "BOLD_d.nii.gz not found"
    exit 1
fi

if $custom_cnf; then
    count=$(ls /INPUTS/*.cnf | grep -c '.cnf')
    if [ $count -ne 1 ]; then
        echo "Error: Expected 1 .cnf file, found $count."
        exit 1
    fi
fi

INPUTS_PATH=/INPUTS
RESULTS_PATH=/OUTPUTS

if [ $skull_stripped ]; then
    T1_ATLAS_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c_mask.nii.gz
    T1_ATLAS_2_5_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c_mask_2_5.nii.gz
else
    T1_ATLAS_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c.nii.gz
    T1_ATLAS_2_5_PATH=/home/mni_icbm152_t1_tal_nlin_asym_09c_2_5.nii.gz
fi

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
if $skull_stripped; then
    echo Copying user-provided T1 Mask
    cp $T1_PATH ${RESULTS_PATH}/T1_mask.nii.gz
else
    echo Skull stripping T1
    bet $T1_PATH ${RESULTS_PATH}/T1_mask.nii.gz -R
fi

# epi_reg distorted BOLD to T1; wont be perfect since BOLD is distorted
echo -------
echo epi_reg distorted BOLD to T1

epi_reg \
  --epi=$BOLD_d_3D \
  --t1=$T1_PATH \
  --t1brain=${RESULTS_PATH}/T1_mask.nii.gz \
  --out=${RESULTS_PATH}/epi_reg_d

# Convert FSL transform to ANTS transform
echo -------
echo converting FSL transform to ANTS transform
c3d_affine_tool \
    -ref $T1_PATH \
    -src $BOLD_d_3D ${RESULTS_PATH}/epi_reg_d.mat \
    -fsl2ras \
    -oitk ${RESULTS_PATH}/epi_reg_d_ANTS.txt

# ANTs register T1 to atlas
echo -------
echo ANTS syn registration
antsRegistrationSyNQuick.sh -d 3 -f $T1_ATLAS_PATH -m $T1_PATH -o ${RESULTS_PATH}/ANTS

# Apply linear transform to normalized T1 to get it into atlas space
echo -------
echo Apply linear transform to T1
antsApplyTransforms \
  -d 3 \
  -i ${RESULTS_PATH}/T1_norm.nii.gz \
  -r $T1_ATLAS_2_5_PATH \
  -n BSpline \
  -t ${RESULTS_PATH}/ANTS0GenericAffine.mat \
  -o ${RESULTS_PATH}/T1_norm_lin_atlas_2_5.nii.gz

# Apply linear transform to N3 T1 to get it into atlas space
echo -------
echo Apply linear transform to T1 N3
antsApplyTransforms \
  -d 3 \
  -i ${RESULTS_PATH}/T1_N3.nii.gz \
  -r $T1_ATLAS_2_5_PATH \
  -n BSpline \
  -t ${RESULTS_PATH}/ANTS0GenericAffine.mat \
  -o ${RESULTS_PATH}/T1_N3_lin_atlas_2_5.nii.gz

# Apply linear transform to distorted BOLD to get it into atlas space
echo -------
echo Apply linear transform to distorted BOLD
antsApplyTransforms \
  -d 3 \
  -i $BOLD_d_3D \
  -r $T1_ATLAS_2_5_PATH \
  -n BSpline \
  -t ${RESULTS_PATH}/ANTS0GenericAffine.mat \
  -t ${RESULTS_PATH}/epi_reg_d_ANTS.txt \
  -o ${RESULTS_PATH}/BOLD_d_3D_lin_atlas_2_5.nii.gz

cd $RESULTS_PATH
# Run inference
NUM_FOLDS=5
for i in $(seq 1 $NUM_FOLDS);
do 
  echo Performing inference on FOLD: "$i"
  python3 /home/inference.py \
        T1_norm_lin_atlas_2_5.nii.gz \
        BOLD_d_3D_lin_atlas_2_5.nii.gz \
        BOLD_s_3D_lin_atlas_2_5_FOLD_$i.nii.gz \
        $model_path/num_fold_${i}_total_folds_5_seed_1_num_epochs_120_lr_0.0001_betas_\(0.9,\ 0.999\)_weight_decay_1e-05_num_epoch_*.pth
done

# Take mean
echo Taking ensemble average
fslmerge -t BOLD_s_3D_lin_atlas_2_5_merged.nii.gz BOLD_s_3D_lin_atlas_2_5_FOLD_*.nii.gz
fslmaths BOLD_s_3D_lin_atlas_2_5_merged.nii.gz -Tmean BOLD_s_3D_lin_atlas_2_5.nii.gz

# Apply inverse xform to undistorted BOLD
echo Applying inverse xform to undistorted BOLD
antsApplyTransforms \
  -d 3 \
  -i BOLD_s_3D_lin_atlas_2_5.nii.gz \
  -r $BOLD_d_3D \
  -n BSpline \
  -t [epi_reg_d_ANTS.txt,1] \
  -t [ANTS0GenericAffine.mat,1] \
  -o BOLD_s_3D.nii.gz

# Smooth image
if ! $no_smoothing; then
    echo Applying slight smoothing to distorted BOLD
    fslmaths $BOLD_d_3D -s 1.15 BOLD_d_3D_smoothed.nii.gz
    fslmerge -t BOLD_all BOLD_d_3D_smoothed.nii.gz BOLD_s_3D.nii.gz
else
    fslmerge -t BOLD_all $BOLD_d_3D BOLD_s_3D.nii.gz
fi

if $TOPUP; then
    echo -e "0 1 0 ${total_readout_time}\n0 1 0 0" > acqparams.txt

    data_matrix=($(mrinfo $BOLD_PATH -size))
    all_even=true

    for i in {0..2}; do
        if (( $((data_matrix[i])) % 2 == 1 )); then
            all_even=false
            echo "odd dimension detected"
            break
        fi
    done

    if $custom_cnf; then
        cnf=$(ls /INPUTS/*.cnf | head -n 1)
        cp $cnf .
    elif $all_even; then
        cnf=b02b0_2.cnf
        cp /opt/fsl/src/fsl-topup/flirtsch/b02b0_2.cnf .
    else
        cnf=b02b0_1.cnf
        cp /opt/fsl/src/fsl-topup/flirtsch/b02b0_1.cnf .
    fi

    topup -v \
        --imain=BOLD_all.nii.gz \
        --datain=acqparams.txt \
        --config=${cnf} \
        --iout=BOLD_all_topup \
        --fout=topup_results_field \
        --out=topup_results \
         
    applytopup --imain=$BOLD_d_mc \
               --datain=acqparams.txt \
               --inindex=1 \
               --topup=topup_results \
               --out=BOLD_u \
               --method=jac

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