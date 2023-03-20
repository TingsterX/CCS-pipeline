#!/usr/bin/env bash
##########################################################################################################################
## docker image: https://hub.docker.com/r/tingsterx/ccs-bids
## export PATH for docker
#. /neurodocker/startup.sh
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=10
##########################################################################################################################
################### Setup code and data directory 
# Source the config file
. config_file.config

################### Take parameters

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      echo "-----------------------------"
      echo "Usage:"
      exit 0
      ;;
    -d)
      shift
      if test $# -gt 0; then
        export base_directory=$1
      else
        echo "Need to specify directory to subject folder (path/to/subjects)"
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
        echo "Need to specify session number (ses-***)"
      fi
      shift
      ;;
    --run*)
      shift
      if test $# -gt 0; then
        export run=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify session number (ses-***)"
      fi
      shift
      ;;
    --num-runs*)
      shift
      if test $# -gt 0; then
        export num_runs=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify session number (ses-***)"
      fi
      shift
      ;;
    --func-name*)
      shift
      if test $# -gt 0; then
        export func_name=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify name of functional image"
      fi
      shift
      ;;
    --mask*)
      shift
      if test $# -gt 0; then
        export mask_path=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify name of functional image"
      fi
      shift
      ;;
    *)
      echo "Invalid input"
      exit 0
  esac
done
  
    
## name of anatomical scan (no extension)
anat_name=${subject}_${session_name}_${run_name}_T1w
## name of resting-state scan (no extension)
ccs_dir=`pwd`
standard_head=${ccs_dir}/templates/MacaqueYerkes19_T1w_0.5mm.nii.gz
standard_brain=${ccs_dir}/templates/MacaqueYerkes19_T1w_0.5mm_brain.nii.gz
standard_template=${ccs_dir}/templates/MacaqueYerkes19_T1w_1.0mm_brain.nii.gz
fsaverage=fsaverage5
##########################################################################################################################

## BIDS format directory setup
anat_dir=${base_directory}/${subject}/${session_name}/${anat_dir_name}
SUBJECTS_DIR=${base_directory}/${subject}/${session_name}
func_dir=${base_directory}/${subject}/${session_name}/func
TR_file=${func_dir}/TR.txt
tpattern_file=${func_dir}/SliceTiming.txt
###################

## Set up logging directory in working directory
if [ ! -d "./Logs/${subject}" ]
then
  mkdir -p ./Logs/${subject}
fi

echo "-----------------------------------------------------"
echo "Preprocessing of data: ${subject} ${session_name} ${run_name}..."
echo "-----------------------------------------------------"
##########################################################################################################################
## Anatomical Image Preprocessing
##########################################################################################################################

if [ ${run_anat} == true ]; then

  ## 1. skullstriping 
  ${scripts_dir}/ccs_bids_01_anatpreproc.sh -d ${base_directory} --subject ${subject} --session ${session} --num-scans ${num_runs} --gcut --denoise --mask ${mask_path}

  ## 2. freesurfer pipeline
  ${scripts_dir}/ccs_bids_01_anatsurfrecon.sh -d ${base_directory} --subject ${subject} --session ${session} --mask manual 
  
  ## 3. registration
  ${scripts_dir}/ccs_bids_02_anatregister.sh ${ccs_dir} ${anat_dir} ${SUBJECTS_DIR} ${subject} ${anat_reg_dir_name}

fi

##########################################################################################################################
## Functional Image Preprocessing
##########################################################################################################################

if [ ${run_func} == true ]; then

  ## 1. Preprocessing functional images
  ${scripts_dir}/ccs_bids_01_funcpreproc.sh ${func_name} ${anat_dir} ${func_dir} ${numDropping} ${TR_file} ${tpattern_file} ${func_min_dir_name} ${if_rerun} ${clean_up}
  
  ## 2. func to anat registration
  ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh ${anat_dir} ${anat_reg_dir_name} ${SUBJECTS_DIR} ${subject} ${func_name} ${func_dir} ${func_min_dir_name} ${reg_method} ${func_reg_dir_name} ${if_use_bc_func} ${res_func} ${if_rerun}
  
  ## 2. func to std registration
  ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh ${ccs_dir} ${anat_dir} ${anat_reg_dir_name} ${func_name} ${func_dir} ${func_min_dir_name} ${func_reg_dir_name} ${res_func} ${if_rerun}
  
  ## 3. func segmentation
  ${scripts_dir}/ccs_bids_03_funcsegment.sh ${anat_dir} ${SUBJECTS_DIR} ${subject} ${func_name} ${func_dir} ${func_reg_dir_name} ${func_seg_dir_name} ${if_rerun}
  
  ## 4. func generate nuisance 
  ${scripts_dir}/ccs_bids_04_funcnuisance.sh ${func_name} ${func_dir} ${func_min_dir_name} ${func_reg_dir_name} ${func_seg_dir_name} ${nuisance_dir_name} ${svd} ${if_rerun}
  
  ## 5. func nuisance regression, filter, smoothing preproc
  ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh ${anat_dir} ${anat_reg_dir_name} ${func_name} ${func_dir} ${func_min_dir_name} ${func_reg_dir_name} ${nuisance_dir_name} ${func_proc_dir_name} ${motion_model} ${compcor} ${hp} ${lp} ${FWHM} ${res_anat} ${res_std} ${ccs_dir} ${if_rerun}

fi
