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
  --dc_method=[none, topup, fugue, omni]
  --dc_dir=[path to the distortion corrected directory which contains example_func_bc_dc.nii.gz]
  --reg_method=[flirt, flirbbr, fsbbr]
  --func_min_dir_name=[func_minimal], default=func_minimal
  --SUBJECTS_DIR=[path to the FreeSurfer folder], specify this option if using fsbbr
  --subject=[subject ID used in FreeSurfer], specify this option if using fsbbr
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
dc_method=`getopt1 "--dc_method" $@`
dc_dir=`getopt1 "--dc_dir" $@`
reg_method=`getopt1 "--reg_method" $@`
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`
SUBJECTS_DIR=`getopt1 "--SUBJECTS_DIR" $@`
subject=`getopt1 "--subject" $@`

## default parameter
func=`defaultopt ${func_name} func`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
dc_method=`defaultopt ${dc_method} none`
reg_method=`defaultopt ${reg_method} flirtbbr`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`
SUBJECTS_DIR=`defaultopt ${SUBJECTS_DIR} ${anat_dir}/${subject}`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing step 1: generate mask for minimal preprocessed dta"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "dc_method=           ${dc_method}"
Note "dc_dir=              ${dc_dir}"
Note "reg_method=          ${reg_method}"
Note "func_min_dir_name=   ${func_min_dir_name}"
Note "SUBJECTS_DIR=        ${SUBJECTS_DIR}"
Note "subject=             ${subject}"
echo "------------------------------------------------"

T1w_image=${anat_ref_name}_acpc_dc
anat_ref_head=${anat_dir}/${T1w_image}.nii.gz
anat_ref_brain=${anat_dir}/${T1w_image}_brain.nii.gz
anat_ref_mask=${anat_dir}/${T1w_image}_brain_mask.nii.gz
anat_ref_wm4bbr=${anat_dir}/segment/segment_wm+sub+stem.nii.gz
anat_ref_gm=${anat_dir}/segment/segment_gm.nii.gz
func_min_dir=${func_dir}/${func_min_dir_name}

# ----------------------------------------------------
if [ ! -f ${func_min_dir}/example_func_bc.nii.gz ] || [ ! -f ${func_min_dir}/example_func_bc_brain.nii.gz ]; then
  Error "example_func_bc.nii.gz or example_func_bc_brain.nii.gz does not exist in ${func_min_dir}"
  exit 1
fi

## If anat directory exist, check anat and anat_mask
if [ -z ${anat_dir} ]; then
  Error "Specify the preprocessed anatomical directory"
  exit 1
elif [ ! -e ${anat_ref_head} ] && [ ! -e ${anat_ref_brain} ] && [ ! -e ${anat_ref_mask} ] && [ ! -e ${anat_ref_wm4bbr} ] && [ ! -e ${anat_ref_gm} ]; then
  Error "One or more of the following files do/esn't esit"
  echo "${anat_ref_head}"
  echo "${anat_ref_brain}"
  echo "${anat_ref_mask}"
  echo "${anat_ref_wm4bbr}"
  echo "${anat_ref_gm}"
  exit 1
fi

## If func_unwarped is 
if [ ! ${dc_method} = "none" ]; then
  Note "Distortion corrected example_func* image will be used..."
  if [ ! -f ${dc_dir}/example_func_unwarped.nii.gz ] || [ ! -f ${dc_dir}/example_func_unwarped_brain.nii.gz ]; then
    Error "example_func_unwarped.nii.gz, example_func_unwarped_brain.nii.gz are/is not in the ${dc_dir}"
    exit 1
  fi
fi

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

if [[ ${reg_method} != "fsbbr" ]] && [[ ${reg_method} != "flirtbbr" ]] && [[ ${reg_method} != "flirt" ]]; then
  Error "!!! Check and select the registration method option (reg_method): fsbbr, flirtbbr, flirt"
  exit 1
fi

if [[ ${reg_method} = "fsbbr" ]]; then
  if [ -f ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz ]; then
    Error "fsbbr is selected but FreeSurfer preprocessed data doesn't exist"
  exit 1
  fi
fi
#####################################################################################################################
  
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x

##---------------------------------------------
func_pp_dir=${func_dir}/${func_pp_dir_name}
func_reg_dir=${func_dir}/${func_pp_dir_name}/xfms
mkdir -p ${func_reg_dir}
mkdir -p ${func_pp_dir}/masks

