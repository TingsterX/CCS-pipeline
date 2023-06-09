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
  --rerun=[if delete FS output and redo reconstruction], default=false
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
rerun=`getopt1 "--rerun" $@`


## default parameter
SUBJECTS_DIR=`defaultopt ${SUBJECTS_DIR} ${anat_dir}`
T1w=`defaultopt ${T1w} T1w`
use_gpu=`defaultopt ${use_gpu} false`
rerun=`defaultopt ${do_denoise} false`

## Make sure the input file exist (T1w_acpc.nii.gz) 
if [ ! -e ${anat_dir}/${T1w}_acpc.nii.gz ] ; then
  Error "Input ${anat_dir}/${T1w}_acpc.nii.gz doesn't exist. Please run acpc first"
fi

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
Note "rerun=               ${rerun}"
echo "------------------------------------------------"

## ======================================================
## 
echo ------------------------------------------
echo !!!! RUNNING FreeSurfer  !!!!
echo ------------------------------------------
## directory setup

## 1. Change to anat dir
cwd=$( pwd ) 

mkdir -p ${SUBJECTS_DIR}/${subject}/mri/orig
Do_cmd mri_convert ${anat_dir}/${T1w}_acpc.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/001.mgz
Do_cmd recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend

# recon-all -autoreonn1
pushd ${SUBJECTS_DIR}/${subject}/mri
## generate the registration (FS - Input)
echo "Generate the registration file FS to input (rawavg) space ..."
Do_cmd tkregister2 --mov T1.mgz --targ rawavg.mgz --noedit --reg xfm_fs_To_rawavg.reg --fslregout xfm_fs_To_rawavg.FSL.mat --regheader --s ${subject}
if [ ! -f brainmask.init.fs.mgz ]; then
  Do_cmd mv brainmask.mgz brainmask.init.fs.mgz
fi
# generate the inverse transformation matrix in FSL and lta (FS) format
Do_cmd convert_xfm -omat xfm_rawavg_To_fs.FSL.mat -inverse xfm_fs_To_rawavg.FSL.mat
Do_cmd tkregister2 --s ${subject} --mov T1.mgz --targ rawavg.mgz --reg xfm_fs_To_rawavg.reg --ltaout-inv --ltaout xfm_rawavg_To_fs.reg
## The inverse transformation matrix can be also converted from FSL to FS
## tkregister2 --s ${subject} --mov rawavg.mgz --targ T1.mgz --fsl xfm_fs_To_rawavg.FSL.mat --noedit --reg xfm_rawavg_To_fs.reg

# convert the selected brain mask to FS space
Do_cmd mri_vol2vol --interp nearest --mov ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz --targ T1.mgz --reg xfm_rawavg_To_fs.reg --o tmp.brainmask.mgz 
Do_cmd mri_mask T1.mgz tmp.brainmask.mgz brainmask.mgz
Do_cmd rm -rf tmp.brainmask.mgz
popd

# recon-all -autoreonn2 -autorecon3
if [[ ! -e ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz ]]; then
  echo "Segmenting brain for ${subject} (May take more than 24 hours ...)"
  if [ "${use_gpu}" = "true" ]; then
    Do_cmd recon-all -s ${subject} -autorecon2 -autorecon3 -use-gpu -no-isrunning
  else
    Do_cmd recon-all -s ${subject} -autorecon2 -autorecon3 -no-isrunning
  fi
fi

## FAST segmentation: CSF: *_pve_0, GM: *_pve_1, WM: *_pve_2
echo "-------------------------------------------"
echo "FAST segmentation"
echo "-------------------------------------------"
Do_cmd mkdir ${anat_dir}/segment
Do_cmd cd ${anat_dir}/segment
## freesurfer version
if [ ! -f segment_wm_erode1.nii.gz ] || [ ! -f segment_csf_erode1.nii.gz ]; then
  echo "RUN >> Convert FS aseg to create csf/wm segment files"
  #mri_convert -it mgz ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz -ot nii aseg.nii.gz
  Do_cmd mri_vol2vol --interp nearest --mov ${SUBJECTS_DIR}/${subject}/mri/aseg.mgz --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --reg xfm_fs_To_rawavg.reg --o aseg.nii.gz --regheader
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm.nii.gz --match 2 41 7 46 251 252 253 254 255 
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_csf.nii.gz --match 4 5 43 44 31 63 
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm_erode1.nii.gz --match 2 41 7 46 251 252 253 254 255 --erode 1
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_csf_erode1.nii.gz --match 4 5 43 44 31 63 --erode 1
  # Create for flirt -bbr to match with FAST wm output to include Thalamus, Thalamus-Proper*, VentralDC, Stem
  Do_cmd mri_binarize --i aseg.nii.gz --o segment_wm+sub+stem.nii.gz --match 2 41 7 46 251 252 253 254 255 9 48 10 49 28 60 16
else
  echo "SKIP >> Convert FS aseg to create csf/wm segment files"
fi

## FAST segmentation: CSF: *_pve_0, GM: *_pve_1, WM: *_pve_2
echo "-------------------------------------------"
echo "FAST segmentation"
echo "-------------------------------------------"
Do_cmd mkdir ${anat_dir}/segment_fast
Do_cmd cd ${anat_dir}/segment_fast
if [[ ! -e segment_pveseg.nii.gz ]]; then
  Do_cmd fast -o segment ${anat_seg_dir}/${T1w}_acpc.nii.gz
else
  echo "SKIP >> FAST segmentation done"
fi
if [ ! -f segment_wm_erode1.nii.gz ] || [ ! -f segment_csf_erode1.nii.gz ]; then
  echo "RUN >> Convert FS aseg to create csf/wm segment files"
  Do_cmd fslmaths segment_pve_1.nii.gz -thr 0.99 segment_csf.nii.gz
  Do_cmd fslmaths segment_pve_2.nii.gz -thr 0.99 segment_wm.nii.gz
  Do_cmd mri_binarize --i segment_csf.nii.gz --o segment_csf_erode1.nii.gz --match 1 --erode 1
  Do_cmd mri_binarize --i segment_wm.nii.gz --o segment_wm_erode1.nii.gz --match 1 --erode 1
else
  echo "SKIP >> Convert FS aseg to create csf/wm segment files"
fi

Do_cmd cd ${cwd}
