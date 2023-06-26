#!/usr/bin/env bash

##########################################################################################################################
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, functional preprocessing
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Function Pipeline: brain extraction

Usage: ${0}
  --func_dir=<functional directory>, e.g. base_dir/subID/func/sub-X_task-X/
  --func_name=[func], name of the functional data, default=func (e.g. <func_dir>/func.nii.gz)
  --anat_dir=<anatomical directory>, specify the anat directory 
  --anat_ref_name=<T1w, T2w>, name of the anatomical reference name, default=T1w
  --anat_seg_name=[segment, segment_fast], name of the anatomical segmention directory, default=segment
  --dc_method=[none, topup, fugue, omni]
  --func_min_dir_name=[func_minimal], default=func_minimal
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
anat_seg_name=`getopt1 "--anat_seg_name" $@`
dc_method=`getopt1 "--dc_method" $@`
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`

## default parameter
func=`defaultopt ${func_name} func`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
anat_seg_name=`defaultopt ${anat_seg_name} segment`
dc_method=`defaultopt ${dc_method} none`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing step 1: generate mask for minimal preprocessed dta"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "dc_method=           ${dc_method}"
Note "func_min_dir_name=   ${func_min_dir_name}"
echo "------------------------------------------------"

T1w_image=${anat_ref_name}_acpc_dc
anat_ref_head=${anat_dir}/${T1w_image}.nii.gz
anat_ref_brain=${anat_dir}/${T1w_image}_brain.nii.gz
anat_ref_mask=${anat_dir}/${T1w_image}_brain_mask.nii.gz

anat_ref_gm=${anat_dir}/${anat_seg_name}/segment_gm.nii.gz
anat_ref_csf=${anat_dir}/${anat_seg_name}/segment_csf.nii.gz
anat_ref_wm=${anat_dir}/${anat_seg_name}/segment_wm_erode1.nii.gz

func_min_dir=${func_dir}/${func_min_dir_name}

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

func_pp_dir=${func_dir}/${func_pp_dir_name}
func_reg_dir=${func_dir}/${func_pp_dir_name}/xfms
func_seg_dir=${func_pp_dir}/segment
# ----------------------------------------------------

Title "Extract functional segmentation ..."

if [ ! -f ${anat_ref_wm} ] || [ ! -f ${anat_ref_csf} ] || [ ! -f ${anat_ref_gm} ]; then
  Error "!!! No wm/csf segment of anatomical images. Please check anatsurface preprocess"
  exit 1 
fi

## -----------------------------------------

## 
cwd=$( pwd )

## 2. Change to func dir
mkdir -p ${func_seg_dir}
cd ${func_seg_dir}

## Global (brainmask)
if [[ ! -f ${func_seg_dir}/global_mask.nii.gz ]]; then 
  Info ">> Registering global csf to raw func space"
  3dcopy ${func_pp_dir}/example_func_pp_mask.nii.gz ${func_seg_dir}/global_mask.nii.gz
  vcheck_mask_func ${func_min_dir}/example_func.nii.gz ${func_seg_dir}/global_mask.nii.gz ${func_seg_dir}/global_mask.png
fi

## CSF 
if [[ ! -f ${func_seg_dir}/csf_mask.nii.gz ]]; then
  Info ">> Registering anat csf (erode1) to raw func space"
  Do_cmd applywarp --rel --interp=nn --in=${anat_ref_csf} --ref=${func_min_dir}/example_func_bc.nii.gz --warp=${func_reg_dir}/${T1w_image}2func_mc.nii.gz --out=${func_seg_dir}/csf_mask.nii.gz
  Do_cmd fslmaths ${func_seg_dir}/csf_mask.nii.gz -mas ${func_seg_dir}/global_mask.nii.gz -bin ${func_seg_dir}/csf_mask.nii.gz
  Do_cmd vcheck_mask_func ${func_min_dir}/example_func.nii.gz ${func_seg_dir}/csf_mask.nii.gz ${func_seg_dir}/csf_mask.png
fi

## CSF 
if [[ ! -f ${func_seg_dir}/wm_mask.nii.gz ]]; then
  Info ">> Registering anat wm (erode1) to raw func space"
  Do_cmd applywarp --rel --interp=nn --in=${anat_ref_wm} --ref=${func_min_dir}/example_func_bc.nii.gz --warp=${func_reg_dir}/${T1w_image}2func_mc.nii.gz --out=${func_seg_dir}/wm_mask.nii.gz
  Do_cmd fslmaths ${func_seg_dir}/wm_mask.nii.gz -mas ${func_seg_dir}/global_mask.nii.gz -bin ${func_seg_dir}/wm_mask.nii.gz
  Do_cmd vcheck_mask_func ${func_min_dir}/example_func.nii.gz ${func_seg_dir}/wm_mask.nii.gz ${func_seg_dir}/wm_mask.png
fi

## GM
if [[ ! -f ${func_seg_dir}/gm_mask.nii.gz ]]; then
  Info ">> Registering anat gm to raw func space"
  Do_cmd applywarp --rel --interp=nn --in=${anat_ref_gm} --ref=${func_min_dir}/example_func_bc.nii.gz --warp=${func_reg_dir}/${T1w_image}2func_mc.nii.gz --out=${func_seg_dir}/gm_mask.nii.gz
  Do_cmd fslmaths ${func_seg_dir}/gm_mask.nii.gz -mas ${func_seg_dir}/global_mask.nii.gz -bin ${func_seg_dir}/gm_mask.nii.gz
  Do_cmd vcheck_mask_func ${func_min_dir}/example_func.nii.gz ${func_seg_dir}/gm_mask.nii.gz ${func_seg_dir}/gm_mask.png
fi

cd ${cwd}
