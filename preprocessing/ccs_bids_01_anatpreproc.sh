#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from Xi-Nian Zuo https://github.com/zuoxinian/CCS
## Ting Xu, Denoise using ANTS, if only one T1w, the name has to be T1w1.nii.gz, BIDS format input
## Use acpc aligned space as the main native space 
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: ANAT preprocess step 1: brain extraction, ACPC alignment

Usage: ${0}
	--ref_head=[template head ], default=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz
	--ref_init_mask=[initial template mask], default=${FSLDIR}/data/standard/MNI152_T1_1mm_first_brain_mask.nii.gz
	--anat_dir=<anatomical directory>, e.g. base_dir/subID/anat or base_dir/subID/sesID/anat
	--SUBJECTS_DIR=<FreeSurfer SUBJECTS_DIR>, e.g. base_dir/subID/sesID
	--subject=<subject ID>, e.g. sub001 
	--T1w_name=[T1w name], default=T1w
	--num_scans=[number of scans], default=1
	--gcut=[if use gcut option in FS], default=true
	--denoise=[if use denoise in ANTS], default=true
	--prior_mask=[custimized brain mask]
	--prior_anat=[underlay of the custimized brain mask]
	
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
template_init_mask=`getopt1 "--ref_init_mask" $@`
anat_dir=`getopt1 "--anat_dir" $@`
SUBJECTS_DIR=`getopt1 "--SUBJECTS_DIR" $@`
subject=`getopt1 "--subject" $@`
T1w=`getopt1 "--T1w_name" $@`
num_scans=`getopt1 "--num_scans" $@`
do_gcut=`getopt1 "--gcut" $@`
do_denoise=`getopt1 "--denoise" $@`
prior_mask=`getopt1 "--prior_mask" $@`
prior_anat=`getopt1 "--prior_anat" $@`

## default parameter
template_head=`defaultopt ${template_head} ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz`
template_init_mask=`defaultopt ${template_init_mask} ${FSLDIR}/data/standard/MNI152_T1_1mm_first_brain_mask.nii.gz`
T1w=`defaultopt ${T1w} T1w`
do_gcut=`defaultopt ${do_gcut} true`
do_denoise=`defaultopt ${do_denoise} true`

## If prior_mask is provided, make sure prior_anat is also provided
if [ ! -z ${prior_mask} ]; then
	if [ -z ${prior_anat} ]; then
		Error "Please specify the underlay image of the prior mask"
	fi
fi


## Setting up logging
#exec > >(tee "Logs/${subject}/01_anatpreproc_log.txt") 2>&1
#set -x 

## Show parameters in log file
Title "anat preprocessing step 1: brain extraction and ACPC alignment"
Note "template_head=       ${template_head}"
Note "template_init_mask=  ${template_init_mask}"
Note "anat_dir=            ${anat_dir}"
Note "SUBJECTS_DIR=        ${SUBJECTS_DIR}"
Note "subject=             ${subject}"
Note "T1w_name             ${T1w}"
Note "num_scans=           ${num_scans}"
Note "gcut=                ${do_gcut}"
Note "denoise=             ${do_denoise}"
Note "prior_mask=          ${prior_mask}"
Note "prior_anat=          ${prior_anat}"
echo "------------------------------------------------"


## Setting up other parameters
# FSL BET threshold 
bet_thr_tight=0.3 ; bet_thr_loose=0.1

# vcheck function 
vcheck_mask(){
	underlay=$1
	overlay=$2
	figout=$3
	title=$4
	echo "----->> vcheck mask"
	Do_cmd overlay 1 1 ${underlay} -a ${overlay} 1 1 tmp_rendered_mask.nii.gz
	Do_cmd slicer tmp_rendered_mask.nii.gz -S 10 1200 ${figout}
	Do_cmd title=${title}
	Do_cmd convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" ${figout} ${figout}
	Do_cmd rm -f tmp_rendered_mask.nii.gz
}

## ======================================================
## 
echo --------------------------------------
echo !!!! PREPROCESSING ANATOMICAL SCAN!!!!
echo --------------------------------------
cwd=$( pwd )

Do_cmd cd ${anat_dir}
## 1. Denoise (ANTS)
if [[ "${do_denoise}" = "true" ]]; then
  	for (( n=1; n <= ${num_scans}; n++ )); do
    	if [ ! -e ${anat_dir}/${T1w}_${n}_denoise.nii.gz ]; then
    		Do_cmd DenoiseImage -i ${anat_dir}/${T1w}_${n}.nii.gz -o ${anat_dir}/${T1w}_${n}_denoise.nii.gz -d 3
    	fi
	done
fi
## 2.1 FS stage-1 (average T1w images if there are more than one)
echo "Preparing data for ${sub} in freesurfer ..."
mkdir -p ${SUBJECTS_DIR}/${subject}/mri/orig
if [[ "${do_denoise}" = "true" ]]; then
	for (( n=1; n <= ${num_scans}; n++ ))
	do
		Do_cmd 3drefit -deoblique ${anat_dir}/${T1w}_${n}_denoise.nii.gz
		Do_cmd mri_convert --in_type nii ${T1w}_${n}_denoise.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done	
else
	for (( n=1; n <= ${num_scans}; n++ ))
       	do
		Do_cmd 3drefit -deoblique ${anat_dir}/${T1w}_${n}.nii.gz
		Do_cmd mri_convert --in_type nii ${T1w}_${n}.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done
