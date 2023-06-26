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
  --anat_seg_name=[segment, segment_fast], name of the anatomical segmention directory, default=segment
  --dc_method=[none, topup, fugue, omni]
  --average_method=[mean, svd], use mean or svd to extract signal, default=mean
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
anat_seg_name=`getopt1 "--anat_seg_name" $@`
dc_method=`getopt1 "--dc_method" $@`
average_method=`getopt1 "--average_method" $@`
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`

## default parameter
func=`defaultopt ${func_name} func`
dc_method=`defaultopt ${dc_method} none`
average_method=`defaultopt ${average_method} mean`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing step 1: generate mask for minimal preprocessed dta"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "dc_method=           ${dc_method}"
Note "average_method=      ${average_method}"
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

func_min_dir=${func_dir}/${func_min_dir_name}
func_pp_dir=${func_dir}/${func_pp_dir_name}
func_seg_dir=${func_pp_dir}/segment
nuisance_dir=${func_pp_dir}/nuisance

# ----------------------------------------------------

if [ ! ${average_method} = "mean" ] && [ ! ${average_method} = "svd" ]; then
  Error "--average_method has to be mean or svd"
  exit 1
fi

if [ ! -f ${func_seg_dir}/global_mask.nii.gz ] || [ ! -f ${func_seg_dir}/csf_mask.nii.gz ] || [ ! -f ${func_seg_dir}/wm_mask.nii.gz ]; then
  Error "!!!Check the functional segmentation files in ${func_seg_dir}"
  exit 1
fi

if [ ! -f ${func_min_dir}/${func}_mc.1D ]; then
  Error "!!!Check the motion file generated in the func minimal preprocess step"
  exit 1
fi

# ----------------------------------------------------
cwd=$( pwd )
mkdir -p ${nuisance_dir}

echo --------------------------------------------
Title "Run nuisance step ..."
echo --------------------------------------------

func_input=${func_pp_dir}/${func}_gms.nii.gz
## Skull Strip the func dataset
if [[ ! -f ${func_pp_dir}/${func}_gms.nii.gz ]] ; then
  Info ">> Skullstrip the func dataset using the refined rest_pp_mask"
  Do_cmd rm -f ${func_pp_dir}/${func}_ss.nii.gz
  Do_cmd mri_mask ${func_min_dir}/${func}_mc.nii.gz ${func_pp_dir}/example_func_pp_mask.nii.gz ${func_pp_dir}/${func}_ss.nii.gz
  Do_cmd fslmaths ${func_pp_dir}/${func}_ss.nii.gz -ing 10000 ${func_pp_dir}/${func}_gms.nii.gz
else
  Info ">> Skullstrip strip the func dataset using the example_func_pp_mask (done, skip)"
fi

## make nuisance directory
cd ${nuisance_dir}

nvols=`fslnvols ${func_input}`
## 2. Prepare regressors
if [ ${nvols} -ne `cat Model_Motion24_CSF_WM_Global.txt | wc -l` ] && [ ${nvols} -ne `cat Model_Motion24_CSF_WM.txt | wc -l` ] ; then
  ## 2.1 generate the temporal derivates of motion
  Do_cmd cp ${func_min_dir}/${func}_mc.1D ${nuisance_dir}/${func}_mc.1D
  Do_cmd 1d_tool.py -infile ${func}_mc.1D -derivative -write ${func}_mcdt.1D
  ## 2.2 Seperate motion parameters into seperate files
  Info "Splitting up ${subject} motion parameters"
  awk '{print $1}' ${func}_mc.1D > mc1.1D
  awk '{print $2}' ${func}_mc.1D > mc2.1D
  awk '{print $3}' ${func}_mc.1D > mc3.1D
  awk '{print $4}' ${func}_mc.1D > mc4.1D
  awk '{print $5}' ${func}_mc.1D > mc5.1D
  awk '{print $6}' ${func}_mc.1D > mc6.1D
  awk '{print $1}' ${func}_mcdt.1D > mcdt1.1D
  awk '{print $2}' ${func}_mcdt.1D > mcdt2.1D
  awk '{print $3}' ${func}_mcdt.1D > mcdt3.1D
  awk '{print $4}' ${func}_mcdt.1D > mcdt4.1D
  awk '{print $5}' ${func}_mcdt.1D > mcdt5.1D
  awk '{print $6}' ${func}_mcdt.1D > mcdt6.1D
  Info "Preparing 1D files for Friston-24 motion correction"
  for ((k=1 ; k <= 6 ; k++)); do
    # calculate the squared MC files
    1deval -a mc${k}.1D -expr 'a*a' > mcsqr${k}.1D
    # calculate the AR and its squared MC files
    1deval -a mc${k}.1D -b mcdt${k}.1D -expr 'a-b' > mcar${k}.1D
    1deval -a mcar${k}.1D -expr 'a*a' > mcarsqr${k}.1D
  done
  # Extract signal for global, csf, and wm
  ## 2.3. Global
  Info "Extracting global signal"
  3dmaskave -mask ${func_seg_dir}/global_mask.nii.gz -quiet ${func_input} > global.1D
  ## 2.4 csf matter
  Info "Extracting signal from csf"
  3dmaskSVD -vnorm -mask ${func_seg_dir}/csf_mask.nii.gz -polort 0 ${func_input} > csf_qvec.1D
  3dmaskave -mask ${func_seg_dir}/csf_mask.nii.gz -quiet ${func_input} > csf.1D
  ## 2.5. white matter
  Info "Extracting signal from white matter"
  3dmaskSVD -vnorm -mask ${func_seg_dir}/wm_mask.nii.gz -polort 0 ${func_input} > wm_qvec.1D
  3dmaskave -mask ${func_seg_dir}/wm_mask.nii.gz -quiet ${func_input} > wm.1D
  ## 2.6 CompCor file
  Info "Calculating CompCor components "
  fslmaths ${func_seg_dir}/wm_mask.nii.gz -add ${func_seg_dir}/csf_mask.nii.gz -bin tmp_csfwm_mask.nii.gz
  3dmaskSVD -vnorm -mask tmp_csfwm_mask.nii.gz -sval 4 -polort 0 ${func_input} > csfwm_qvec5.1D
  rm tmp_csfwm_mask.nii.gz
  ##  Seperate SVD parameters into seperate files
  awk '{print $1}' csfwm_qvec5.1D > compcor1.1D
  awk '{print $2}' csfwm_qvec5.1D > compcor2.1D
  awk '{print $3}' csfwm_qvec5.1D > compcor3.1D
  awk '{print $4}' csfwm_qvec5.1D > compcor4.1D
  awk '{print $5}' csfwm_qvec5.1D > compcor5.1D
  1dcat compcor1.1D compcor2.1D compcor3.1D compcor4.1D compcor5.1D > compcor_1-5.txt
  
  Info "Prepare different nuisance regression models"
  ## Concatenate regressor for the nuisance regression
  1dcat mc1.1D mc2.1D mc3.1D mc4.1D mc5.1D mc6.1D > mc_1-6.txt
  1dcat mcsqr1.1D mcsqr2.1D mcsqr3.1D mcsqr4.1D mcsqr5.1D mcsqr6.1D > mcsqr_1-6.txt
  1dcat mcar1.1D mcar2.1D mcar3.1D mcar4.1D mcar5.1D mcar6.1D > mcar_1-6.txt
  1dcat mcarsqr1.1D mcarsqr2.1D mcarsqr3.1D mcarsqr4.1D mcarsqr5.1D mcarsqr6.1D > mcarsqr_1-6.txt
  1dcat csf.1D wm.1D global.1D > csf_wm_global.txt
  # Motion + CSF + WM + (Global)
  if [ ${average_method} == "mean" ]; then
    1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt csf.1D wm.1D > Model_Motion24_CSF_WM.txt
    1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt csf.1D wm.1D global.1D > Model_Motion24_CSF_WM_Global.txt
    1dcat mc_1-6.txt mcar_1-6.txt csf.1D wm.1D > Model_Motion12_CSF_WM.txt
    1dcat mc_1-6.txt mcar_1-6.txt csf.1D wm.1D global.1D > Model_Motion12_CSF_WM_Global.txt
    1dcat mc_1-6.txt csf.1D wm.1D > Model_Motion6_CSF_WM.txt
    1dcat mc_1-6.txt csf.1D wm.1D global.1D > Model_Motion6_CSF_WM_Global.txt
  elif [ ${average_method} == "svd" ]; then
    1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt csf_qvec.1D wm_qvec.1D > Model_Motion24_CSF_WM.txt
    1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt csf_qvec.1D wm_qvec.1D global.1D > Model_Motion24_CSF_WM_Global.txt
    1dcat mc_1-6.txt mcar_1-6.txt csf_qvec.1D wm_qvec.1D > Model_Motion12_CSF_WM.txt
    1dcat mc_1-6.txt mcar_1-6.txt csf_qvec.1D wm_qvec.1D global.1D > Model_Motion12_CSF_WM_Global.txt
    1dcat mc_1-6.txt csf_qvec.1D wm_qvec.1D > Model_Motion6_CSF_WM.txt
    1dcat mc_1-6.txt csf_qvec.1D wm_qvec.1D global.1D > Model_Motion6_CSF_WM_Global.txt
  fi
  # Prepare Compcor
  1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt compcor_1-5.txt > Model_Motion24_CompCor.txt
  1dcat mc_1-6.txt mcar_1-6.txt mcsqr_1-6.txt mcarsqr_1-6.txt compcor_1-5.txt global.1D > Model_Motion24_CompCor_Global.txt
  1dcat mc_1-6.txt mcar_1-6.txt compcor_1-5.txt > Model_Motion12_CompCor.txt
  1dcat mc_1-6.txt mcar_1-6.txt compcor_1-5.txt global.1D > Model_Motion12_CompCor_Global.txt
  1dcat mc_1-6.txt compcor_1-5.txt > Model_Motion6_CompCor.txt
  1dcat mc_1-6.txt compcor_1-5.txt global.1D > Model_Motion6_CompCor_Global.txt

  ## clean-up
  Do_cmd rm mc[1-6].1D mcar[1-6].1D mcarsqr[1-6].1D mcdt[1-6].1D mcsqr[1-6].1D compcor?.1D

  Info ">> Visualize the nuisance"
  1dplot -xlabel "Frame" -ylabel "headmotion (mm)" -yaxis -0.5:0.5:4:8 -png vcheck_motion_0.5.png mc_1-6.txt
  1dplot -xlabel "Frame" -ylabel "headmotion (mm)" -yaxis -1:1:4:8 -png vcheck_motion_1.png mc_1-6.txt
  1dplot -xlabel "Frame" -ylabel "roll:blk,pitch:r,yaw:g,dS:blue,dL:pink,dP:yellow" -png vcheck_motion.png mc_1-6.txt
  1dplot -xlabel "Frame" -ylabel "CSF(blk)/WM(r)/Global(g)" -demean -png vcheck_csf_wm_global.png csf_wm_global.txt
  1dplot -xlabel "Frame" -ylabel "Global" -demean -png vcheck_global.png global.1D
  1dplot -xlabel "Frame" -ylabel "Global" -demean -png vcheck_csf.png csf.1D
  1dplot -xlabel "Frame" -ylabel "Global" -demean -png vcheck_wm.png wm.1D
  1dplot -xlabel "Frame" -ylabel "CompCor" -norm2 -png vcheck_compcor.png compcor_1-5.txt
else
  Info "Note: the nuisance files are existing, skip..."
fi

cd ${cwd}



