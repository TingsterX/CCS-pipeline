#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO DO FUNCTIONAL IMAGE Registration (FUNC to STD)
## Xi-Nian Zuo, Aug. 13, 2011; Revised at IPCAS, Feb. 12, 2013.
## Ting Xu 202204, BIDS format input
##########################################################################################################################


while test $# -gt 0; do
  case "$1" in
    -d)
      shift
      if test $# -gt 0; then
        export base_directory=$1
      else
        echo "Need to specify input working directory (path/to/subject_folder)"
      fi
      shift
      ;;
    --subject*)
      shift
			if test $# -gt 0; then
				export subject=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify subject number (sub-******)"
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
    --res*)
      shift
			if test $# -gt 0; then
				export res=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify res"
			fi
			shift
			;;
    --func-name)
      shift
      if test $# -gt 0; then
        export rest=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify name of resting state scan"
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

exec > >(tee "Logs/${subject}/02_funcregister_func2std_log.txt") 2>&1
set -x 

if [ -z ${dc_method} ]; then
  dc_method=nondc
fi

## directory setup
ccs_dir=`pwd`
anat_dir=${base_directory}/${subject}/${session}/anat
func_dir=${base_directory}/${subject}/${session}/func_${dc_method}
anat_reg_dir=${anat_dir}/reg
func_min_dir=${base_directory}/${subject}/${session}/func_minimal
func_reg_dir=${func_dir}/func_reg
highres=${anat_reg_dir}/highres.nii.gz

if [ -f ${func_min_dir}/example_func_brain_unwarped.nii.gz ]; then
  example_func=${func_dir}/example_func_unwarped_brain.nii.gz
else
  example_func=${func_dir}/example_func_brain.nii.gz
fi

if [ -z ${res} ]; then
  res=3
fi 

if [ -z ${if_rerun} ]; then
  if_rerun=true
fi


## template
standard_head=${ccs_dir}/templates/MacaqueYerkes19_T1w_0.5mm.nii.gz
standard_brain=${ccs_dir}/templates/MacaqueYerkes19_T1w_0.5mm_brain.nii.gz
standard_edge=${ccs_dir}/templates/MacaqueYerkes19_T1w_0.5mm_brain_edge.nii.gz # same resolution as standard_brain/head
standard_func=${ccs_dir}/templates/MacaqueYerkes19_T1w_${res}mm.nii.gz


echo "---------------------------------------"
echo "!!!! FUNC TO STANDARD REGISTRATION !!!!"
echo "---------------------------------------"

##------------------------------------------------
cwd=$( pwd )
##1. FUNC->STANDARD
cd ${func_reg_dir}
if [[ ! -f fnirt_example_func2standard.nii.gz ]] || [[ ${if_rerun} == "true" ]]; then
  echo ">> Concatenate func-anat-std registration"
  ## Create mat file for registration of functional to standard
  convert_xfm -omat example_func2standard.mat -concat ${anat_reg_dir}/highres2standard.mat example_func2highres.mat
  ## apply registration
  flirt -ref ${standard_brain} -in ${example_func} -out example_func2standard.nii.gz -applyxfm -init example_func2standard.mat -interp trilinear
  ## Create inverse mat file for registration of standard to functional
  convert_xfm -inverse -omat standard2example_func.mat example_func2standard.mat
  ## 5. Applying fnirt
  applywarp --interp=spline --ref=${standard_brain} --in=${example_func} --out=fnirt_example_func2standard.nii.gz --warp=${anat_reg_dir}/highres2standard_warp --premat=example_func2highres.mat 

  ## 5. Visual check
  ## vcheck of the fnirt registration
  echo "----- visual check of the functional registration ----"
  bg_min=`fslstats fnirt_example_func2standard.nii.gz -P 1`
  bg_max=`fslstats fnirt_example_func2standard.nii.gz -P 99`
  overlay 1 1 fnirt_example_func2standard.nii.gz ${bg_min} ${bg_max} ${standard_edge} 1 1 vcheck/render_vcheck
  slicer vcheck/render_vcheck -s 2 \
      -x 0.30 sla.png -x 0.45 slb.png -x 0.50 slc.png -x 0.55 sld.png -x 0.70 sle.png \
      -y 0.30 slg.png -y 0.40 slh.png -y 0.50 sli.png -y 0.60 slj.png -y 0.70 slk.png \
      -z 0.30 slm.png -z 0.40 sln.png -z 0.50 slo.png -z 0.60 slp.png -z 0.70 slq.png 
  pngappend sla.png + slb.png + slc.png + sld.png  +  sle.png render_vcheck1.png 
  pngappend slg.png + slh.png + sli.png + slj.png  + slk.png render_vcheck2.png
  pngappend slm.png + sln.png + slo.png + slp.png  + slq.png render_vcheck3.png
  pngappend render_vcheck1.png - render_vcheck2.png - render_vcheck3.png fnirt_example_func2standard_edge.png
  mv fnirt_example_func2standard_edge.png vcheck/
  title=fnirt_example2standard
  convert -font helvetica -fill white -pointsize 36 -draw "text 15,25 '$title'" vcheck/fnirt_example_func2standard.png vcheck/fnirt_example_func2standard.png
  rm -f sl?.png render_vcheck?.png vcheck/render_vcheck*

else
  echo ">> Concatenate func-anat-std registration (done, skip)"
fi

## Apply to the data
if [[ ! -f ${rest}_gms.yerkes.${res}mm.nii.gz ]] || [[ "${if_rerun}" = "true" ]]; then 
  echo ">> Apply func-anat-std registration to the func dataset"
  applywarp --interp=nn --ref=${standard_func} --in=${rest}_pp_mask.nii.gz --out=${rest}_pp_mask.yerkes.${res}mm.nii.gz --warp=${anat_reg_dir}/highres2standard_warp --premat=example_func2highres.mat

  applywarp --interp=spline --ref=${standard_func} --in=${rest}_gms.nii.gz --out=${rest}_gms.yerkes.${res}mm.nii.gz --warp=${anat_reg_dir}/highres2standard_warp --premat=example_func2highres.mat
  mri_mask ${rest}_gms.yerkes.${res}mm.nii.gz ${rest}_pp_mask.yerkes.${res}mm.nii.gz ${rest}_gms.yerkes.${res}mm.nii.gz
else
  echo ">> Apply func-anat-std registration to the func dataset (done, skip)"
fi

##--------------------------------------------
## Back to the directory
cd ${cwd}
