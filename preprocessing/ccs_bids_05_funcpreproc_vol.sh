#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO DO REGRESS OUT NUISANCE COVARIATES FROM RESTING_STATE SCAN
## Revised from Xi-Nian Zuo https://github.com/zuoxinian/CCS
## Ting Xu, 202204, BIDS format input
##########################################################################################################################


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
      --motion-model*)
        shift
			  if test $# -gt 0; then
				  export motion_model=`echo $1 | sed -e 's/^[^=]*=//g'`
			  else
				  echo "Need to specify motion model (6, 12, 24, compcor)"
			  fi
			  shift
			  ;;
      --res*)
        shift
			  if test $# -gt 0; then
				  export res_std=`echo $1 | sed -e 's/^[^=]*=//g'`
			  else
				  echo "Need to specify standard space resolution number"
			  fi
			  shift
			  ;;
      --FWHM*)
        shift
			  if test $# -gt 0; then
				  export FWHM=`echo $1 | sed -e 's/^[^=]*=//g'`
			  else
				  echo "Need to specify desired spatial smoothing"
			  fi
			  shift
			  ;;
      --compcor*)
        shift
			  export compcor=true
			  ;;
      --hp*)
        shift
			  if test $# -gt 0; then
				  export hp=`echo $1 | sed -e 's/^[^=]*=//g'`
			  else
				  echo "Need to specify high pass band filtering"
			  fi
			  shift
			  ;;
      --lp*)
        shift
			  if test $# -gt 0; then
				  export lp=`echo $1 | sed -e 's/^[^=]*=//g'`
			  else
				  echo "Need to specify low pass band filtering"
			  fi
			  shift
			  ;;
      --dc-method)
        shift
        export dc_method=$1
        shift
        ;;
      *)
        echo "Invalid input"
        exit 0
    esac
done

exec > >(tee "Logs/${subject}/05_funcpreproc_vol_log.txt") 2>&1
set -x 

## directory setup
ccs_dir=`pwd`
anat_dir=${base_directory}/${subject}/${session}/anat
func_dir=${base_directory}/${subject}/${session}/func_${dc_method}
anat_reg_dir=${anat_dir}/reg
func_reg_dir=${func_dir}/func_reg
nuisance_dir=${func_dir}/func_nuisance
func_proc_dir=${func_dir}/func_proc

## template
standard=${ccs_dir}/templates/MacaqueYerkes19_T1w_${res_std}mm.nii.gz 
## input data
func_input=${func_reg_dir}/${rest}_gms.nii.gz
func_mask=${func_reg_dir}/${rest}_pp_mask.nii.gz
## smooth kernel
sigma=`echo "scale=10 ; ${FWHM}/2.3548" | bc`


if [ -z ${if_rerun} ]; then if_rerun=false; fi
if [ -z ${motion_model} ]; then motion_model=24; fi
if [ -z ${compcor} ]; then compcor=false; fi
if [ -z ${res_anat} ]; then res_anat=1.0; fi
if [ -z ${res_std} ]; then res_std=1.0; fi
if [ -z ${hp} ]; then hp=0.01; fi
if [ -z ${lp} ]; then lp=0.1; fi

if [ ! -f ${func_input} ]; then
  echo "!!!Check the minimal preprocessed func_gms after registration"
  exit
fi

if [ ! -f ${nuisance_dir}/Model_Motion24_CSF_WM_Global.txt ] || [ ! -f ${nuisance_dir}/Model_Motion24_CSF_WM.txt ]; then
  echo -e \\"e[0;41m !!!Check!!! \\e[0m"
  echo "!!!Check the nuisance step if the Regressors are generated"
  exit
fi

nvols=`fslnvols ${func_input}`
nt=`cat ${nuisance_dir}/Model_Motion24_CSF_WM.txt | wc -l`
if [ ${nvols} -ne ${nt} ]; then
  echo -e \\"e[0;41m !!!Check!!! \\e[0m"
  echo "!!!Check the number of the func data doesn't match with the number of timepoints of regressors"
  exit
