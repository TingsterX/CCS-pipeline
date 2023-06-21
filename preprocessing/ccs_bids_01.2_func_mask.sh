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
  --use_anat_mask_only=[true, false], use anatomical mask only, otherwise will use 3dAutomask as well, default=false
  --mask_prior=[path], use the input (which should be aligned with example_func) as a prior mask 
  --func_min_dir_name=[func_minimal], default=func_minimal
  --rm_exist=[true, false], clear up all existing preprocessed files and re-do this step.
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
use_anat_mask_only=`getopt1 "--use_anat_mask_only" $@`
anat_dir=`getopt1 "--anat_dir" $@`
anat_ref_name=`getopt1 "--anat_ref_name" $@`
mask_prior=`getopt1 "--mask_prior" $@`
func_min_dir_name=`getopt1 "--out_dir_name" $@`
rm_exist=`getopt1 "--rm_exist" $@`


## default parameter
func=`defaultopt ${func_name} func`
ndvols=`defaultopt ${ndvols} 5`
example_volume=`defaultopt ${example_volume} 8`
use_anat_mask_only=`defaultopt ${use_anat_mask_only} false`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`
rm_exist=`defaultopt ${rm_exist} true`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

## Show parameters in log file
Title "func preprocessing step 1: minimal preprocessing"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "example_volume=      ${example_volume}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "anat_dir=            ${anat_dir}"
Note "use_anat_mask_only=  ${use_anat_mask_only}"
Note "mask_prior=          ${mask_prior}"
Note "out_dir_name=        ${func_min_dir_name}"
Note "rm_exist=            ${rm_exist}"
echo "------------------------------------------------"


anat_ref_head=${anat_dir}/${anat_ref_name}_acpc_dc.nii.gz
anat_ref_brain=${anat_dir}/${anat_ref_name}_acpc_dc_brain.nii.gz
anat_ref_mask=${anat_dir}/${anat_ref_name}_acpc_dc_mask.nii.gz
func_min_dir=${func_dir}/${func_min_dir_name}

# ----------------------------------------------------
if [ ! -f ${func_dir}/example_func_bc.nii.gz ] ; then
  Error "Input data ${func_dir}/example_func_bc.nii.gz does not exist"
  exit 1
fi

## If anat directory exist, check anat and anat_mask
if [ -z ${anat_dir} ]; then
  Error "Specify the preprocessed anatomical directory"
  exit 1
elif [ ! -e ${anat_ref_head} ] && [ ! -e ${anat_ref_brain} ] && [ ! -e ${anat_ref_mask} ]; then
  Error "${anat_ref_head} and/or ${anat_ref_mask} are/is in specified anatomical directory"
  exit 1
fi

#####################################################################################################################
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x 

cwd=$( pwd )

##7 Initial func_pp_mask.init
if [ ${use_anat_mask_only} = "false" ]; then
  if [[ ! -f ${func}_mask.initD.nii.gz ]]; then
    echo "Skull stripping for this func dataset"
    rm ${func}_mask.initD.nii.gz
    3dAutomask -prefix ${func}_mask.initD.nii.gz -dilate 1 example_func_bc.nii.gz
  fi
  ${mask_prior}
  ## anatomical brain as reference to refine the functional mask
  fslmaths example_func_bc.nii.gz -mas ${func}_mask.initD.nii.gz tmpbrain.nii.gz
  flirt -ref ${anat_ref_brain} -in tmpbrain.nii.gz -out mask/example_func2highres_rpi4mask -omat mask/example_func2highres_rpi4mask.mat -cost corratio -dof 6 -interp trilinear 
  ## Create mat file for conversion from subject's anatomical to functional
  convert_xfm -inverse -omat mask/highres_rpi2example_func4mask.mat mask/example_func2highres_rpi4mask.mat
  flirt -ref example_func -in ${highres_rpi} -out tmpT1.nii.gz -applyxfm -init mask/highres_rpi2example_func4mask.mat -interp trilinear
  fslmaths tmpT1.nii.gz -bin -dilM mask/brainmask2example_func.nii.gz
  #rm -v tmp*.nii.gz

  fslmaths ${func}_mc.nii.gz -Tstd -bin ${func}_pp_mask.init.nii.gz #Rationale: any voxels with detectable signals should be included as in the global mask
  fslmaths ${func}_pp_mask.init.nii.gz -mul ${func}_mask.initD.nii.gz -mul mask/brainmask2example_func.nii.gz ${func}_pp_mask.init.nii.gz -odt char
  fslmaths example_func.nii.gz -mas ${func}_pp_mask.init.nii.gz example_func_brain.init.nii.gz
  fslmaths example_func_bc.nii.gz -mas ${func}_pp_mask.init.nii.gz example_func_brain_bc.init.nii.gz
fi

cd ${cwd}
