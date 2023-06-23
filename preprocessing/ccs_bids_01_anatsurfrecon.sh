#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, Surface reconstruction (human); Input: T1w_acpc.nii.gz
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: ANAT preprocess step 1: brain extraction

Usage: ${0}
	--anat_dir=<anatomical directory>, e.g. base_dir/subID/anat or base_dir/subID/sesID/anat
	--SUBJECTS_DIR=<FreeSurfer SUBJECTS_DIR>, default=anat_dir
	--subject=<subject ID>, e.g. sub001 
  --T1w_name=[T1w name], default=T1w
	--use_gpu=[if use gpu], default=false
  --rerun_FS=[if delete FS output and redo reconstruction], default=false
  --rerun_FAST=[if delete FAST output and redo reconstruction], default=false
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
anat_dir=`getopt1 "--anat_dir" $@`
SUBJECTS_DIR=`getopt1 "--SUBJECTS_DIR" $@`
subject=`getopt1 "--subject" $@`
T1w=`getopt1 "--T1w_name" $@`
use_gpu=`getopt1 "--use_gpu" $@`
rerun_FS=`getopt1 "--rerun_FS" $@`
rerun_FAST=`getopt1 "--rerun_FAST" $@`


## default parameter
SUBJECTS_DIR=`defaultopt ${SUBJECTS_DIR} ${anat_dir}`
T1w=`defaultopt ${T1w} T1w`
use_gpu=`defaultopt ${use_gpu} false`
rerun_FS=`defaultopt ${rerun_FS} false`
rerun_FAST=`defaultopt ${rerun_FAST} false`

## Setting up logging
#exec > >(tee "Logs/${subject}/01_anatpreproc_log.txt") 2>&1
#set -x 

## Show parameters in log file
Title "anat preprocessing step 1: brain extraction"
Note "anat_dir=            ${anat_dir}"
Note "SUBJECTS_DIR=        ${SUBJECTS_DIR}"
Note "subject=             ${subject}"
Note "T1w_name=            ${T1w}"
Note "use_gpu=             ${use_gpu}"
Note "rerun_FS=            ${rerun_FS}"
Note "rerun_FAST=          ${rerun_FAST}"
echo "------------------------------------------------"

threshold_fast=0.99
cwd=$( pwd ) 
## ======================================================
## Make sure the input file exist 
T1w_image=${anat_dir}/${T1w}_acpc.nii.gz
if [ ! -e ${T1w_image} ] ; then
  Error "Input ${T1w_image} doesn't exist. Please run acpc first"