fi

echo --------------------------------------------
echo !!!! RUNNING FINAL PREPROCESS !!!!
echo --------------------------------------------

cwd=$( pwd )

func_pp_list=""
func_pp_list="${func_pp_list} ${rest}_pp_filter_sm0"
func_pp_list="${func_pp_list} ${rest}_pp_filter_gsr_sm0"
func_pp_list="${func_pp_list} ${rest}_pp_nofilt_sm0"
func_pp_list="${func_pp_list} ${rest}_pp_nofilt_gsr_sm0"
func_pp_list="${func_pp_list} ${rest}_pp_filter_sm${FWHM}"
func_pp_list="${func_pp_list} ${rest}_pp_filter_gsr_sm${FWHM}"
func_pp_list="${func_pp_list} ${rest}_pp_nofilt_sm${FWHM}"
func_pp_list="${func_pp_list} ${rest}_pp_nofilt_gsr_sm${FWHM}"

if [ ${if_rerun} == "true" ]; then
  echo "Clean up the all the final step files"
  rm -rf ${func_proc_dir}/*
fi

## 1. make nuisance directory
mkdir -p ${func_proc_dir}; cd ${func_proc_dir}

## 3. Select the model
echo "------------------------------------------------"
echo ">> motion_model=${motion_model}, CompCor=${compcor}"
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
fi
cp ${reg_nogsr} ./Regressors_data.txt
cp ${reg_gsr} ./Regressor_data_gsr.txt

## check if nuisance regression and smoothing is done
func_pp_done=true
for func_pp in ${func_pp_list}; do
  if [ ! -f ${func_pp}.nii.gz ]; then
    func_pp_done=false
  fi
done
if [ ! -f filter.log ]; then
  func_pp_done=false
fi

if [ ${func_pp_done} == false ]; then
  ## 4. Nuisance regression
  echo ">> Nuisance regression, no/filtering (hp=${hp}, lp=${lp}), detrending (polynomial=2) the functional data"
  fslmaths ${func_input} -Tmean ${rest}_pp_mean.nii.gz
  echo "hp=${hp}, lp=${lp}" > filter.log
  ## no filter (nogsr, gsr)
  3dTproject -input ${func_input} -prefix ${rest}_pp_nofilt_sm0.nii.gz -ort ${reg_nogsr} -polort 2 -overwrite
  3dTproject -input ${func_input} -prefix ${rest}_pp_nofilt_gsr_sm0.nii.gz -ort ${reg_gsr}  -polort 2 -overwrite
  ## filter (nogsr, gsr)
  3dBandpass -band ${hp} ${lp} -input ${rest}_pp_nofilt_sm0.nii.gz -prefix ${rest}_pp_filter_sm0.nii.gz -overwrite
  3dBandpass -band ${hp} ${lp} -input ${rest}_pp_nofilt_gsr_sm0.nii.gz -prefix ${rest}_pp_filter_gsr_sm0.nii.gz -overwrite
  ## 5. Smooth
  echo ">> Smooth the data: FWHM=${FWHM}"
  ## filter (nogsr, gsr)
  3dBlurInMask -input ${rest}_pp_filter_sm0.nii.gz -FWHM ${FWHM} -mask ${func_mask} -prefix ${rest}_pp_filter_sm${FWHM}.nii.gz -quite -overwrite
  3dBlurInMask -input ${rest}_pp_filter_gsr_sm0.nii.gz -FWHM ${FWHM} -mask ${func_mask} -prefix ${rest}_pp_filter_gsr_sm${FWHM}.nii.gz -quite
  ## no filter (nogsr, gsr)
  3dBlurInMask -input ${rest}_pp_nofilt_sm0.nii.gz -FWHM ${FWHM} -mask ${func_mask} -prefix ${rest}_pp_nofilt_sm${FWHM}.nii.gz -quite -overwrite
  3dBlurInMask -input ${rest}_pp_nofilt_gsr_sm0.nii.gz -FWHM ${FWHM} -mask ${func_mask} -prefix ${rest}_pp_nofilt_gsr_sm${FWHM}.nii.gz -quite -overwrite
else
  echo "SKIP >> Nuisance regression, no/filtering, detrending, smoothing are done"
fi

## 6. register func->anat space
if [ ${do_func2anat} == true ]; then
echo ">> Apply func-anat registration to func_pp_* data"
if [ ! -f ${rest}_pp_mask.anat.${res_anat}mm.nii.gz ]; then
  echo "RUN >> Mask to Anat Space: ${rest}_pp_mask.anat.${res_anat}mm.nii.gz"
  flirt -interp nearestneighbour -in ${func_mask} -ref ${anat_reg_dir}/highres_rpi.nii.gz -applyxfm -init ${func_reg_dir}/example_func2highres_rpi.mat -applyisoxfm ${res_anat} -out ${rest}_pp_mask.anat.${res_anat}mm.nii.gz
else
  echo "SKIP >> Mask to Anat Space: ${rest}_pp_mask.anat.${res_anat}mm.nii.gz"
fi
for func_pp in ${func_pp_list}; do
  if [ ! -f ${func_pp}.anat.${res_anat}mm.nii.gz ]; then
     echo "RUN >> Data to Anat Space: ${func_pp}.anat.${res_anat}mm.nii.gz"
    flirt -interp spline -in ${func_pp}.nii.gz -ref ${anat_reg_dir}/highres_rpi.nii.gz -applyxfm -init ${func_reg_dir}/example_func2highres_rpi.mat -applyisoxfm ${res_anat} -out ${func_pp}.anat.${res_anat}mm.nii.gz
    mri_mask ${func_pp}.anat.${res_anat}mm.nii.gz ${rest}_pp_mask.anat.${res_anat}mm.nii.gz ${func_pp}.anat.${res_anat}mm.nii.gz
  else
    echo "SKIP >> Data to Anat Space: ${func_pp}.anat.${res_anat}mm.nii.gz"
  fi
done
fi

## 7. register to template space
echo ">> Apply func-anat-std registration to func_pp_* data"
if [ ! -f ${rest}_pp_mask.yerkes.${res_std}mm.nii.gz ]; then
  echo "RUN >> Mask to Template Space: ${rest}_pp_mask.yerkes.${res_std}mm.nii.gz" 
  applywarp --interp=nn --ref=${standard} --in=${func_mask} --out=${rest}_pp_mask.yerkes.${res_std}mm.nii.gz --warp=${anat_reg_dir}/highres2standard_warp --premat=${func_reg_dir}/example_func2highres.mat
else
  echo "SKIP >> Mask to Template Space: ${rest}_pp_mask.yerkes.${res_std}mm.nii.gz" 
fi
for func_pp in ${func_pp_list}; do
  if [ ! -f ${func_pp}.yerkes.${res_std}mm.nii.gz ]; then
    echo "RUN >> Data to Template Space: ${func_pp}.yerkes.${res_std}mm.nii.gz"
    applywarp --interp=spline --ref=${standard} --in=${func_pp} --out=${func_pp}.yerkes.${res_std}mm.nii.gz --warp=${anat_reg_dir}/highres2standard_warp --premat=${func_reg_dir}/example_func2highres.mat
    mri_mask ${func_pp}.yerkes.${res_std}mm.nii.gz ${rest}_pp_mask.yerkes.${res_std}mm.nii.gz ${func_pp}.yerkes.${res_std}mm.nii.gz
  else
    echo "SKIP >> Data to Template Space: ${func_pp}.yerkes.${res_std}mm.nii.gz"
  fi
done





