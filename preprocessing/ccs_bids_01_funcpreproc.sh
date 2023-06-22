#!/usr/bin/env bash

##########################################################################################################################
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, functional preprocessing
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Registration

Usage: ${0}
  --func_dir=<functional directory>, e.g. base_dir/subID/func/sub-X_task-X/
  --func_name=[func], name of the functional data, default=func (e.g. <func_dir>/func.nii.gz)
  --example_volume=[8], the n-th volume as the example (Scout) func image, default=8-th 
  --drop_volume=[n], drop the first n volumes, default=5
  --slicetiming=[true, false], do slicetiming correction, default=true, make sure the infomation is correct in the json file
  --slicetiming_info=[json, 1D temporal offset file, tpattern recognizable in 3dTshift], default=json (<func_dir>/func.json)
  --TR_info=[json, TR in sec], specify TR in second, or read TR from json file, default=json (<func_dir>/func.json)
  --despiking=[true, false], do despiking, default=true
  --func_min_dir_name=[func_minimal], default=func_minimal
  --rm_exist=[true, false], clear up all existing preprocessed files and re-do this step.
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
ndvols=`getopt1 "--drop_volume" $@`
example_volume=`getopt1 "--example_volume" $@`
do_slicetiming=`getopt1 "--slicetiming" $@`
do_despiking=`getopt1 "--despiking" $@`
func_min_dir_name=`getopt1 "--out_dir_name" $@`
slicetiming_info=`getopt1 "--slicetiming_info" $@`
TR_info=`getopt1 "--TR_info" $@`
rm_exist=`getopt1 "--rm_exist" $@`