epi=${func_pp_dir}/example_func_bc.nii.gz
epi_brain_init=${func_pp_dir}/masks/example_func_bc_brain.init.nii.gz

## copy the input example_func and 
if [ ${dc_method} = "none" ]; then
  rm -f ${epi}
  3dcopy ${func_min_dir}/example_func_bc.nii.gz ${epi}
else
  rm -f ${epi}
  3dcopy ${dc_dir}/example_func_unwarped.nii.gz ${epi}
fi

##---------------------------------------------
# generate the initial brain mask for unwarped image
if [ ${dc_method} = "none" ]; then
  3dcopy ${func_min_dir}/example_func_bc_brain.nii.gz ${epi_brain_init}
  Do_cmd 3dmask_tool -input ${anat_ref_mask} -dilate_input 1 -prefix ${func_pp_dir}/masks/${T1w_image}_maskD.nii.gz
else
  pushd ${func_pp_dir}
  mkdir masks
  # head to head initial registration
  Do_cmd flirt -in ${anat_ref_head} -ref ${epi} -out masks/${T1w_image}_To_example_func.init.nii.gz -omat masks/xfm_${T1w_image}_To_example_func.init2.mat -cost corratio -dof 6 -interp spline
  ## do flirt -bbr
  Do_cmd flirt -in ${epi} -ref ${anat_ref_head} -cost bbr -wmseg ${anat_ref_wm4bbr} -omat masks/xfm_example_func_To_${T1w_image}.mat -dof 6 -init masks/xfm_example_func_To_${T1w_image}.init1.mat 
  Do_cmd convert_xfm -inverse -omat masks/xfm_${T1w_image}_To_example_func.mat masks/xfm_example_func_To_${T1w_image}.mat
  Do_cmd rm -f masks/${T1w_image}_maskD.nii.gz
  Do_cmd 3dmask_tool -input ${anat_ref_mask} -dilate_input 1 -prefix masks/${T1w_image}_maskD.nii.gz
  Do_cmd flirt -ref example_func.nii.gz -in masks/${T1w_image}_maskD.nii.gz -applyxfm -init masks/xfm_${T1w_image}_To_example_func.mat -interp nearestneighbour -out masks/${func}_mask.anatD.nii.gz
  # fill holes
  Do_cmd rm -f masks/${func}_mask.nii.gz
  Do_cmd 3dmask_tool -input masks/${func}_mask.anatD.nii.gz -prefix masks/${func}_mask.nii.gz -fill_holes
  Do_cmd fslmaths ${epi} -mas masks/${func}_mask.nii.gz ${epi_brain_init}
  popd
fi

##---------------------------------------------
cd ${func_reg_dir}

