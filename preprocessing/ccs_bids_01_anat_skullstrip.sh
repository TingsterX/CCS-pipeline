#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, Denoise using ANTS; T1w and masks are all in raw space
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: ANAT preprocess step 1: brain extraction

Usage: ${0}
	--ref_head=[template head ], default=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz
	--ref_init_mask=[initial template mask], default=${FSLDIR}/data/standard/MNI152_T1_1mm_first_brain_mask.nii.gz
	--anat_dir=<anatomical directory>, e.g. base_dir/subID/anat or base_dir/subID/sesID/anat
	--subject=<subject ID>, e.g. sub001 
	--num_scans=[number of scans], default=1
	--T1w_name=[T1w name], default=T1w
	--gcut=[if use gcut option in FS], default=true
	--denoise=[if use denoise in ANTS], default=true
	--prior_mask=[custimized brain mask]
	--prior_anat=[underlay of the custimized brain mask]
	--do_skullstrip=[if perform FS/FSL skullstripping], default=true
	
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
subject=`getopt1 "--subject" $@`
T1w=`getopt1 "--T1w_name" $@`
num_scans=`getopt1 "--num_scans" $@`
do_gcut=`getopt1 "--gcut" $@`
do_denoise=`getopt1 "--denoise" $@`
prior_mask=`getopt1 "--prior_mask" $@`
prior_anat=`getopt1 "--prior_anat" $@`
do_skullstrip=`getopt1 "--do_skullstrip" $@`

## default parameter
template_head=`defaultopt ${template_head} ${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz`
template_init_mask=`defaultopt ${template_init_mask} ${FSLDIR}/data/standard/MNI152_T1_1mm_first_brain_mask.nii.gz`
num_scans=`defaultopt ${num_scans} 1`
T1w=`defaultopt ${T1w} T1w`
do_gcut=`defaultopt ${do_gcut} true`
do_denoise=`defaultopt ${do_denoise} true`
do_skullstrip=`defaultopt ${do_skullstrip} true`

## If prior_mask is provided, make sure prior_anat is also provided
if [ ! -z ${prior_mask} ] ; then
	if [ -z ${prior_anat} ]; then
		Error "Please specify the underlay image of the prior mask"
	fi
else
	do_skullstrip=true
	Info "No prior mask is specified, run FS and FSL skullstripping"
fi


## Setting up logging
#exec > >(tee "Logs/${subject}/01_anatpreproc_log.txt") 2>&1
#set -x 

## Show parameters in log file
Title "anat preprocessing step 1: brain extraction"
Note "template_head=       ${template_head}"
Note "template_init_mask=  ${template_init_mask}"
Note "anat_dir=            ${anat_dir}"
Note "subject=             ${subject}"
Note "T1w_name             ${T1w}"
Note "num_scans=           ${num_scans}"
Note "gcut=                ${do_gcut}"
Note "denoise=             ${do_denoise}"
Note "prior_mask=          ${prior_mask}"
Note "prior_anat=          ${prior_anat}"
Note "do_skullstrip=       ${do_skullstrip}"
echo "------------------------------------------------"


## Setting up other parameters
# FSL BET threshold 
bet_thr_tight=0.3 ; bet_thr_loose=0.1

# vcheck function 
vcheck_mask() {
	underlay=$1
	overlay=$2
	figout=$3
	title=$4
	echo "----->> vcheck mask"
	Do_cmd overlay 1 1 ${underlay} -a ${overlay} 1 1 tmp_rendered_mask.nii.gz
	Do_cmd slicer tmp_rendered_mask.nii.gz -S 10 1200 ${figout}
	Do_cmd rm -f tmp_rendered_mask.nii.gz
}

## ======================================================
## 
echo ----------------------------------------------------
echo PREPROCESSING ANATOMICAL SCAN - skull stripping
echo ----------------------------------------------------
cwd=$( pwd )
Do_cmd mkdir ${anat_dir}/reg

Do_cmd cd ${anat_dir}