fi
## ======================================================
if [ ${rerun_FS} = "true" ]; then
  Note "Remove the current FreeSurfer output and rerun recon-all..."
  Do_cmd rm -r ${SUBJECTS_DIR}/${subject}/*
fi
if [ ${rerun_FAST} = "true" ]; then
  Note "Remove the current FSL-FAST output and rerun FAST segmentation..."
  Do_cmd rm -r ${anat_dir}/segment_fast/*
fi
## ======================================================


if [ ! -f ${SUBJECTS_DIR}/${subject}/mri/brainmask.init.fs.mgz ]; then
  mkdir -p ${SUBJECTS_DIR}/${subject}/mri/orig
  Do_cmd mri_convert ${T1w_image} ${SUBJECTS_DIR}/${subject}/mri/orig/001.mgz
  # recon-all -autoreonn1
  echo -------------------------------------------
  Info "RUNNING FreeSurfer recon-all -autorecon1"
  echo -------------------------------------------
  Do_cmd recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend

  if [ ! -f brainmask.init.fs.mgz ]; then
    Do_cmd mv brainmask.mgz brainmask.init.fs.mgz
  fi
  pushd ${SUBJECTS_DIR}/${subject}/mri
  ## generate the registration (FS - Input)
  echo "Generate the registration file FS to input (rawavg) space ..."
  Do_cmd tkregister2 --mov T1.mgz --targ rawavg.mgz --noedit --reg xfm_fs_To_rawavg.reg --fslregout xfm_fs_To_rawavg.FSL.mat    --regheader --s ${subject}
  # generate the inverse transformation matrix in FSL and lta (FS) format
  Do_cmd convert_xfm -omat xfm_rawavg_To_fs.FSL.mat -inverse xfm_fs_To_rawavg.FSL.mat
  Do_cmd tkregister2 --mov rawavg.mgz --targ T1.mgz --fsl xfm_rawavg_To_fs.FSL.mat --noedit --reg xfm_rawavg_To_fs.reg --s   {subject}
  ## Note: --ltaout-inv is not available for FS 5.3.0, but available for FS 7.3
  ## Do_cmd tkregister2 --mov T1.mgz --targ rawavg.mgz --reg xfm_fs_To_rawavg.reg --ltaout-inv --ltaout xfm_rawavg_To_fs.reg --s ${subject} 
  
  # convert the selected brain mask to FS space
  Do_cmd mri_vol2vol --interp nearest --mov ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz --targ T1.mgz --reg xfm_rawavg_To_fsreg     --o tmp.brainmask.mgz 
  Do_cmd mri_mask T1.mgz tmp.brainmask.mgz brainmask.mgz
  Do_cmd rm -rf tmp.brainmask.mgz
  popd

else
  Note "SKIP >> FreeSurfer recon-all -autorecon1 has finished"
fi


# recon-all -autoreonn2 -autorecon3
if [[ ! -e ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz ]]; then
  echo -------------------------------------------
  Info "RUNNING FreeSurfer recon-all -autorecon2 -autorecon3"
  Info "Segmenting brain for ${subject} (May take more than 24 hours ...)"
  echo -------------------------------------------
  if [ "${use_gpu}" = "true" ]; then
    Do_cmd recon-all -s ${subject} -autorecon2 -autorecon3 -no-isrunning -careg -use-gpu 
  else
    Do_cmd recon-all -s ${subject} -autorecon2 -autorecon3 -no-isrunning -careg
  fi
else
  Note " SKIP >> FreeSurfer recon-all -autorecon2 -autorecon3 has finished"
fi

if [ ${rerun_FS} = "true" ] || [ ! -f segment_wm+sub+stem.nii.gz ]; then
  ## FS segmentation: 
  echo "-------------------------------------------"
  echo "FS segmentation"
  echo "-------------------------------------------"
  Do_cmd mkdir ${anat_dir}/segment
  Do_cmd cd ${anat_dir}/segment
  ## freesurfer version
  echo "RUN >> Convert FS aseg to create csf/wm segment files"
  Do_cmd cp ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz segment_brain.nii.gz
  #mri_convert -it mgz ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz -ot nii aseg.nii.gz
  Do_cmd mri_vol2vol --interp nearest --mov ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz --targ ${SUBJECTS_DIR}/${subject}mri/   rawavg.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --o aseg.nii.gz 
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_gm.nii.gz --gm
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm.nii.gz --match 2 41 7 46 251 252 253 254 255 
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_csf.nii.gz --match 4 5 43 44 31 63 
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm_erode1.nii.gz --match 2 41 7 46 251 252 253 254 255 --erode 1
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_csf_erode1.nii.gz --match 4 5 43 44 31 63 --erode 1
  # Create for flirt -bbr to match with FAST wm output to include Thalamus, Thalamus-Proper*, VentralDC, Stem
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm+sub+stem.nii.gz --match 2 41 7 46 251 252 253 254 255 9 48 10 49 28 60 16
else
  Note "SKIP >> segmentation are created from FreeSurfer output"
fi

## FAST segmentation: CSF: *_pve_0, GM: *_pve_1, WM: *_pve_2
echo "-------------------------------------------"
echo "FAST segmentation"
echo "-------------------------------------------"
Do_cmd mkdir ${anat_dir}/segment_fast
Do_cmd cd ${anat_dir}/segment_fast
if [[ ! -e segment_pveseg.nii.gz ]]; then
  Info "Running FAST ..."
  Do_cmd fast -S 3 -o segment ${T1w_image}
else
  Note "SKIP >> FAST segmentation done"
fi
if [ ${rerun_FAST} = "true" ] || [ ! -f segment_wm_erode1.nii.gz ]; then
  Info "RUN >> Threshold FSL-FAST to create csf/wm segment files"
  Info "Segmentation threshold of FSL-FAST for wm and csf: ${threshold_fast}"
  Do_cmd cp ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz segment_brain.nii.gz
  Do_cmd fslmaths segment_pve_1.nii.gz -thr ${threshold_fast} segment_csf.nii.gz
  Do_cmd fslmaths segment_pve_2.nii.gz -thr ${threshold_fast} segment_wm.nii.gz
  Do_cmd mri_binarize --i segment_csf.nii.gz --o segment_csf_erode1.nii.gz --match 1 --erode 1
  Do_cmd mri_binarize --i segment_wm.nii.gz --o segment_wm_erode1.nii.gz --match 1 --erode 1
else
  Note "SKIP >> Threshold FSL-FAST to create csf/wm segment files"
fi

Do_cmd cd ${cwd}