## do FS bbregister
if [[ ${reg_method} == "fsbbr" ]]; then
  mkdir ${func_reg_dir}/fsbbr
  pushd ${func_reg_dir}
  ## convert the example_func to RSP orient
  rm -f flirtbbr/tmp_example_func_brain_rsp.nii.gz
  3dresample -orient RSP -prefix flirtbbr/tmp_example_func_brain_rsp.nii.gz -inset ${epi_brain_init}
  fslreorient2std flirtbbr/tmp_example_func_brain_rsp.nii.gz > flirtbbr/func_rsp2rpi.mat
  convert_xfm -omat flirtbbr/func_rpi2rsp.mat -inverse flirtbbr/func_rsp2rpi.mat
  echo "-----------------------------------------------------"
  echo "func->anat registration method: Freesurfer bbregister"
  echo "-----------------------------------------------------"
  if [[ -f ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz ]]; then
    ## do fs bbregist
    mov_rsp=flirtbbr/tmp_example_func_brain_rsp.nii.gz
    bbregister --s ${subject} --mov ${mov_rsp} --reg fsbbr/bbregister_rsp2rsp.dof6.init.dat --init-fsl --bold --fslmat xfm_func_rsp2fsbrain.init.mat
    bb_init_mincost=`cut -c 1-8 fsbbr/bbregister_rsp2rsp.dof6.init.dat.mincost`
    comp=`expr ${bb_init_mincost} \> 0.55`
    if [ "$comp" -eq "1" ]; then
      bbregister --s ${subject} --mov ${mov_rsp} --reg fsbbr/bbregister_rsp2rsp.dof6.dat --init-reg fsbbr/bbregister_rsp2rsp.dof6.init.dat --bold --fslmat fsbbr/xfm_func_rsp2fsbrain.mat
      bb_mincost=`cut -c 1-8 bbregister_rsp2rsp.dof6.dat.mincost`
      comp=`expr ${bb_mincost} \> 0.55`
      if [ "$comp" -eq "1" ]; then
        echo "BBregister seems still problematic, needs a posthoc visual inspection!" >> warnings.bbregister
      fi
    else
      mv fsbbr/bbregister_rsp2rsp.dof6.init.dat fsbbr/bbregister_rsp2rsp.dof6.dat 
      mv fsbbr/xfm_func_rsp2fsbrain.init.mat fsbbr/xfm_func_rsp2fsbrain.mat
    fi
    ## concat reg matrix: func_rpi to highres(rsp)
    convert_xfm -omat fsbbr/xfm_func2fsbrain.mat -concat fsbbr/xfm_func_rsp2fsbrain.mat fsbbr/func_rpi2rsp.mat
    ## write func_rpi to highres(rsp) to fs registration format 
    tkregister2 --mov ${epi} --targ ${SUBJECTS_DIR}/${subject}/mri/T1.mgz --fsl fsbbr/xfm_func2fsbrain.mat --noedit --s ${subject} --reg fsbbr/bbregister.dof6.dat
    # concat func->fs_T1 fs_T1->fs_rawavg (acpc)
    convert_xfm -omat fsbbr/xfm_func2rawavg.mat -concat ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.FSL.mat fsbbr/xfm_func2fsbrain.mat
  fi
  
  # copy to xfms folder
  cp ${func_reg_dir}/fsbbr/xfm_func2rawavg.mat ${func_reg_dir}/xfm_func2${T1w_image}.mat
  popd
fi
  
##---------------------------------------------
## do flirt -bbr
if [[ ${reg_method} == "flirtbbr" ]]; then
  mkdir ${func_reg_dir}/flirtbbr
  pushd ${func_reg_dir}
  echo "-----------------------------------------------------"
  echo "func->anat registration method: FSL flirt -bbr"
  echo "-----------------------------------------------------"
  ## do flirt to init
  flirt -in ${epi} -ref ${anat_ref_head} -cost corratio -omat flirtbbr/xfm_func2anat.flirt_init.mat -dof 6
  convert_xfm -omat flirtbbr/xfm_anat2func.flirt_init.mat -inverse flirtbbr/xfm_func2anat.flirt_init.mat
  flirt -interp nearestneighbour -in ${anat_ref_mask} -ref ${epi} -applyxfm -init flirtbbr/xfm_anat2func.flirt_init.mat -out flirtbbr/tmp_example_func_mask.nii.gz
  fslmaths ${epi} -mas flirtbbr/tmp_example_func_mask.nii.gz flirtbbr/tmp_example_func_brain.nii.gz
  ## do flirt -bbr
  flirt -in flirtbbr/tmp_example_func_brain.nii.gz -ref ${anat_ref_brain} -cost bbr -wmseg ${anat_ref_wm4bbr} -omat flirtbbr/xfm_func2anat.mat -dof 6 -init flirtbbr/xfm_func2anat.flirt_init.mat
  
  ## write func_rpi to highres(rpi) to fs registration format
  ##convert_xfm -omat ${func_reg_dir}/xfm_func2fsbrain.mat -concat ${SUBJECTS_DIR}/${subject}/mri/xfm_rawavg_To_fs.FSL.mat flirtbbr/xfm_func2anat.mat
  ##tkregister2 --mov ${epi} --targ ${highres_rpi} --fsl ${func_reg_dir}/xfm_func2fsbrain.mat --noedit --s ${subject} --reg ${func_regbbr_dir}/bbregister.dof6.dat
  
  # copy to xfms folder
  rm ${func_reg_dir}/flirtbbr/tmp*
  cp ${func_reg_dir}/flirtbbr/xfm_func2anat.mat ${func_reg_dir}/xfm_func2${T1w_image}.mat
  popd
fi
  
