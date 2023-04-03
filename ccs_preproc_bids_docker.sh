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

## Set up functions for usage and checking to make sure required variables are set
usage () {
  echo ""
  echo "Usage (BIDS format):"
  echo ""
  echo "Mandatory arguments:"
  echo "-d <path/to/subject-folder> : Specify input folder"
  echo "--subject <sub-??????> : Subject folder ID"
  echo "--session <ses-???> : Specify session number"
  echo "--run <run-?> : Run number"
  echo ""
  echo "Optional arguments:"
  echo "--topup : Run TOPUP distortion correction"
  echo "--omni : Run OMNI distortion correction"
  echo "--fugue : Run FUGUE distortion correction"
  echo "--func-name (if running functional preprocessing) : Name of functional scan"
  echo "--func-name-2 : Name of second functional scan (used for distortion correction if using TOPUP)"
  echo "--dwell-time : Dwell time in ms"
  echo "--drop-vols : Number of volumes to drop from beginning of functional scan"
  echo "--polarity-direction <x/y/z> : Polarity direction of the functional images (if using topup)"
  echo "--mask <path/to/mask_file.nii.gz> : Input mask to use in pipeline"
  echo ""
  echo "All variables can also be set in the *.config file, sourced at the beginning of the pipeline"
}

check_variables () {
  if [ -z $subject ]; then
    usage
    echo ""
    echo "ERROR: Need to specify subject"
    exit 0
  elif [ -z $session ]; then
    usage
    echo ""
    echo "ERROR: Need to specify session"
    exit 0
  elif [ -z $base_directory ]; then
    usage
    echo ""
    echo "ERROR: Need to specify base-directory"
    exit 0
  elif [ -z $run ]; then
    usage
    echo ""
    echo "ERROR: Need to specify run"
    exit 0
  elif [ $run_func == "true" ]; then
    if [ -z $func_name ]; then
      usage
      echo ""
      echo "ERROR: Need to specify functional scan name"
      exit 0
    fi
    if [[ $dist_corr == *"--topup"* ]]; then
      if [ -z $polarity_direction ]; then
        usage
        echo ""
        echo "ERROR: If using topup, need to specify polarity direction"
        exit 0
      elif [ -z $dwell_time ]; then
        usage
        echo ""
        echo "ERROR: If using topup, need to specify dwell time in ms"
        exit 0
      elif [ -z $func_name_2 ]; then
        usage
        echo ""
        echo "ERROR: If using topup, need to specify second functional scan name"
        exit 0
      fi
    fi
    if [[ $dist_corr == *"--fugue"* ]]; then
      if [ -z $dwell_time ]; then
        usage
        echo ""
        echo "ERROR: If using fugue, need to specify dwell time in ms"
        exit 0
      elif [ -z $fieldmap_name ]; then
        usage
        echo ""
        echo "ERROR: If using fugue, need to specify name of fieldmap image"
        exit 0
      fi
    fi
  fi
}

## Read JSON file for dwell time + slice timing 


################### Take parameters #################

while test $# -gt 0; do
  case "$1" in
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
    --topup)
      shift
      add_dist_corr="--topup "
      export dist_corr="$dist_corr$add_dist_corr"
      ;;
    --fugue)
      shift
      add_dist_corr="--fugue "
      export dist_corr="$dist_corr$add_dist_corr"
      ;;
    --omni)
      shift
      add_dist_corr="--omni "
      export dist_corr="$dist_corr$add_dist_corr"
      ;;
    --no-dc)
      shift
      add_dist_corr="--no-dc "
      export dist_corr="$dist_corr$add_dist_corr"
      ;;
    *)
      usage
      echo ""
      echo "Invalid input : $1"
      exit 0
  esac
done

if [ -z $dist_corr ]; then $dist_corr="--no-dc"; fi

## Check to make sure the variables are set before starting the pipeline
check_variables
  
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
####################################################################################################################

## Set up logging directory in working directory
if [ ! -d "./Logs/${subject}" ]; then
  mkdir -p ./Logs/${subject}
