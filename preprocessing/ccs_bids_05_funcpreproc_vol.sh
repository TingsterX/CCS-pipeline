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
  --anat_ref_name=[T1w, T2w], name of the anatomical reference name, default=T1w
  --dc_method=[none, topup, fugue, omni]
  --func_min_dir_name=[func_minimal], default=func_minimal
  --reference=[write out reference], specify either reference or write out resolution
  --resolution=[1.5, 3], write out resolution in mm
  --num_of_motion=[6, 12, 24], num of motion regressors, default=24
  --compcor=[true, false], use compcor or not, default=false
  --FWHM=<smooth kernel>, smooth the final data
  --high_pass=[high-pass filter], default=0.01
  --low_pass=[low-pass filter], default=0.1
  --ica_denoise=[true, false], default=false
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
func_min_dir_name=`getopt1 "--func_min_dir_name" $@`
reference=`getopt1 "--reference" $@`
res=`getopt1 "--resolution" $@`
motion_model=`getopt1 "--num_of_motion" $@`
compcor=`getopt1 "--compcor" $@`
FWHM=`getopt1 "--FWHM" $@`
hp=`getopt1 "--high_pass" $@`
lp=`getopt1 "--low_pass" $@`
ica_denoise=`getopt1 "--ica_denoise" $@`