## 1. Denoise (ANTS)
if [[ "${do_denoise}" = "true" ]]; then
  	for (( n=1; n <= ${num_scans}; n++ )); do
    	if [ ! -e ${anat_dir}/${T1w}_${n}_denoise.nii.gz ]; then
    		Do_cmd DenoiseImage -i ${anat_dir}/${T1w}_${n}.nii.gz -o ${anat_dir}/${T1w}_${n}_denoise.nii.gz -d 3
    	fi
	done
fi

## 2. Average multiple T1 images and run bias field correction
if [ ! -e ${anat_dir}/${T1w}.nii.gz ]; then
    T1w_scans_list=""
    for (( n=1; n <= ${num_scans}; n++ )); do
    	if [[ "${do_denoise}" = "true" ]]; then
    		T1w_scans_list="${T1w_scans_list} ${T1w}_${n}_denoise.nii.gz"
    	else
    		T1w_scans_list="${T1w_scans_list} ${T1w}_${n}.nii.gz"
    	fi
    done
    if [ ${num_scans} -gt 1 ]; then
    	Do_cmd mri_robust_template --mov ${T1w_scans_list} --average 1 --template ${anat_dir}/${T1w}.nii.gz --satit --inittp 1 --fixtp --noit --iscale     --iscaleout ${anat_dir}/reg/${T1w_scans_list//.nii.gz/-iscale.txt} --subsample 200 --lta ${anat_dir}/reg/${T1w_scans_list//.nii.gz/.lta}
    	for T1w_scan in ${T1w_scans_list}; do
    		Do_cmd lta_convert --inlat ${T1w_scan//.nii.gz/.lta} --outfsl ${T1w_scan//.nii.gz/.mat}
    	done
    else
    	Do_cmd cp -L ${anat_dir}/${T1w_scans_list/\ /} ${anat_dir}/${T1w}.nii.gz
    fi
    ## Deoblique
    Do_cmd 3drefit -deoblique ${anat_dir}/${T1w}.nii.gz
fi
# Bias Field Correction (N4)
if [ ! -f ${anat_dir}/${T1w}_bc.nii.gz ]; then
	Do_cmd N4BiasFieldCorrection -d 3 -i ${anat_dir}/${T1w}.nii.gz -o ${anat_dir}/${T1w}_bc.nii.gz
fi


## DO skullstriping in FS, FSL-BET
Do_cmd mkdir -p ${anat_dir}/mask
if [ ${do_skullstrip} = true ]; then
	# Input of the FS, FSL-BET
	## FS stage-1 (average T1w images if there are more than one)
	echo "Preparing data for ${sub} in freesurfer ..."
	Do_cmd mkdir -p ${anat_dir}/mask/FS/mri/orig
	Do_cmd mri_convert --in_type nii ${anat_dir}/${T1w}_bc.nii.gz ${anat_dir}/mask/FS/mri/orig/001.mgz
	## 3.1 FS autorecon1 - skull stripping
	SUBJECTS_DIR=${anat_dir}/mask
	if [ ! -f ${SUBJECTS_DIR}/FS/mri/brainmask.mgz ]; then
	echo "Auto reconstruction stage in Freesurfer (Take half hour ...)"
	if [[ ${do_gcut} = 'true' ]]; then
		Do_cmd recon-all -s FS -autorecon1 -notal-check -clean-bm -no-isrunning -noappend -gcut 
	else
		Do_cmd recon-all -s FS -autorecon1 -notal-check -clean-bm -no-isrunning -noappend
	fi
	fi
	
	## generate the registration (FS - original)
	echo "Generate the registration file FS to original (rawavg) space ..."
	Do_cmd tkregister2 --mov ${SUBJECTS_DIR}/FS/mri/T1.mgz --targ ${SUBJECTS_DIR}/FS/mri/rawavg.mgz --noedit --reg ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.reg --fslregout ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.FSL.mat --regheader --s FS 
	## invert affine matrix: invert the FSL affine matrix and transfer back to FS format
	Do_cmd convert_xfm -omat ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.FSL.mat -inverse ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.FSL.mat
	Do_cmd tkregister2 --mov ${SUBJECTS_DIR}/FS/mri/rawavg.mgz --targ ${SUBJECTS_DIR}/FS/mri/T1.mgz --fsl ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.FSL.mat --noedit --reg ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.reg --s FS 
	## Note: --ltaout-inv is not available for FS 5.3.0, but available for FS 7.3
	## Do_cmd tkregister2 --mov ${SUBJECTS_DIR}/FS/mri/T1.mgz --targ ${SUBJECTS_DIR}/FS/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.reg --ltaout-inv --ltaout ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.reg 
	

	## Clean up
	Do_cmd rm -rf ${anat_dir}/mask/FS/stats ${anat_dir}/mask/FS/trash ${anat_dir}/mask/FS/touch ${anat_dir}/mask/FS/tmp ${anat_dir}/mask/FS/surf ${anat_dir}/mask/FS/src ${anat_dir}/mask/FS/bem ${anat_dir}/mask/FS/label
	Do_cmd rm -rf ${anat_dir}/mask/FS/mri/orig/001.mgz 

	## Generate brain mask in mask directory
	## Change the working directory ----------------------------------
	Do_cmd pushd ${anat_dir}/mask

	## 3.2 Do other processing in mask directory (rawavg, the first T1w space)
	echo "Convert FS brain mask to original space (orientation is the same as the first input T1w)..."
	Do_cmd mri_vol2vol --targ ${SUBJECTS_DIR}/FS/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/FS/mri/T1.mgz --o T1.nii.gz
	Do_cmd mri_vol2vol --targ ${SUBJECTS_DIR}/FS/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/FS/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/FS/mri/brainmask.mgz --o brain_fs.nii.gz
	Do_cmd fslmaths brain_fs.nii.gz -abs -bin brain_mask_fs.nii.gz

	## 3.3 BET using tight and loose parameter
	echo "Simply register the T1 image to the standard space ..."
	Do_cmd flirt -in T1.nii.gz -ref ${template_head} -out tmp_head_fs2standard.nii.gz -omat tmp_head_fs2standard.mat -bins 256 -cost corratio 	-searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12  -interp trilinear
	Do_cmd convert_xfm -omat tmp_standard2head_fs.mat -inverse tmp_head_fs2standard.mat

	echo "Perform a tight brain extraction ..."
	Do_cmd bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_tight} -m
	Do_cmd fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
	Do_cmd flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_tight.nii.gz -paddingsize 0.0 -interp 	nearestneighbour -ref T1.nii.gz
	Do_cmd fslmaths brain_mask_fs.nii.gz -add brain_mask_fsl_tight.nii.gz -bin brain_mask_fs+.nii.gz
	Do_cmd fslmaths T1.nii.gz -mas brain_mask_fsl_tight.nii.gz brain_fsl_tight.nii.gz
	Do_cmd fslmaths T1.nii.gz -mas brain_mask_fs+.nii.gz brain_fs+.nii.gz
	Do_cmd mri_vol2vol --mov brain_fs+.nii.gz --targ ${SUBJECTS_DIR}/FS/mri/T1.mgz --reg ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.reg --o ${SUBJECTS_DIR}/FS/mri/brain_fs+.mgz 
	Do_cmd mri_mask ${SUBJECTS_DIR}/FS/mri/T1.mgz ${SUBJECTS_DIR}/FS/mri/brain_fs+.mgz ${SUBJECTS_DIR}/FS/mri/brainmask.tight.mgz

	echo "Perform a loose brain extraction ..."
	Do_cmd bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_loose} -m
	Do_cmd fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
	Do_cmd flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_loose.nii.gz -paddingsize 0.0 -interp 	nearestneighbour -ref T1.nii.gz
	Do_cmd fslmaths brain_mask_fs.nii.gz -mul brain_mask_fsl_loose.nii.gz -bin brain_mask_fs-.nii.gz
	Do_cmd fslmaths T1.nii.gz -mas brain_mask_fsl_loose.nii.gz brain_fsl_loose.nii.gz
	Do_cmd fslmaths T1.nii.gz -mas brain_mask_fs-.nii.gz brain_fs-.nii.gz
	Do_cmd mri_vol2vol --mov brain_fs-.nii.gz --targ ${SUBJECTS_DIR}/FS/mri/T1.mgz --reg ${SUBJECTS_DIR}/FS/mri/xfm_rawavg_To_fs.reg --o ${SUBJECTS_DIR}/FS/mri/brain_fs-.mgz
	Do_cmd mri_mask ${SUBJECTS_DIR}/FS/mri/T1.mgz ${SUBJECTS_DIR}/FS/mri/brain_fs-.mgz ${SUBJECTS_DIR}/FS/mri/brainmask.loose.mgz
	
	## clean up
	Do_cmd rm -rf tmp_mask.nii.gz tmp_standard2head_fs.mat tmp_head_fs2standard.mat


	## 4. Quality check
	#FS BET
	Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz brain_mask_fs.nii.gz vcheck_skull_strip_fs.png fs

	#FS/FSL tight BET
	Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz brain_mask_fs+.nii.gz vcheck_skull_strip_fs+.png fs+
	Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_fs+.nii.gz -abs -bin diff_mask_fs+.nii.gz
	Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz diff_mask_fs+.nii.gz vcheck_diff_skull_strip_fs+.png diff.fs+

	#FS/FSL loose BET
	Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz brain_mask_fs-.nii.gz vcheck_skull_strip_fs-.png fs-
	Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_fs-.nii.gz -abs -bin diff_mask_fs-.nii.gz
	Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz diff_mask_fs-.nii.gz vcheck_diff_skull_strip_fs-.png diff.fs-

	## Change the working directory ----------------------------------
	Do_cmd popd