## default parameter
func=`defaultopt ${func_name} func`
ndvols=`defaultopt ${ndvols} 5`
example_volume=`defaultopt ${example_volume} 8`
do_slicetiming=`defaultopt ${do_slicetiming} true`
do_despiking=`defaultopt ${do_despiking} false`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`
slicetiming_info=`defaultopt ${do_slicetiming} json`
TR_info=`defaultopt ${TR_info} json`
rm_exist=`defaultopt ${rm_exist} true`

## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

## Show parameters in log file
Title "func preprocessing step 1: minimal preprocessing"
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "example_volume=      ${example_volume}"
Note "drop_volume=         ${ndvols}"
Note "despiking            ${do_despiking}"
Note "slicetiming=         ${do_slicetiming}"
Note "slicetiming_info=    ${slicetiming_info}"
Note "TR_info=             ${TR_info}"
Note "out_dir_name=        ${func_min_dir_name}"
Note "rm_exist=            ${rm_exist}"
echo "------------------------------------------------"


func_min_dir=${func_dir}/${func_min_dir_name}

## ----------------------------------------------------
## Check the input data
if [ ! -f ${func_dir}/${func}.nii.gz ] || [ ! -f ${func_dir}/${func}.json ]; then
  Error "Input data ${func_dir}/${func}.nii.gz or ${func}.json does not exist"
  exit 1
fi

## Extract the slicetiming information
if [ ${do_slicetiming} = "true" ]; then
  if [ $slicetiming_info = "json" ]; then
      ${CCSPIPELINE_DIR}/preprocessing/ccspy_bids_json2txt.py \
      -i ${func_dir}/${func}.json -o ${func_dir}/SliceTiming.txt -k SliceTiming -f %.8f
      tpattern="@${tpattern_file}"
  elif [ -e $slicetiming_info ]; then
    tpattern="@${tpattern_file}"
  else
    tpattern=$slicetiming_info
  fi
fi

## Extract the TR
if [ $TR_info = "json" ]; then
  ${CCSPIPELINE_DIR}/preprocessing/ccspy_bids_json2txt.py \
  -i ${func_dir}/${func}.json -o ${func_dir}/TR.txt -k RepetitionTime -f %.8f
  TR=`cat ${func_dir}/TR.txt`
elif [[ $TR_info =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  TR=${TR_info}  
fi

#####################################################################################################################
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x 

cwd=$( pwd )

## Setup the working directory and mkdir
mkdir -p ${func_min_dir}

echo "---------------------------------------"
echo "!!!! PREPROCESSING FUNCTIONAL SCAN !!!!"
echo "---------------------------------------"

cd ${func_min_dir}
## If rerun everything
if [[ ${rm_exist} == "true" ]]; then
	Title "!!! Clean up the existing preprocessed data and Run funcpreproc step"
	Do_cmd rm -f ${func}_dr.nii.gz ${func}_dspk.nii.gz ${func}_ts.nii.gz ${func}_ro.nii.gz ${func}_ro_mean.nii.gz ${func}_mc.nii.gz ${func}_mc.1D example_func.nii.gz example_func_bc.nii.gz
else
	Title "!!! The existing preprocessed files will be used, if any "
fi

## 0. Dropping first # TRS
if [[ ! -f ${func}_dr.nii.gz ]]; then
  Note "Dropping first ${ndvols} vols"
  nvols=`fslnvols ${func}.nii.gz`
  ## first timepoint (remember timepoint numbering starts from 0)
  TRstart=${ndvols} 
  ## last timepoint
  let "TRend = ${nvols} - 1"
  Do_cmd 3dcalc -a ${func}.nii.gz[${TRstart}..${TRend}] -expr 'a' -prefix ${func}_dr.nii.gz -datum float
  Do_cmd 3drefit -TR ${TR} ${func}_dr.nii.gz
else
  Note "Dropping first ${ndvols} TRs (done, skip)"
fi

## 1. Despiking (particular helpful for motion)
if [ ${do_despiking} = "true" ]; then
  if [[ ! -f ${func}_dspk.nii.gz ]]; then
    Note "Despiking timeseries for this func dataset"
    Do_cmd 3dDespike -prefix ${func}_dspk.nii.gz ${func}_dr.nii.gz
  else
    Note "Despiking timeseries for this func dataset (done, skip)"
  fi
  ts_input=${func}_dspk.nii.gz
else
  ts_input=${func}_dr.nii.gz
fi

## 2. Slice timing
if [ ${do_slicetiming} = "true" ]; then
  if [[ ! -f ${func}_ts.nii.gz ]]; then
    Note "Slice timing for this func dataset"
    Do_cmd 3dTshift -prefix ${func}_ts.nii.gz -tpattern ${tpattern} -tzero 0 ${ts_input}
  else
    Note "Slice timing for this func dataset (done, skip)"
  fi
  ro_input=${func}_ts.nii.gz
else
  ro_input=${ts_input}
fi

##3. Reorient into fsl friendly space (what AFNI calls RPI)
if [[ ! -f ${func}_ro.nii.gz ]]; then
  #echo "Deobliquing this func dataset"
  #3drefit -deoblique ${ro_input}
  Note "Reorienting for this func dataset"
  Do_cmd 3dresample -orient RPI -inset ${ro_input} -prefix ${func}_ro.nii.gz
else
  Note "Reorienting for this func dataset (done, skip)"
fi

##4. Motion correct to average of timeseries 
if [[ ! -f ${func}_mc.nii.gz ]] || [[ ! -f ${func}_mc.1D ]]; then
  Note "Motion correcting for this func dataset"
  Do_cmd rm -f ${func}_ro_mean.nii.gz
  Do_cmd 3dTstat -mean -prefix ${func}_ro_mean.nii.gz ${func}_ro.nii.gz 
  Do_cmd 3dvolreg -Fourier -twopass -base ${func}_ro_mean.nii.gz -zpad 4 -prefix ${func}_mc.nii.gz -1Dfile ${func}_mc.1D -1Dmatrix_save ${func}_mc.affine.1D ${func}_ro.nii.gz
else
  Note "Motion correcting for this func dataset (done, skip)"
fi

##5 Extract one volume as an example_func (Lucky 8)
if [[ ! -f example_func.nii.gz ]]; then
  Note "Extract one volume (No.8) as an example_func"
  let "n_example=${example_volume}-1"
  Do_cmd fslroi ${func}_mc.nii.gz example_func.nii.gz ${n_example} 1
else
  Note "Extract one volume (No.8) as an example_func (done, skip)"
fi

##6 Bias Field Correction (output is used for alignment only)
if [[ ! -f example_func_bc.nii.gz ]]; then
  Note "N4 Bias Field Correction, used for alignment only"
	Do_cmd fslmaths ${func}_mc.nii.gz -Tmean tmp_func_mc_mean.nii.gz
	Do_cmd N4BiasFieldCorrection -i tmp_func_mc_mean.nii.gz -o tmp_func_bc.nii.gz
	Do_cmd fslmaths tmp_func_mc_mean.nii.gz -sub tmp_func_bc.nii.gz ${func}_biasfield.nii.gz
	Do_cmd fslmaths example_func.nii.gz -sub ${func}_biasfield.nii.gz example_func_bc.nii.gz
	Do_cmd rm tmp_func_mc_mean.nii.gz tmp_func_bc.nii.gz
else
  Note "N4 Bias Field Correction, used for alignment only (done, skip)"
fi

cd ${cwd}
