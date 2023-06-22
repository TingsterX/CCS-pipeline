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
  --use_prior_only=[true, false], use the prior directly, no refinement based on anatomical brain, default=false
  --use_automask_prior=[true, false], use 3dAutomask to generate a prior mask before refine from anatomical brain
  --mask_prior=[path], use the input (which should be aligned with example_func) as a prior mask before refine from anatomical brain
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
use_prior_only=`getopt1 "--use_anatuse_prior_only_refine" $@`
use_automask_prior=`getopt1 "--use_automask_prior" $@`
anat_dir=`getopt1 "--anat_dir" $@`
anat_ref_name=`getopt1 "--anat_ref_name" $@`
mask_prior=`getopt1 "--mask_prior" $@`
func_min_dir_name=`getopt1 "--out_dir_name" $@`


## default parameter
func=`defaultopt ${func_name} func`
ndvols=`defaultopt ${ndvols} 5`
example_volume=`defaultopt ${example_volume} 8`
use_automask_prior=`defaultopt ${use_automask_prior} true`
use_prior_only=`defaultopt ${use_prior_only} false`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing step 1: generate mask for minimal preprocessed dta"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "use_automask_prior=  ${use_automask_prior}"
Note "use_prior_only=      ${use_prior_only}"
Note "mask_prior=          ${mask_prior}"
Note "out_dir_name=        ${func_min_dir_name}"
echo "------------------------------------------------"

T1w_image=${anat_ref_name}_acpc_dc
anat_ref_head=${anat_dir}/${T1w_image}.nii.gz
anat_ref_brain=${anat_dir}/${T1w_image}_brain.nii.gz
anat_ref_mask=${anat_dir}/${T1w_image}_brain_mask.nii.gz
anat_ref_wm4bbr=${anat_dir}/segment/segment_wm+sub+stem.nii.gz
func_min_dir=${func_dir}/${func_min_dir_name}

# ----------------------------------------------------
if [ ! -f ${func_min_dir}/example_func_bc.nii.gz ] ; then
  Error "Input data ${func_min_dir}/example_func_bc.nii.gz does not exist"
  exit 1
fi

## If anat directory exist, check anat and anat_mask
if [ -z ${anat_dir} ]; then
  Error "Specify the preprocessed anatomical directory"
  exit 1
elif [ ! -e ${anat_ref_head} ] && [ ! -e ${anat_ref_brain} ] && [ ! -e ${anat_ref_mask} ]; then
  Error "${anat_ref_head} and/or ${anat_ref_mask} are/is not in specified anatomical directory"
  exit 1
fi

if [ ! -z ${mask_prior} ] && [ ! -f ${mask_prior} ]; then
  Error "The prior mask ${mask_prior} does not exist"
  exit 1
fi

#####################################################################################################################
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x 

# vcheck function 
vcheck_mask() {
	underlay=$1
	overlay=$2
	figout=$3
	echo "----->> vcheck mask"
	Do_cmd overlay 1 1 ${underlay} -a ${overlay} 1 1 tmp_rendered_mask.nii.gz
	Do_cmd slicer tmp_rendered_mask.nii.gz -S 10 1200 ${figout}
	Do_cmd rm -f tmp_rendered_mask.nii.gz
}


cwd=$( pwd )

mkdir ${func_min_dir}/masks
cd ${func_min_dir}

## Prior mask from 3dAutomask or prior 
if [[ ${use_automask_prior} = "true" ]]; then
  echo "Skull stripping (3dAutomask) for this func dataset"
  Do_cmd rm masks/${func}_mask.automD.nii.gz
  Do_cmd 3dAutomask -prefix masks/${func}_mask.automD.nii.gz -dilate 1 example_func_bc.nii.gz
  Do_cmd pushd ${func_min_dir}/masks
  Do_cmd ln -s ${func}_mask.automD.nii.gz ${func}_mask.initD.nii.gz
  Do_cmd popd