## default parameter
func=`defaultopt ${func_name} func`
dc_method=`defaultopt ${dc_method} none`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`
motion_model=`defaultopt ${motion_model} 24`
compcor=`defaultopt ${compcor} false`
hp=`defaultopt ${hp} 0.01`
lp=`defaultopt ${lp} 0.1`
ica_denoise=`defaultopt ${ica_denoise} false`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "func preprocessing: final preprocessing "
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "dc_method=           ${dc_method}"
Note "func_min_dir_name=   ${func_min_dir_name}"
Note "reference=           ${reference}"
Note "resolution=          ${res}"
Note "num_of_motion=       ${motion_model}"
Note "FWHM=                ${FWHM}"
Note "low_pass=            ${lp}"
Note "high_pass=           ${hp}"
Note "ica_denoise=         ${ica_denoise}"
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

## directory
T1w_image=${anat_ref_name}_acpc_dc
anat_ref_head=${anat_dir}/${T1w_image}.nii.gz

func_min_dir=${func_dir}/${func_min_dir_name}
func_pp_dir=${func_dir}/${func_pp_dir_name}
nuisance_dir=${func_pp_dir}/nuisance
func_reg_dir=${func_pp_dir}/xfms
func_atlas_dir=${func_pp_dir}/TemplateSpace
func_native_dir=${func_pp_dir}/NativeSpace
## input data
func_input=${func_pp_dir}/${func}_gms.nii.gz
func_mask=${func_pp_dir}/example_func_pp_mask.nii.gz
## smooth kernel
sigma=`echo "scale=10 ; ${FWHM}/2.3548" | bc`

if [ ! -f ${reference} ] || [ -z ${res} ]; then
  Error "Specify--reference or --resolution ..."
  exit 1
fi

if [[ ${lp} =~ ^[0-9]+([.][0-9]+)?$ ]] && [[ ${hp} =~ ^[0-9]+([.][0-9]+)?$ ]] && [[ ${FWHM} =~ ^[0-9]+([.][0-9]+)?$ ]] && [[ ${num_of_motion} =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  Error "Specify number: --lp, --hp, --FWHM, --num_of_motion"
  exit 1
fi

if [ ! -f ${func_input} ]; then
  Error "!!!Check the minimal preprocessed func_gms after registration"
  exit 1
fi

nvols=`fslnvols ${func_input}`
nt=`cat ${nuisance_dir}/Model_Motion24_CSF_WM.txt | wc -l`
if [ ${nvols} -ne ${nt} ]; then
  Error "!!!Check the number of the func data doesn't match with the number of timepoints of regressors"
  exit 1
fi

# ----------------------------------------------------
Title "!!!! RUNNING FINAL PREPROCESS !!!!"

cwd=$( pwd )

func_pp_list=""
func_pp_list="${func_pp_list} ${func}_pp_filter_sm0"
func_pp_list="${func_pp_list} ${func}_pp_filter_gsr_sm0"
func_pp_list="${func_pp_list} ${func}_pp_nofilt_sm0"
func_pp_list="${func_pp_list} ${func}_pp_nofilt_gsr_sm0"

## 1. make nuisance directory
mkdir -p ${func_native_dir} 
mkdir -p ${func_atlas_dir}

Do_cmd cd ${func_pp_dir}
## 3. Select the model
echo "------------------------------------------------"
Info ">> motion_model=${motion_model}, CompCor=${compcor}"
echo "------------------------------------------------"
echo "motion_model=${motion_model}, CompCor=${compcor}" > ${func_proc_dir}/Regressors_model.log
if [ $motion_model == "24" ] && [ ${compcor} == false ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion24_CSF_WM.txt
  reg_gsr=${nuisance_dir}/Model_Motion24_CSF_WM_Global.txt
elif [ $motion_model == "12" ] && [ ${compcor} == false ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion12_CSF_WM.txt
  reg_gsr=${nuisance_dir}/Model_Motion12_CSF_WM_Global.txt
elif [ $motion_model == "6" ] && [ ${compcor} == false ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion6_CSF_WM.txt
  reg_gsr=${nuisance_dir}/Model_Motion6_CSF_WM_Global.txt
elif [ $motion_model == "24" ] && [ ${compcor} == true ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion24_CompCor.txt
  reg_gsr=${nuisance_dir}/Model_Motion24_CompCor_Global.txt
elif [ $motion_model == "12" ] && [ ${compcor} == true ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion12_CompCor.txt
  reg_gsr=${nuisance_dir}/Model_Motion12_CompCor_Global.txt
elif [ $motion_model == "6" ] && [ ${compcor} == true ]; then
  reg_nogsr=${nuisance_dir}/Model_Motion6_CompCor.txt
  reg_gsr=${nuisance_dir}/Model_Motion6_CompCor_Global.txt
else
  Error "--num_of_motion has to be 6, 12, 24 and --compcor has to be true or false"
fi
Do_cmd cp ${reg_nogsr} Regressors_data.txt
Do_cmd cp ${reg_gsr} Regressor_data_gsr.txt

## 4. Nuisance regression
Info ">> Nuisance regression, no/filtering (hp=${hp}, lp=${lp}), detrending (polynomial=2) the functional data"
Do_cmd fslmaths ${func_input} -Tmean ${func}_pp_mean.nii.gz
echo "hp=${hp}, lp=${lp}" > filter.log
## no filter (nogsr, gsr)
Do_cmd 3dTproject -input ${func_input} -mask ${func_mask} -prefix ${func}_pp_nofilt_sm0.nii.gz -ort ${reg_nogsr} -polort 2 -overwrite
Do_cmd 3dTproject -input ${func_input} -mask ${func_mask} -prefix ${func}_pp_nofilt_gsr_sm0.nii.gz -ort ${reg_gsr}  -polort 2 -overwrite
## filter (nogsr, gsr)
Do_cmd 3dTproject -input ${func_input} -bandpass ${hp} ${lp} -mask ${func_mask} -prefix ${func}_pp_filter_sm0.nii.gz -ort ${reg_nogsr} -polort 2 -overwrite
Do_cmd 3dTproject -input ${func_input} -bandpass ${hp} ${lp} -mask ${func_mask} -prefix ${func}_pp_filter_gsr_sm0.nii.gz -ort ${reg_gsr} -polort 2 -overwrite


## 6. register func->anat space
cd ${func_native_dir}
Info ">> Apply func-anat registration to func_pp_* data"
Info "RUN >> Mask to Anat Space: ${func}_pp_mask.${res}mm.nii.gz"
Do_cmd flirt -interp spline -in ${anat_ref_head} -ref ${anat_ref_head} -applyxfm -init ${FSLDIR}/etc/flirtsch/ident.mat -applyisoxfm ${res} -out ${T1w_image}.NativeSpace.${res}mm.nii.gz
Do_cmd applywarp --rel --interp=nn --in=${func_mask} --ref=${T1w_image}.NativeSpace.${res}mm.nii.gz --warp=${func_reg_dir}/func_mc2${T1w_image}.nii.gz --out=${func}_pp_mask.${res}mm.nii.gz
for func_pp in ${func_pp_list}; do
  Info "RUN >> Data to Anat Space: ${func_pp}"
  Do_cmd applywarp --rel --interp=spline --in=${func_pp_dir}/${func_pp}.nii.gz --ref=${T1w_image}.NativeSpace.${res}mm.nii.gz --warp=${func_reg_dir}/func_mc2${T1w_image}.nii.gz --out=${func_pp}.${res}mm.nii.gz
  Do_cmd mri_mask ${func_pp}.${res}mm.nii.gz ${func}_pp_mask.${res}mm.nii.gz ${func_pp}.${res}mm.nii.gz
done
# smoothing
for func_pp in ${func_pp_list}; do
  Info "RUN >> Smoothing data to anat Space: ${func_pp}"
  Do_cmd 3dBlurInMask -input ${func_pp}.${res}mm.nii.gz -FWHM ${FWHM} -mask ${func}_pp_mask.${res}mm.nii.gz -prefix ${func_pp/sm0/}sm${FWHM}.${res}mm.nii.gz -quite -overwrite
done


## 7. register to template space
cd ${func_atlas_dir}
Info ">> Apply func-anat-std registration to func_pp_* data"
echo "RUN >> Mask to Template Space: ${func}_pp_mask.${res}mm.nii.gz" 
Do_cmd applywarp --rel --interp=nn --ref=${reference} --in=${func_mask} --out=${func}_pp_mask.${res}mm.nii.gz --warp=${func_reg_dir}/func_mc2standard.nii.gz 
for func_pp in ${func_pp_list}; do
  echo "RUN >> Data to Template Space: ${func_pp}.${res}mm.nii.gz"
  Do_cmd applywarp --rel --interp=spline --ref=${reference} --in=${func_pp_dir}/${func_pp}.nii.gz --out=${func_pp}.${res}mm.nii.gz --warp=${func_reg_dir}/func_mc2standard.nii.gz
  Do_cmd mri_mask ${func_pp}.${res}mm.nii.gz ${func}_pp_mask.${res}mm.nii.gz ${func_pp}.${res}mm.nii.gz
done
# smoothing
for func_pp in ${func_pp_list}; do
  Info "RUN >> Smoothing data to anat Space: ${func_pp}"
  Do_cmd 3dBlurInMask -input ${func_pp}.${res}mm.nii.gz  -FWHM ${FWHM} -mask ${func}_pp_mask.${res}mm.nii.gz -prefix ${func_pp/sm0/}sm${FWHM}.${res}mm.nii.gz -quite -overwrite
done

cd ${cwd}



