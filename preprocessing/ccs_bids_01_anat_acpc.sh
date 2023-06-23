#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from https://github.com/zuoxinian/CCS
## Use acpc aligned space as the main native space 
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: ANAT preprocess step 2: ACPC alignment

Usage: ${0}
	--ref_head=[template head used for ACPC alignment], default=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz
	--ref_brain=[template brain used for ACPC alignment], default=${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz
	--anat_dir=<anatomical directory>, e.g. base_dir/subID/anat or base_dir/subID/sesID/anat
	--SUBJECTS_DIR=<FreeSurfer SUBJECTS_DIR>, e.g. base_dir/subID/sesID
	--subject=<subject ID>, e.g. sub001 
	--T1w_name=[T1w name], default=T1w
	--mask_select=[fs/fs+/fs-/prior], default=fs
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
template_head=`getopt1 "--ref_head" $@`
template_brain=`getopt1 "--ref_brain" $@`
anat_dir=`getopt1 "--anat_dir" $@`
SUBJECTS_DIR=`getopt1 "--SUBJECTS_DIR" $@`
subject=`getopt1 "--subject" $@`
T1w=`getopt1 "--T1w_name" $@`
mask_select=`getopt1 "--mask_select" $@`

## default parameter
template_head=`defaultopt ${template_head} ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz`
template_brain=`defaultopt ${template_brain} ${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz`
T1w=`defaultopt ${T1w} T1w`
mask_select=`defaultopt ${mask_select} fs`

## Setting up logging
#exec > >(tee "Logs/${subject}/01_anatpreproc_log.txt") 2>&1
#set -x 

## Show parameters in log file
Title "anat preprocessing step 2: ACPC alignment"
Note "template_head=       ${template_head}"
Note "template_brain=      ${template_brain}"
Note "anat_dir=            ${anat_dir}"
Note "SUBJECTS_DIR=        ${SUBJECTS_DIR}"
Note "subject=             ${subject}"
Note "T1w_name             ${T1w}"
Note "mask_select=         ${mask_select}"
echo "------------------------------------------------"

## set the selected brain mask 
T1w_brain_mask=${anat_dir}/mask/brain_mask_${mask_select}.nii.gz
if [ ! -f ${T1w_brain_mask} ]; then
    Error "Selected brain mask ${T1w_brain_mask} doesn't exist, please check"
    exit;
fi

## ======================================================
## 
echo ----------------------------------------------------
echo  PREPROCESSING ANATOMICAL SCAN - ACPC alignment
echo ----------------------------------------------------
cwd=$( pwd )
acpc_reg_dir=${anat_dir}/xfms
Do_cmd mkdir ${acpc_reg_dir}
Do_cmd cd ${anat_dir}

# create Sympolic link to the mask selected
ln -s mask/brain_mask_${mask_select}.nii.gz ${T1w}_brain_mask.nii.gz
Do_cmd fslmaths ${anat_dir}/${T1w}.nii.gz -mas ${T1w_brain_mask} ${anat_dir}/${T1w}_brain.nii.gz

## ACPC alignment
Do_cmd flirt -in ${anat_dir}/${T1w}_brain.nii.gz -ref ${template_brain} -omat ${acpc_reg_dir}/orig2std_dof12.mat -dof 12
Do_cmd flirt -interp spline -in ${anat_dir}/${T1w}_brain.nii.gz -ref ${template_brain} -applyxfm -init ${acpc_reg_dir}/orig2std_dof12.mat -out ${acpc_reg_dir}/orig2std_dof12.nii.gz
Do_cmd flirt -in ${anat_dir}/${T1w}_brain.nii.gz -ref ${acpc_reg_dir}/orig2std_dof12.nii.gz -out ${acpc_reg_dir}/${T1w}_acpc_step1.nii.gz -dof 6 -omat ${acpc_reg_dir}/acpc_step1.mat
Do_cmd flirt -in ${acpc_reg_dir}/${T1w}_acpc_step1.nii.gz -ref ${acpc_reg_dir}/orig2std_dof12.nii.gz -out ${acpc_reg_dir}/${T1w}_acpc_step2.nii.gz -dof 6 -omat ${acpc_reg_dir}/acpc_step2.mat
Do_cmd convert_xfm -omat ${acpc_reg_dir}/acpc.mat -concat ${acpc_reg_dir}/acpc_step2.mat ${acpc_reg_dir}/acpc_step1.mat
Do_cmd aff2rigid ${acpc_reg_dir}/acpc.mat ${acpc_reg_dir}/acpc.mat
Do_cmd flirt -interp spline -in ${anat_dir}/${T1w}.nii.gz -ref ${template_brain} -applyxfm -init ${acpc_reg_dir}/acpc.mat -out ${anat_dir}/${T1w}_acpc.nii.gz
Do_cmd flirt -interp nearestneighbour -in ${anat_dir}/${T1w}_brain_mask.nii.gz -ref ${template_brain} -applyxfm -init ${acpc_reg_dir}/acpc.mat -out ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz
Do_cmd fslmaths ${anat_dir}/${T1w}_acpc.nii.gz -mas ${anat_dir}/${T1w}_acpc_brain_mask.nii.gz ${anat_dir}/${T1w}_acpc_brain.nii.gz

## Get back to the directory
Do_cmd cd ${cwd}
