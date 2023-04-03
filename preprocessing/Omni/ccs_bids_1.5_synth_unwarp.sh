#!/bin/bash

ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=10
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS

while test $# -gt 0; do
    case "$1" in   
        -d)
            shift
            if test $# -gt 0; then
                export base_directory=$1
            else
                echo "No base directory specified (path/to/subject_folder)"
                exit 1
            fi
            shift
            ;;
        --subject*)
            shift
            if test $# -gt -0; then
                export subject=$1
            else
                echo "No subject ID specified (sub-******)"
            fi
            shift
            ;;
        --session*)
			shift
			if test $# -gt 0; then
				export session=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify session number"
			fi
			shift
			;;
        --run*)
            shift
			if test $# -gt 0; then
				export run=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify run number"
			fi
			shift
			;;
        --func-name*)
            shift
			if test $# -gt 0; then
				export rest=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify session number"
			fi
			shift
			;;
        --program*)
            shift
            if test $# -gt 0; then
                export program=`echo $1 | sed -e 's/^[^=]*=//g'`
            else
                echo "Specify program (default = 'fsl')"
            fi
            shift
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
done

exec > >(tee "Logs/${subject}/1.5_synth_unwarp_log.txt") 2>&1
set -x 

working_dir=`pwd`

if [ -z $program ]; then
    export program=fsl
fi

## Setting up common directories
func_dir=${base_directory}/${subject}/${session}
anat_dir=${base_directory}/${subject}/${session}/anat
fmap_dir=${base_directory}/${subject}/${session}/fmap
Omni_dir=${working_dir}/preprocessing/Omni

## Debiasing and generating EPI reference
echo "Debiasing EPI data..."
fslroi ${func_dir}/func_minimal/${rest}_mc.nii.gz ${func_dir}/func_minimal/epi_reference_raw.nii.gz 7 1
N4BiasFieldCorrection -i ${func_dir}/func_minimal/epi_reference_raw.nii.gz -d 3 -o ${func_dir}/func_minimal/epi_reference_temp.nii.gz

## Debiasing anatomical images
echo "Debiasing anatomicals..."
mkdir ${anat_dir}/Synth-Unwarp
N4BiasFieldCorrection -i ${anat_dir}/${subject}_${session}_${run}_T1w.nii.gz -d 3 -o ${anat_dir}/Synth-Unwarp/${subject}_${session}_${run}_T1w_bc.nii.gz
N4BiasFieldCorrection -i ${anat_dir}/${subject}_${session}_${run}_T2w.nii.gz -d 3 -o ${anat_dir}/Synth-Unwarp/${subject}_${session}_${run}_T2w_bc.nii.gz

# GETTING DIMENSIONS OF IMAGE
pixdim1=`fslinfo ${func_dir}/func_minimal/epi_reference_raw.nii.gz | grep pixdim1`
pixdim1=`echo $pixdim1 | cut -d " " -f 2`
pixdim2=`fslinfo ${func_dir}/func_minimal/epi_reference_raw.nii.gz | grep pixdim2`
pixdim2=`echo $pixdim2 | cut -d " " -f 2`
pixdim3=`fslinfo ${func_dir}/func_minimal/epi_reference_raw.nii.gz | grep pixdim3`
pixdim3=`echo $pixdim3 | cut -d " " -f 2`

## Z-SCORE EPI
echo "Z-scoring EPI data..."
mean=`fslstats ${func_dir}/func_minimal/epi_reference_temp.nii.gz -M`
stdev=`fslstats ${func_dir}/func_minimal/epi_reference_temp.nii.gz -S`
fslmaths ${func_dir}/func_minimal/epi_reference_temp.nii.gz -sub $mean -div $stdev ${func_dir}/func_minimal/epi_reference_zscore.nii.gz 
rm ${func_dir}/func_minimal/epi_reference_temp.nii.gz

## DEOBLIQUE FUNC DATA
echo "Deobliquing functional data..."
cp ${func_dir}/func_minimal/${rest}_mc.nii.gz ${func_dir}/func_minimal/${rest}_mc_dblq.nii.gz
3drefit -deoblique ${func_dir}/func_minimal/${rest}_mc_dblq.nii.gz

## synth unwarp
echo "Running synth unwarp..."
mkdir ${func_dir}/Synth-Unwarp
singularity exec --bind ${base_directory}/${subject}/${session}:/files ${Omni_dir}/omni_2022.6.23.sif omni_synthunwarp -o /files/Synth-Unwarp -x /files/anat/Synth-Unwarp/${subject}_${session}_${run}_T1w_bc.nii.gz -y /files/anat/Synth-Unwarp/${subject}_${session}_${run}_T2w_bc.nii.gz -m /files/anat/mask/brain_fs_mask.nii.gz -r /files/func_minimal/epi_reference_zscore.nii.gz -b /files/func_minimal/example_func_mask.nii.gz -e /files/func_minimal/${rest}_mc_dblq.nii.gz --program ${program}

## SQUEEZE OUT 5TH DIMENSION OF WARP FILE
echo "Squeezing dimension from warp file..."
python ${working_dir}/preprocessing/Omni/squeeze_warp.py ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz

## final unwarped func (also want to register to T1 space)
echo "Unwarping final data..."
cp ${anat_dir}/reg/highres.nii.gz ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz
3dresample -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -dxyz $pixdim1 $pixdim2 $pixdim3 -master ${func_dir}/func/${rest}.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_resampled.nii.gz -overwrite

## MAKING EDGE ##################
flirt -in ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -ref ${func_dir}/func_minimal/example_func_brain.nii.gz -omat ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_to_epi.mat -out ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain.nii.gz -dof 6

3dedge3 -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_edge.nii.gz -overwrite

3dedge3 -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain_edge.nii.gz -overwrite

# ${func_dir}/Synth-Unwarp/final_epi_to_anat.aff12.1D

3dNwarpApply -nwarp ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz -master ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_resampled.nii.gz -source ${func_dir}/func_minimal/${rest}_mc.nii.gz -prefix ${rest}_unwarped.nii.gz -overwrite

cp ${rest}_unwarped.nii.gz ${func_dir}/func_minimal/.

fslroi ${func_dir}/func_minimal/${rest}_unwarped.nii.gz ${func_dir}/func_minimal/example_func_unwarped.nii.gz 7 1
fslmaths ${func_dir}/func_minimal/example_func_unwarped.nii.gz -mas ${func_dir}/func_minimal/example_func_mask.nii.gz ${func_dir}/func_minimal/example_func_unwarped_brain.nii.gz


