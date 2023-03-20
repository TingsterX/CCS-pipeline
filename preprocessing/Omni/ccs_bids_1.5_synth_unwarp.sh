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
        *)
            print_usage
            exit 1
            ;;
    esac
done

exec > >(tee "Logs/${subject}/1.5_synth_unwarp_log.txt") 2>&1
set -x 

working_dir=`pwd`

## Setting up common directories
func_dir=${base_directory}/${subject}/${session}/func
anat_dir=${base_directory}/${subject}/${session}/anat
fmap_dir=${base_directory}/${subject}/${session}/fmap
Omni_dir=${working_dir}/preprocessing/Omni

## Setting example func
if [[ -f ${func_dir}/func_minimal/example_func_bc.nii.gz ]]; then
    example_func=example_func_bc.nii.gz
else
    example_func=example_func.nii.gz
fi

# GETTING DIMENSIONS OF IMAGE
pixdim1=`fslinfo ${func_dir}/func_minimal/example_func.nii.gz | grep pixdim1`
pixdim1=`echo $pixdim1 | cut -d " " -f 2`
pixdim2=`fslinfo ${func_dir}/func_minimal/example_func.nii.gz | grep pixdim2`
pixdim2=`echo $pixdim2 | cut -d " " -f 2`
pixdim3=`fslinfo ${func_dir}/func_minimal/example_func.nii.gz | grep pixdim3`
pixdim3=`echo $pixdim3 | cut -d " " -f 2`

## DEOBLIQUE FUNC DATA
echo "Deobliquing functional data..."
cp ${func_dir}/func_minimal/${rest}_dspk.nii.gz ${func_dir}/func_minimal/${rest}_dspk_dblq.nii.gz
3drefit -deoblique ${func_dir}/func_minimal/${rest}_dspk_dblq.nii.gz

## synth unwarp
#echo "Running synth unwarp..."
#mkdir ${func_dir}/Synth-Unwarp
#singularity exec --bind ${base_directory}/${subject}/${session}:/files ${Omni_dir}/omni_2022.6.23.sif omni_synthunwarp -o /files/func/Synth-Unwarp -x /files/anat/${subject}_${session}_${run}_T1w.nii.gz -y /files/anat/${subject}_${session}_${run}_T2w.nii.gz -m /files/anat/mask/brain_fs_mask.nii.gz -r /files/func/func_minimal/${example_func} -b /files/func/func_minimal/example_func_mask.nii.gz -e /files/func/func_minimal/${rest}_dspk_dblq.nii.gz

## SQUEEZE OUT 5TH DIMENSION OF WARP FILE
#echo "Squeezing dimension from warp file..."
#python ${working_dir}/preprocessing/Omni/squeeze_warp.py ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz

## final unwarped func (also want to register to T1 space)
echo "Unwarping final data..."
#cp ${anat_dir}/reg/highres.nii.gz ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz
3dresample -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -dxyz $pixdim1 $pixdim2 $pixdim3 -master ${func_dir}/${rest}.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_resampled.nii.gz -overwrite

## MAKING EDGE ################## (IN PROGRESS)
flirt -in ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -ref ${func_dir}/func_minimal/example_func_brain.nii.gz -omat ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_to_epi.mat -out ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain.nii.gz -dof 6

3dedge3 -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_edge.nii.gz -overwrite
3dedge3 -input ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain.nii.gz -prefix ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_in_epi_brain_edge.nii.gz -overwrite

3dNwarpApply -nwarp ${func_dir}/Synth-Unwarp/final_epi_to_anat.aff12.1D ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz -master ${func_dir}/Synth-Unwarp/input_data/${subject}_${session}_${run}_T1w_brain_resampled.nii.gz -source ${func_dir}/func_minimal/${rest}.nii.gz -prefix final_func_unwarped_anat_space.nii.gz -overwrite

flirt -in ${func_dir}/Synth-Unwarp/final_func_unwarped_anat_space.nii.gz -ref ${func_dir}/func_minimal/${example_func} -omat ${func_dir}/Synth-Unwarp/T1_to_epi.mat -dof 6

python3 ${working_dir}/preprocessing/Omni/affine_conversion.py -i ${func_dir}/Synth-Unwarp/T1_to_epi.mat -f FSL -o ${func_dir}/Synth-Unwarp/T1_to_epi.aff12.1D

@Align_Centers -base ${func_dir}/func_minimal/${example_func} -dset ${func_dir}/Synth-Unwarp/final_func_unwarped_anat_space.nii.gz -cm -prefix anat_centered_to_epi.nii.gz -overwrite

#mv $working_dir/anat_centered_to_epi.1D  ${DCAN_out}/Synth-Unwarp/.

3dAllineate -1Dmatrix_apply ${func_dir}/Synth-Unwarp/T1_to_epi.aff12.1D -warp shr -base ${func_dir}/func_minimal/${example_func} -prefix ${func_dir}/Synth-Unwarp/temp_func_space_unwarped.nii.gz -source ${func_dir}/Synth-Unwarp/anat_centered_to_epi.nii.gz -overwrite 

@Align_Centers -base ${func_dir}/func_minimal/${example_func} -dset ${func_dir}/Synth-Unwarp/temp_func_space_unwarped.nii.gz -cm -prefix final_func_unwarped_func_space.nii.gz -overwrite

3dNwarpCat -prefix ${func_dir}/Synth-Unwarp/concat_warp.nii.gz -warp1 ${func_dir}/Synth-Unwarp/final_epi_to_anat.aff12.1D -warp2 ${func_dir}/Synth-Unwarp/final_epi_to_synth_warp.nii.gz -warp3 ${func_dir}/Synth-Unwarp/anat_centered_to_epi.1D -warp4 ${func_dir}/Synth-Unwarp/T1_to_epi.aff12.1D -warp5 ${func_dir}/Synth-Unwarp/final_func_unwarped_func_space.1D -overwrite


