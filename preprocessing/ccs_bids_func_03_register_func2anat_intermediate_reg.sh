#!/usr/bin/env bash

##########################################################################################################################
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, functional preprocessing
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Function Pipeline: registration (func->anat) 

Usage: ${0}
  --func_dir=<functional directory>, e.g. base_dir/subID/func/sub-X_task-X/
  --func_name=[func], name of the functional data, default=func (e.g. <func_dir>/func.nii.gz)
  --anat_dir=<anatomical directory>, specify the anat directory 
  --anat_ref_name=<T1w, T2w>, name of the anatomical reference name, default=T1w
  --epi2=<intermediate epi>
  --brain2=<intermediate anatomical brain>
  --epi2_to_brain2=<mat or warp from intermediate epi to intermediate anat brain>
  --dc_method=[none, topup, fugue, omni]
  --dc_dir=[path to the distortion corrected directory which contains example_func_bc_dc.nii.gz]
  --reg_method=[flirt, flirbbr], default=flirt
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
func=`getopt1 "--func_name" $@`
anat_dir=`getopt1 "--anat_dir" $@`
anat_ref_name=`getopt1 "--anat_ref_name" $@`
epi2=`getopt1 "--epi2" $@`
brain2=`getopt1 "--brain2" $@`
dc_method=`getopt1 "--dc_method" $@`
dc_dir=`getopt1 "--dc_dir" $@`
reg_method=`getopt1 "--reg_method" $@`
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`

## default parameter
func=`defaultopt ${func} func`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
dc_method=`defaultopt ${dc_method} none`
reg_method=`defaultopt ${reg_method} flirt`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "Function Pipeline: registration (func->anat) "
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "epi2=                ${epi2}"
Note "brain2=              ${brain2}"
Note "dc_method=           ${dc_method}"
Note "dc_dir=              ${dc_dir}"
Note "reg_method=          ${reg_method}"
Note "func_min_dir_name=   ${func_min_dir_name}"

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
  Info "Distortion corrected example_func* image will be used..."
  if [ ! -f ${dc_dir}/example_func_unwarped.nii.gz ]; then
    Error "example_func_unwarped.nii.gz is not in the ${dc_dir}"
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

if [[ ${reg_method} != "flirtbbr" ]] && [[ ${reg_method} != "flirt" ]]; then
  Error "!!! Check and select the registration method option (reg_method): fsbbr, flirtbbr, flirt"
  exit 1
fi

#####################################################################################################################
  
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x

##---------------------------------------------
func_pp_dir=${func_dir}/${func_pp_dir_name}
func_reg_dir=${func_dir}/${func_pp_dir_name}/xfms
mkdir -p ${func_reg_dir}

## copy the input example_func and unwarp
if [ ${dc_method} = "none" ]; then
  epi=${func_pp_dir}/example_func_bc.nii.gz
  epi_brain_init=${func_pp_dir}/masks/example_func_bc_brain.init.nii.gz
  epi_brain=${func_pp_dir}/example_func_bc_brain.nii.gz
else
  epi=${func_pp_dir}/example_func_unwarped.nii.gz
  epi_brain_init=${func_pp_dir}/masks/example_func_unwarped_brain.init.nii.gz
  epi_brain=${func_pp_dir}/example_func_unwarped_brain.nii.gz
fi

mkdir ${func_reg_dir}/intermediate_epi
mkdir ${func_reg_dir}/intermediate_epi/vcheck
pushd ${func_reg_dir}/intermediate_epi
##---------------------------------------------
## intermediate anat brain to anat brain
Do_cmd flirt -in ${brain2} -ref ${anat_ref_brain} -cost corratio -omat xfm_intermediate_brain2anat.mat -dof 12
Do_cmd fnirt --in=${brain2} --ref=${anat_ref_brain} --aff=xfm_intermediate_brain2anat.mat --fout=intermediate_brain2anat_warp.nii.gz --iout=intermediate_brain2anat.nii.gz
Do_cmd vcheck_reg intermediate_brain2anat.nii.gz ${anat_ref_brain} vcheck/figure_intermediate_brain2anat_with_anat_boundary.png

##  NOT FINISHED YET!!!!!!!!!!!!!!!!!!!!!!!!!
## epi register to intermediate epi

    
  ##---------------------------------------------
  ## do flirt -bbr
  if [[ ${reg_method} == "flirtbbr" ]]; then
    mkdir ${func_reg_dir}/flirtbbr
    pushd ${func_reg_dir}/flirtbbr
    echo "-----------------------------------------------------"
    Info "func->anat registration method: FSL flirt -bbr"
    echo "-----------------------------------------------------"
    ## do flirt to init
    Do_cmd flirt -in ${epi_brain_init} -ref ${anat_ref_brain} -cost corratio -omat xfm_func2anat.flirt_init.mat -dof 6
    Do_cmd convert_xfm -omat xfm_anat2func.flirt_init.mat -inverse xfm_func2anat.flirt_init.mat
    ## do flirt -bbr
    Do_cmd flirt -in ${epi_brain_init} -ref ${anat_ref_brain} -cost bbr -wmseg ${anat_ref_wm4bbr} -omat xfm_func2anat.mat -dof 6 -init xfm_func2anat.flirt_init.mat -searchrx -30 30 -searchry -30 30 -searchrz -30 30
    ## write func_rpi to highres(rpi) to fs registration format
    ##convert_xfm -omat ${func_reg_dir}/xfm_func2fsbrain.mat -concat ${SUBJECTS_DIR}/${subject}/mri/xfm_rawavg_To_fs.FSL.mat xfm_func2anat.mat
    ##tkregister2 --mov ${epi} --targ ${highres_rpi} --fsl ${func_reg_dir}/xfm_func2fsbrain.mat --noedit --s ${subject} --reg ${func_regbbr_dir}/bbregister.dof6.dat
    # copy to xfms folder
    Do_cmd cp xfm_func2anat.mat xfm_example_func_To_${T1w_image}.mat
    popd
  fi

  ##---------------------------------------------
  ## do flirt 
  if [ ${reg_method} == "flirt" ]; then
    mkdir ${func_reg_dir}/flirt
    pushd ${func_reg_dir}/flirt
    echo "-----------------------------------------------------"
    Info "func->anat registration method: FSL flirt"
    echo "-----------------------------------------------------"
    Do_cmd flirt -in ${epi_brain_init} -ref ${anat_ref_brain} -cost corratio -omat xfm_func2anat.flirt_init.mat -dof 6
    Do_cmd convert_xfm -omat xfm_anat2func.flirt_init.mat -inverse xfm_func2anat.flirt_init.mat
    ## do flirt 
    Do_cmd flirt -in ${epi_brain_init} -ref ${anat_ref_brain} -omat xfm_func2anat.mat -dof 6 -init xfm_func2anat.flirt_init.mat
    # copy to xfms folder
    Do_cmd cp xfm_func2anat.mat xfm_example_func_To_${T1w_image}.mat
    popd
  fi
  
  ##---------------------------------------------
  ## invert mat, generate warp, vcheck
  pushd ${func_reg_dir}/${reg_method}
  ##---------------------------------------------
  # invert and transfer to warp
  Info "create the inverse affine and refine brain mask as func_pp_mask ..."
  Do_cmd convert_xfm -omat xfm_${T1w_image}_To_example_func.mat -inverse xfm_example_func_To_${T1w_image}.mat
  Info "convert affine matrix to warp file"
  Do_cmd convertwarp -m xfm_example_func_To_${T1w_image}.mat -r ${anat_ref_brain} -o xfm_example_func_To_${T1w_image}.nii.gz --relout --rel 
  Do_cmd convertwarp -m xfm_${T1w_image}_To_example_func.mat -r ${epi} -o xfm_${T1w_image}_To_example_func.nii.gz --relout --rel
  ##---------------------------------------------
  ## apply the affine
  Info "Apply affine to native structure images..."
  # anat to epi
  mkdir vcheck
  Do_cmd flirt -interp spline -in ${anat_ref_head} -ref ${epi} -applyxfm -init xfm_${T1w_image}_To_example_func.mat -out vcheck/${T1w_image}_To_example_func.nii.gz
  Do_cmd flirt -interp spline -in ${anat_ref_brain} -ref ${epi} -applyxfm -init xfm_${T1w_image}_To_example_func.mat  -out vcheck/${T1w_image}_brain_To_example_func.nii.gz
  Do_cmd flirt -interp nearestneighbour -in ${anat_ref_gm} -ref ${epi} -applyxfm -init xfm_${T1w_image}_To_example_func.mat  -out vcheck/${T1w_image}_gm_To_example_func.nii.gz
  # epi to anat
  Do_cmd flirt -interp spline -in ${epi} -ref ${anat_ref_brain} -applyxfm -init xfm_example_func_To_${T1w_image}.mat  -out vcheck/example_func_To_${T1w_image}.nii.gz
  # apply affine can be done using the warp created
  #Do_cmd applywarp --rel --interp=spline --in=${epi} --warp=xfm_example_func_To_${T1w_image}.nii.gz --ref=${anat_ref_brain} --out=vcheck/example_func_To_${T1w_image}.nii.gz
  #Do_cmd applywarp --rel --interp=spline --in=${anat_ref_brain} --warp=xfm_${T1w_image}_To_example_func.nii.gz --ref=${epi} --out=vcheck/${T1w_image}_brain_To_example_func.nii.gz
  ##---------------------------------------------
  ## vcheck the registration quality
  Info "Generate QC figures for func -> anat registration ..."
  Do_cmd rm ${func_pp_dir}/masks/${func}_pp_mask.png ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_with_anat_gm_boundary.png ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_with_anat_brain_boundary.png ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_To_${T1w_image}_with_anat_gm_boundary.png
  Do_cmd vcheck_reg ${epi} ${func_reg_dir}/${reg_method}/vcheck/${T1w_image}_gm_To_example_func.nii.gz ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_with_anat_gm_boundary.png ${func_min_dir}//masks/${func}_mask.nii.gz
  Do_cmd vcheck_reg ${epi} ${func_reg_dir}/${reg_method}/vcheck/${T1w_image}_brain_To_example_func.nii.gz ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_with_anat_brain_boundary.png ${func_min_dir}/masks/${func}_mask.nii.gz
  Do_cmd vcheck_reg ${func_reg_dir}/${reg_method}/vcheck/example_func_To_${T1w_image}.nii.gz ${anat_ref_gm} ${func_reg_dir}/${reg_method}/vcheck/figure_example_func_To_${T1w_image}_with_anat_gm_boundary.png ${anat_ref_mask}
  ##---------------------------------------------
  popd

fi

if [ ! -z ${select_reg_output} ]; then
  ##---------------------------------------------
  Info "Copy selected registration output ${select_reg_output}"
  Do_cmd cp ${func_reg_dir}/${select_reg_output}/xfm_example_func_To_${T1w_image}.mat ${func_reg_dir}/xfm_example_func_To_${T1w_image}.mat
  Do_cmd cp ${func_reg_dir}/${select_reg_output}/xfm_${T1w_image}_To_example_func.mat ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat
  Do_cmd cp ${func_reg_dir}/${select_reg_output}/xfm_example_func_To_${T1w_image}.nii.gz ${func_reg_dir}/xfm_example_func_To_${T1w_image}.nii.gz
  Do_cmd cp ${func_reg_dir}/${select_reg_output}/xfm_${T1w_image}_To_example_func.nii.gz ${func_reg_dir}/xfm_${T1w_image}_To_example_func.nii.gz
  pushd ${func_reg_dir}
  ln -sf ${select_reg_output}/vcheck vcheck
  popd
  ##---------------------------------------------
  ## generate example_func_pp_mask
  if [ ${do_anat_refine_mask} = "true" ]; then
    ##---------------------------------------------
    ## refine brain mask by applying the affine to anatomical mask 
    Do_cmd flirt -ref ${epi} -in ${func_pp_dir}/masks/${T1w_image}_maskD.nii.gz -applyxfm -init ${func_reg_dir}/xfm_${T1w_image}_To_example_func.mat -interp nearestneighbour -out ${func_pp_dir}/masks/${func}_pp_mask.anatD.nii.gz
    # fill holes
    Do_cmd rm -f ${func_pp_dir}/masks/${func}_pp_mask.nii.gz
    Do_cmd 3dmask_tool -input ${func_pp_dir}/masks/${func}_pp_mask.anatD.nii.gz -prefix ${func_pp_dir}/masks/${func}_pp_mask.nii.gz -fill_holes
    Do_cmd fslmaths ${epi} -mas ${func_pp_dir}/masks/${func}_pp_mask.nii.gz ${epi_brain}
  
    ## refine brain mask to raw example_func space if distortion correction was applied
    if [ ${dc_method} = "none" ]; then
      Do_cmd rm ${func_pp_dir}/example_func_pp_mask.nii.gz
      Do_cmd 3dcopy ${func_pp_dir}/masks/${func}_pp_mask.nii.gz ${func_pp_dir}/example_func_pp_mask.nii.gz
    else
      Do_cmd applywarp --rel --interp=nn --in=${func_pp_dir}/masks/${func}_pp_mask.nii.gz --ref=${func_pp_dir}/example_func_bc.nii.gz --warp=${func_reg_dir}/unwarped2raw.nii.gz --out=${func_pp_dir}/example_func_pp_mask.nii.gz
    fi
  else
    Do_cmd fslmaths ${func_min_dir}/example_func_bc_brain.nii.gz -bin ${func_pp_dir}/example_func_pp_mask.nii.gz
  fi
  ##---------------------------------------------
  ## vcheck final func_pp_mask
  Do_cmd vcheck_mask_func ${epi} ${func_pp_dir}/masks/${func}_pp_mask.nii.gz ${func_pp_dir}/masks/${func}_pp_mask.png

fi

##--------------------------------------------
## Back to the directory
cd ${cwd}
