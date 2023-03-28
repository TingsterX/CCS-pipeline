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
    --func-name)
      shift
      if test $# -gt 0; then
        export func_name=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify name of functional image"
      fi
      shift
      ;;
    ## Specify the second func scan (if available for topup)
    --func-name-2*)
      shift
      if test $# -gt 0; then
        export func_name_2=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify name of functional image"
      fi
      shift
      ;;
    --drop-vols*)
      shift
      if test $# -gt 0; then
        export drop_vols=`echo $1 | sed -e 's/^[^=]*=//g'`
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
    --reg-method*)
      shift
      if test $# -gt 0; then
        export reg_method=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify the reg method (fsbbr, fslbbr, flirt)"
      fi
      shift
      ;;
    --distortion-correction*)
      shift
      if test $# -gt 0; then
        export diss_type=`echo $1 | sed -e 's/^[^=]*=//g'`
      else
        echo "Need to specify the reg method (fsbbr, fslbbr, flirt)"
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

exec > >(tee "Logs/${subject}/ccs_preproc_bids_docker_log.txt") 2>&1
set -x 

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
  ${scripts_dir}/ccs_bids_02_anatregister.sh -d ${base_directory} --subject ${subject} --session ${session}

fi

##########################################################################################################################
## Functional Image Preprocessing
##########################################################################################################################

if [ ${run_func} == true ]; then

  ## 1. Preprocessing functional images
  ${scripts_dir}/ccs_bids_01_funcpreproc.sh -d ${base_directory} -r ${func_name} --n-vols ${drop_vols} --subject ${subject} --session ${session} --run ${run} --mask

  ## 1.5 Distortion correction (WORK ON TURNING THIS INTO A STRING TO CALL INSTEAD -- TOO MANY VARIABLES)
  ${scripts_dir}/ccs_bids_1.5_funcdistortioncorr.sh -d ${base_directory} --subject ${subject} --session ${session} --distortion-type ${diss_type} --func-name ${func_name} --func-name-2 ${func_name_2} --dwell-time ${dwell_time} --polarity-direction ${polarity_direction} --n-vols ${drop_vols}
  
  ## 2. func to anat registration
  ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh -d ${base_directory} --reg-method ${reg_method} --subject ${subject} --session ${session} --res ${func_res} --func-name ${func_name}
  
  ## 2. func to std registration
  ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --res ${func_res} --func-name ${func_name}
  
  ## 3. func segmentation
  ${scripts_dir}/ccs_bids_03_funcsegment.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --func-name ${func_name}
  
  ## 4. func generate nuisance 
  ${scripts_dir}/ccs_bids_04_funcnuisance.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --svd
  
  ## 5. func nuisance regression, filter, smoothing preproc
  ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --motion-model ${motion_model} --FWHM ${FWHM} --compcor --hp ${hp} --lp ${lp} --res 1.0

fi