elif [ -d "./Logs/${subject}" ]; then
  rm -r ./Logs/${subject}
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
  ${scripts_dir}/ccs_bids_1.5_funcdistortioncorr.sh -d ${base_directory} --subject ${subject} --session ${session} ${dist_corr} --func-name ${func_name} --func-name-2 ${func_name_2} --dwell-time ${dwell_time} --polarity-direction ${polarity_direction} --n-vols ${drop_vols}

  if [[ $dist_corr == *"--topup"* ]]; then
    ## 2. func to anat registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh -d ${base_directory} --dc-method topup --reg-method ${reg_method} --subject ${subject} --session ${session} --res ${func_res} --func-name ${func_name}
  
    ## 2. func to std registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh -d ${base_directory} --dc-method topup --subject ${subject} --session ${session} --run ${run} --res ${func_res} --func-name ${func_name}
  
    ## 3. func segmentation
    ${scripts_dir}/ccs_bids_03_funcsegment.sh -d ${base_directory} --dc-method topup --subject ${subject} --session ${session} --run ${run} --func-name ${func_name}
  
    ## 4. func generate nuisance 
    ${scripts_dir}/ccs_bids_04_funcnuisance.sh -d ${base_directory} --dc-method topup --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --svd
  
    ## 5. func nuisance regression, filter, smoothing preproc
    ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh -d ${base_directory} --dc-method topup --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --motion-model ${motion_model} --FWHM ${FWHM} --compcor --hp ${hp} --lp ${lp} --res 1.0
  fi
  if [[ $dist_corr == *"--omni"* ]]; then
    ## 2. func to anat registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh -d ${base_directory} --dc-method omni --reg-method ${reg_method} --subject ${subject} --session ${session} --res ${func_res} --func-name ${func_name}
  
    ## 2. func to std registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh -d ${base_directory} --dc-method omni --subject ${subject} --session ${session} --run ${run} --res ${func_res} --func-name ${func_name}
  
    ## 3. func segmentation
    ${scripts_dir}/ccs_bids_03_funcsegment.sh -d ${base_directory} --dc-method omni --subject ${subject} --session ${session} --run ${run} --func-name ${func_name}
  
    ## 4. func generate nuisance 
    ${scripts_dir}/ccs_bids_04_funcnuisance.sh -d ${base_directory} --dc-method omni --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --svd
  
    ## 5. func nuisance regression, filter, smoothing preproc
    ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh -d ${base_directory} --dc-method omni --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --motion-model ${motion_model} --FWHM ${FWHM} --compcor --hp ${hp} --lp ${lp} --res 1.0
  fi
  if [[ $dist_corr == *"--fugue"* ]]; then
    ## 2. func to anat registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh -d ${base_directory} --dc-method fugue --reg-method ${reg_method} --subject ${subject} --session ${session} --res ${func_res} --func-name ${func_name}
  
    ## 2. func to std registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh -d ${base_directory} --dc-method fugue --subject ${subject} --session ${session} --run ${run} --res ${func_res} --func-name ${func_name}
  
    ## 3. func segmentation
    ${scripts_dir}/ccs_bids_03_funcsegment.sh -d ${base_directory} --dc-method fugue --subject ${subject} --session ${session} --run ${run} --func-name ${func_name}
  
    ## 4. func generate nuisance 
    ${scripts_dir}/ccs_bids_04_funcnuisance.sh -d ${base_directory} --dc-method fugue --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --svd

    ## 5. func nuisance regression, filter, smoothing preproc
    ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh -d ${base_directory} --dc-method fugue --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --motion-model ${motion_model} --FWHM ${FWHM} --compcor --hp ${hp} --lp ${lp} --res 1.0
  fi
  if [[ $dist_corr == *"--no-dc"* ]]; then
    ## 2. func to anat registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2anat.sh -d ${base_directory} --dc-method no-dc --reg-method ${reg_method} --subject ${subject} --session ${session} --res ${func_res} --func-name ${func_name}
  
    ## 2. func to std registration
    ${scripts_dir}/ccs_bids_02_funcregister_func2std.sh -d ${base_directory} --dc-method no-dc --subject ${subject} --session ${session} --run ${run} --res ${func_res} --func-name ${func_name}
  
    ## 3. func segmentation
    ${scripts_dir}/ccs_bids_03_funcsegment.sh -d ${base_directory} --dc-method no-dc --subject ${subject} --session ${session} --run ${run} --func-name ${func_name}
  
    ## 4. func generate nuisance 
    ${scripts_dir}/ccs_bids_04_funcnuisance.sh -d ${base_directory} --dc-method no-dc --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --svd

    ## 5. func nuisance regression, filter, smoothing preproc
    ${scripts_dir}/ccs_bids_05_funcpreproc_vol.sh -d ${base_directory} --dc-method no-dc --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --motion-model ${motion_model} --FWHM ${FWHM} --compcor --hp ${hp} --lp ${lp} --res 1.0
  fi
fi