##---------------------------------------------
## do flirt 
if [ ${reg_method} == "flirt" ]; then
  mkdir ${func_reg_dir}/flirt
  pushd ${func_reg_dir}
  echo "-----------------------------------------------------"
  echo "func->anat registration method: FSL flirt"
  echo "-----------------------------------------------------"
  flirt -in ${epi} -ref ${anat_ref_head} -cost corratio -omat flirt/xfm_func2anat.flirt_init.mat -dof 6
  convert_xfm -omat flirt/xfm_anat2func.flirt_init.mat -inverse flirt/xfm_func2anat.flirt_init.mat
  flirt -interp nearestneighbour -in ${anat_ref_mask} -ref ${epi} -applyxfm -init flirt/xfm_anat2func.flirt_init.mat -out flirtbbr/tmp_example_func_mask.nii.gz
  fslmaths ${epi} -mas flirt/tmp_example_func_mask.nii.gz flirt/tmp_example_func_brain.nii.gz
  ## do flirt 
  flirt -in flirt/tmp_example_func_brain.nii.gz -ref ${anat_ref_brain} -omat flirtbbr/xfm_func2anat.mat -dof 6 -init flirt/xfm_func2anat.flirt_init.mat
  
  # copy to xfms folder
  rm ${func_reg_dir}/flirt/tmp*
  cp ${func_reg_dir}/flirt/xfm_func2anat.mat ${func_reg_dir}/xfm_func2${T1w_image}.mat
  popd
fi

## create the inverse affine anat -> func 
Do_cmd convert_xfm -inverse -omat ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat ${func_reg_dir}/xfm_example_func_To_${T1w_image}.mat
##---------------------------------------------
## refine brain mask by applying the affine to anatomical mask 
Do_cmd flirt -ref ${epi} -in ${func_pp_dir}/masks/${T1w_image}_maskD.nii.gz -applyxfm -init ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat -interp nearestneighbour -out ${func_pp_dir}/masks/${func}_pp_mask.anatD.nii.gz
# fill holes
Do_cmd rm -f ${func_pp_dir}/masks/${func}_pp_mask.nii.gz
Do_cmd 3dmask_tool -input ${func_pp_dir}/masks/${func}_pp_mask.anatD.nii.gz -prefix ${func_pp_dir}/masks/${func}_pp_mask.nii.gz -fill_holes
Do_cmd fslmaths ${epi} -mas ${func_pp_dir}/masks/${func}_pp_mask.nii.gz ${func_pp_dir}/example_func_bc_brain.nii.gz
Do_cmd vcheck_mask ${epi} ${func_pp_dir}/masks/${func}_pp_mask.nii.gz ${func_pp_dir}/masks/${func}_pp_mask.png

##---------------------------------------------
## apply the affine
# anat to epi
mkdir ${func_reg_dir}/vcheck
Do_cmd flirt -in ${anat_ref_head} -ref ${epi} -applyxfm -init ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat -interp spline -out ${func_reg_dir}/vcheck/${T1w_image}_To_example_func.nii.gz
Do_cmd flirt -in ${anat_ref_brain} -ref ${epi} -applyxfm -init ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat -interp spline -out ${func_reg_dir}/vcheck/${T1w_image}_brain_To_example_func.nii.gz
Do_cmd flirt -in ${anat_ref_gm} -ref ${epi} -applyxfm -init ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat -interp spline -out ${func_reg_dir}/vcheck/${T1w_image}_gm_To_example_func.nii.gz
# epi to anat
Do_cmd flirt -in ${epi} -ref ${anat_ref_brain} -applyxfm -init ${func_reg_dir}/xfm_example_func_To_${T1w_image}.mat -interp spline -out ${func_reg_dir}/vcheck/example_func_To_${T1w_image}.nii.gz

## vcheck the registration quality
Do_cmd vcheck_reg ${epi} ${func_reg_dir}/vcheck/${T1w_image}_gm_To_example_func.nii.gz ${func_reg_dir}/vcheck/figure_example_func_with_anat_gm_boundary.png
Do_cmd vcheck_reg ${func_reg_dir}/vcheck/example_func_To_${T1w_image}.nii.gz ${anat_ref_gm} ${func_reg_dir}/vcheck/figure_example_func_To_${T1w_image}_with_anat_gm_boundary.png

##--------------------------------------------
## Back to the directory
cd ${cwd}
