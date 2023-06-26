#!/usr/bin/env bash

##########################################################################################################################
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, functional preprocessing
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Function Pipeline: registration (func->std) 

Usage: ${0}
  --func_dir=<functional directory>, e.g. base_dir/subID/func/sub-X_task-X/
  --func_name=[func], name of the functional data, default=func (e.g. <func_dir>/func.nii.gz)
  --anat_dir=<anatomical directory>, specify the anat directory 
  --anat_ref_name=[T1w, T2w], name of the anatomical reference name, default=T1w
  --dc_method=[none, topup, fugue, omni], default=none
  --func_min_dir_name=[func_minimal], default=func_minimal
  --ref_brain=<reference brain>, path fo the reference brain that match with the write_out_res resolution
EOF
}

# Return a Usage statement
if [ "$#" = "0" ]; then
    Usage
    exit 1
fi

# function for parsing options
getopt1() {
  sopt="$1"
  shift 1
  for fn in $@ ; do
    if [ `echo $fn | grep -- "^${sopt}=" | wc -w` -gt 0 ] ; then
     echo $fn | sed "s/^${sopt}=//"
     return 0
    fi
  done
}

defaultopt() {
    echo $1
}

source ${CCSPIPELINE_DIR}/global/utilities.sh
## arguments pasting
func_dir=`getopt1 "--func_dir" $@`
func_name=`getopt1 "--func_name" $@`
anat_dir=`getopt1 "--anat_dir" $@`
anat_ref_name=`getopt1 "--anat_ref_name" $@`
ref_brain=`getopt1 "--ref_brain" $@`
dc_method=`getopt1 "--dc_method" $@`
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`

## default parameter
func=`defaultopt ${func_name} func`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
dc_method=`defaultopt ${dc_method} none`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`
ref_brain=`defaultopt ${ref_brain} ${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing step 1: generate mask for minimal preprocessed dta"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "ref_brain=           ${ref_brain}"
Note "dc_method=           ${dc_method}"
Note "func_min_dir_name=   ${func_min_dir_name}"
echo "------------------------------------------------"

# set func_reg_dir
if [ ${dc_method} = "none" ]; then
  func_pp_dir_name=func_non_dc
elif [ ${dc_method} = "topup" ]; then
  func_pp_dir_name=func_dc_topup
elif [ ${dc_method} = "fugue" ]; then
  func_pp_dir_name=func_dc_fugue
elif [ ${dc_method} = "omni" ]; then
  func_pp_dir_name=func_dc_omni
else
  Error "--dc_method distortion correction method has to be none, topup, fugue, omni"
  exit 1
fi

T1w_image=${anat_ref_name}_acpc_dc
anat_ref_head=${anat_dir}/${T1w_image}.nii.gz

atlas_space_dir=${anat_dir}/TemplateSpace
func_min_dir=${func_dir}/${func_min_dir_name}
epi_bc_raw=${func_min_dir}/example_func_bc.nii.gz
func_pp_dir=${func_dir}/${func_pp_dir_name}
func_reg_dir=${func_dir}/${func_pp_dir_name}/xfms

xfm_raw2unwarp=${func_reg_dir}/raw2unwarped.nii.gz
xfm_unwarp2raw=${func_reg_dir}/unwarped2raw.nii.gz
xfm_func2anat=${func_reg_dir}/xfm_example_func_To_${T1w_image}.mat
xfm_anat2func=${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat
xfm_anat2std=${atlas_space_dir}/xfms/acpc_dc2standard.nii.gz
xfm_std2anat=${atlas_space_dir}/xfms/standard2acpc_dc.nii.gz
Transform=${func_pp_dir}/xfms/example_func2
##------------------------------------------------

cwd=$( pwd )
##------------------------------------------------
## combine warp
cd ${func_reg_dir}
if [ ${dc_method} = "none" ]; then
  Info "Combine warp for non-distortion corrected data ..."
  Do_cmd convertwarp --relout --rel --ref=${anat_ref_head} --premat=${xfm_func2anat} --out=${func_reg_dir}/func_mc2${T1w_image}.nii.gz
  Do_cmd convertwarp --relout --rel --ref=${epi_bc_raw} --premat=${xfm_anat2func} --out=${func_reg_dir}/${T1w_image}2func_mc.nii.gz

  Do_cmd convertwarp --relout --rel --ref=${ref_brain} --premat=${xfm_func2anat} --warp1=${xfm_anat2std} --out=${func_reg_dir}/func_mc2standard.nii.gz
  Do_cmd convertwarp --relout --rel --ref=${epi_bc_raw} --warp1=${xfm_std2anat} --postmat=${xfm_anat2func} --out=${func_reg_dir}/standard2func_mc.nii.gz
else
  Info "Combine warp for distortion corrected data ..."
  # func raw <-> anat acpc_dc
  Do_cmd convertwarp --relout --rel --ref=${anat_ref_head} --warp1=${xfm_raw2unwarp} --postmat=${xfm_func2anat} --out=${func_reg_dir}/func_mc2${T1w_image}.nii.gz
  Do_cmd convertwarp --relout --rel --ref=${epi_bc_raw} --premat=${xfm_anat2func} --warp1=${xfm_unwarp2raw} --out=${func_reg_dir}/${T1w_image}2func_mc.nii.gz
  # func raw <-> standard
  Do_cmd convertwarp --relout --rel --ref=${ref_brain} --warp1=${func_reg_dir}/func_mc2${T1w_image}.nii.gz --warp2=${xfm_anat2std} --out=${func_reg_dir}/func_mc2standard.nii.gz
  Do_cmd convertwarp --relout --rel --ref=${func_min_dir}/example_func.nii.gz --warp1=${xfm_std2anat} --warp1=${func_reg_dir}/${T1w_image}2func_mc.nii.gz --out=${func_reg_dir}/standard2func_mc.nii.gz
fi
##------------------------------------------------
Info "Apply warps to the motion corrected data (func_mc) ..."
## apply warp
Do_cmd applywarp --rel --interp=spline --in=${epi_bc_raw} --ref=${ref_brain} --warp=${func_reg_dir}/func_mc2standard.nii.gz --out=${func_reg_dir}/vcheck/func_mc_To_standard.nii.gz
Do_cmd applywarp --rel --interp=spline --in=${ref_brain} --ref=${epi_bc_raw} --warp=${func_reg_dir}/standard2func_mc.nii.gz --out=${func_reg_dir}/vcheck/standard_To_func_mc.nii.gz
##------------------------------------------------
Info "Generate quality vcheck figures ..."
Do_cmd vcheck_reg ${epi_bc_raw} ${func_reg_dir}/vcheck/standard_To_func_mc.nii.gz ${func_reg_dir}/vcheck/figure_func_mc_with_standard_brain_boundary.png ${func_min_dir}/masks/${func}_mask.nii.gz
Do_cmd fslmaths ${ref_brain} ${func_reg_dir}/vcheck/standard_mask.nii.gz
Do_cmd vcheck_reg ${func_reg_dir}/vcheck/func_mc_To_standard.nii.gz ${ref_brain} ${func_reg_dir}/vcheck/figure_func_mc_To_standard_with_std_brain_boundary.png ${func_reg_dir}/vcheck/standard_mask.nii.gz
Do_cmd rm ${func_reg_dir}/vcheck/standard_mask.nii.gz

##--------------------------------------------
## Back to the directory
cd ${cwd}