fi # end if [ ${do_skullstrip} = true ]

Do_cmd pushd ${anat_dir}/mask

## 3.4 make sure that prior mask is in the same raw space
if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
	Do_cmd ln -s ${prior_mask} prior_mask_link.nii.gz
	Do_cmd ln -s ${prior_anat} prior_anat_link.nii.gz
    Do_cmd flirt -in ${prior_anat} -ref ${anat_dir}/${T1w}_bc.nii.gz -omat ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -dof 6
	Do_cmd convert_xfm -omat ${anat_dir}/mask/xfm_T1_To_prior_mask.mat  -inverse ${anat_dir}/mask/xfm_prior_mask_To_T1.mat 
	Do_cmd flirt -in ${prior_mask} -ref ${anat_dir}/${T1w}_bc.nii.gz -applyxfm -init ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -out ${anat_dir}/mask/brain_mask_prior.nii.gz -interp nearestneighbour
	Do_cmd fslmaths ${anat_dir}/${T1w}_bc.nii.gz -mas ${anat_dir}/mask/brain_mask_prior.nii.gz ${anat_dir}/${T1w}_bc_brain_prior.nii.gz
	
	## vcheck prior mask
    vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz brain_mask_prior.nii.gz vcheck_skull_strip_prior.png prior
	if [ ${do_skullstrip} = true ]; then
    	Do_cmd fslmaths brain_mask_fs.nii.gz -sub brain_mask_prior.nii.gz  diff_mask_prior-fs.nii.gz
		Do_cmd fslmaths diff_mask_prior.nii.gz -thr 0 -abs -bin tmp_diff_mask_prior+.nii.gz
		Do_cmd fslmaths diff_mask_prior.nii.gz -uthr 0 -abs -bin tmp_diff_mask_prior-.nii.gz
		Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz tmp_diff_mask_prior+.nii.gz vcheck_diff_skull_strip_prior+.png diff.prior+
		Do_cmd vcheck_mask ${anat_dir}/${T1w}_bc.nii.gz tmp_diff_mask_prior-.nii.gz vcheck_diff_skull_strip_prior-.png diff.prior-
		Do_cmd rm tmp_diff_mask_prior+.nii.gz tmp_diff_mask_prior-.nii.gz
	fi	
fi
## specify the init brain mask
if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
	Do_cmd ln -s brain_mask_prior.nii.gz brain_mask_init.nii.gz
else
	Do_cmd ln -s brain_mask_fs.nii.gz brain_mask_init.nii.gz
fi

Do_cmd popd

## Get back to the directory
Do_cmd cd ${cwd}