fi
## 2.2 FS autorecon1 - skull stripping 
echo "Auto reconstruction stage in Freesurfer (Take half hour ...)"
if [ ${gcut} = 'true' ]; then
	Do_cmd recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend -gcut 
else
	Do_cmd recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend
fi
Do_cmd cp ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.fsinit.mgz

## generate the registration (FS - original)
echo "Generate the registration file FS to original (rawavg) space ..."
Do_cmd tkregister2 --mov ${SUBJECTS_DIR}/${subject}/mri/brain.mgz --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --noedit --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --fslregout ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.FSL.mat --regheader

## Change the working directory ----------------------------------
Do_cmd mkdir -p mask 
Do_cmd pushd mask

## 2.3 Do other processing in mask directory (rawavg, the first T1w space)
echo "Convert FS brain mask to original space (orientation is the same as the first input T1w)..."
Do_cmd mri_vol2vol --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/${subject}/mri/T1.mgz --o T1.nii.gz
Do_cmd mri_vol2vol --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz --o brain_fs.nii.gz
Do_cmd fslmaths brain_fs.nii.gz -abs -bin brain_mask_fs.nii.gz

## 2.5. BET using tight and loose parameter
echo "Simply register the T1 image to the MNI152 standard space ..."
Do_cmd flirt -in T1.nii.gz -ref ${template_head} -out tmp_head_fs2standard.nii.gz -omat tmp_head_fs2standard.mat -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12  -interp trilinear
Do_cmd convert_xfm -omat tmp_standard2head_fs.mat -inverse tmp_head_fs2standard.mat

echo "Perform a tight brain extraction ..."
Do_cmd bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_tight} -m
Do_cmd fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
Do_cmd flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_tight.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref T1.nii.gz
Do_cmd fslmaths brain_mask_fs.nii.gz -add brain_mask_fsl_tight.nii.gz -bin brain_mask_tight.nii.gz
Do_cmd fslmaths T1.nii.gz -mas brain_mask_fsl_tight.nii.gz brain_fsl_tight.nii.gz
Do_cmd fslmaths T1.nii.gz -mas brain_mask_tight.nii.gz brain_tight.nii.gz
Do_cmd rm -f tmp.nii.gz
Do_cmd 3dresample -master T1.nii.gz -inset brain_tight.nii.gz -prefix tmp.nii.gz
Do_cmd mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz
Do_cmd mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.tight.mgz

echo "Perform a loose brain extraction ..."
Do_cmd bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_loose} -m
Do_cmd fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
Do_cmd flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_loose.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref T1.nii.gz
Do_cmd fslmaths brain_mask_fs.nii.gz -mul brain_mask_fsl_loose.nii.gz -bin brain_mask_loose.nii.gz
Do_cmd fslmaths T1.nii.gz -mas brain_mask_fsl_loose.nii.gz brain_fsl_loose.nii.gz
Do_cmd fslmaths T1.nii.gz -mas brain_mask_loose.nii.gz brain_loose.nii.gz
Do_cmd rm -f tmp.nii.gz
Do_cmd 3dresample -master T1.nii.gz -inset brain_loose.nii.gz -prefix tmp.nii.gz
Do_cmd mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz
Do_cmd mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.loose.mgz

## 3. make sure that prior mask is in the same FS space
	if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
	Do_cmd fslmaths ${prior_anat} -mas ${prior_mask} ${anat_dir}/mask/tmp_prior_brain.nii.gz
    Do_cmd flirt -in ${prior_anat} -ref ${anat_dir}/mask/T1.nii.gz -omat ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -dof 6
	Do_cmd flirt -in ${prior_mask} -ref ${anat_dir}/mask/T1.nii.gz -applyxfm -init ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -out ${anat_dir}/mask/brain_mask_prior.nii.gz
fi

## 4. Quality check
#FS BET
vcheck_mask T1.nii.gz brain_mask_fs.nii.gz skull_strip_fs.png FS

#FS/FSL tight BET
vcheck_mask T1.nii.gz brain_mask_tight.nii.gz skull_strip_BETtight.png BETtight
Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_tight.nii.gz -abs -bin diff_mask_tight.nii.gz
vcheck_mask T1.nii.gz diff_mask_tight.nii.gz diff_skull_strip_BETtight.png diff.BETtight.FS

#FS/FSL loose BET
vcheck_mask T1.nii.gz brain_mask_loose.nii.gz skull_strip_BETloose.png BETloose
Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_loose.nii.gz -abs -bin diff_mask_loose.nii.gz
vcheck_mask T1.nii.gz diff_mask_loose.nii.gz diff_skull_strip_BETloose.png diff.BETloose.FS

#prior mask
if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
    vcheck_mask T1.nii.gz brain_mask_prior.nii.gz skull_strip_prior.png prior
    Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_prior.nii.gz diff_mask_prior.nii.gz
	vcheck_mask T1.nii.gz diff_mask_prior.nii.gz diff_skull_strip_prior.png diff_FS.prior
fi

## Change the working directory ----------------------------------
Do_cmd popd

## Clean up 
for (( n=1; n <= ${num_scans}; n++ )); do
	Do_cmd rm -f ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
done

Do_cmd cd ${cwd}