fi
if [ ! -z ${mask_prior} ]; then
  rm 
  Do_cmd 3dcopy ${mask_prior} masks/${func}_mask.prior.nii.gz 
  Do_cmd 3dmask_tool -input masks/${func}_mask.prior.nii.gz -dilate_input 1 -prefix masks/${func}_mask.priorD.nii.gz
  Do_cmd pushd ${func_min_dir}/masks
  Do_cmd ln -s ${func}_mask.priorD.nii.gz ${func}_mask.initD.nii.gz
  Do_cmd popd
fi

## refine the mask from the native anatomical image
if [ ${use_prior_only} = "false" ]; then
  if [ -f ${func_min_dir}/masks/${func}_mask.initD.nii.gz ]; then
    ## anatomical brain as reference to refine the functional mask
    Do_cmd fslmaths example_func_bc.nii.gz -mas ${func}_mask.initD.nii.gz tmpbrain.nii.gz
    # brain to brain initial registration
    Do_cmd flirt -in ${anat_ref_brain} -ref tmpbrain.nii.gz -out masks/${T1w_image}_To_example_func.nii.gz -omat masks/xfm_${T1w_image}_To_example_func.init.mat -cost corratio -dof 6 -interp spline
    Do_cmd convert_xfm -inverse -omat masks/xfm_example_func_To_${T1w_image}.init.mat masks/xfm_${T1w_image}_To_example_func.init.mat
    ## do flirt -bbr
    Do_cmd flirt -in tmpbrain.nii.gz -ref ${anat_ref_brain} -cost bbr -wmseg ${anat_ref_wm4bbr} -omat masks/xfm_example_func_To_${T1w_image}.mat -dof 6 -init masks/xfm_example_func_To_${T1w_image}.init.mat
    Do_cmd rm -v tmpbrain.nii.gz
  else
    # head to head initial registration
    Do_cmd flirt -in ${anat_ref_head} -ref example_func_bc.nii.gz -out masks/${T1w_image}_To_example_func.nii.gz -omat masks/xfm_${T1w_image}_To_example_func.init.mat -cost corratio -dof 6 -interp spline
    Do_cmd convert_xfm -inverse -omat masks/xfm_example_func_To_${T1w_image}.init.mat masks/xfm_${T1w_image}_To_example_func.init.mat
    ## do flirt -bbr
    Do_cmd flirt -in example_func_bc.nii.gz -ref ${anat_ref_head} -cost bbr -wmseg ${anat_ref_wm4bbr} -omat masks/xfm_example_func_To_${T1w_image}.mat -dof 6 -init masks/xfm_example_func_To_${T1w_image}.init.mat 
  fi
  Do_cmd convert_xfm -inverse -omat masks/xfm_${T1w_image}_To_example_func.mat masks/xfm_example_func_To_${T1w_image}.mat
  Do_cmd rm -f masks/${T1w_image}_maskD.nii.gz
  Do_cmd 3dmask_tool -input ${anat_ref_mask} -dilate_input 1 -prefix masks/${T1w_image}_maskD.nii.gz
  Do_cmd flirt -ref example_func.nii.gz -in masks/${T1w_image}_maskD.nii.gz -applyxfm -init masks/xfm_${T1w_image}_To_example_func.mat -interp nearestneighbour -out masks/${func}_mask.anatD.nii.gz
  # fill holes
  Do_cmd rm -f masks/${func}_mask.nii.gz
  Do_cmd 3dmask_tool -input masks/${func}_mask.anatD.nii.gz -prefix masks/${func}_mask.nii.gz -fill_holes  
else
  # Use the prior directly, remove the holes
  rm -f masks/${func}_mask.nii.gz
  Do_cmd 3dmask_tool -input masks/${func}_mask.prior.nii.gz -prefix masks/${func}_mask.nii.gz -fill_holes
fi

Do_cmd fslmaths example_func.nii.gz -mas masks/${func}_mask.nii.gz example_func_brain.nii.gz
Do_cmd fslmaths example_func_bc.nii.gz -mas masks/${func}_mask.nii.gz example_func_bc_brain.nii.gz

Do_cmd vcheck_mask example_func_bc.nii.gz masks/${func}_mask.nii.gz masks/${func}_mask.png

cd ${cwd}
