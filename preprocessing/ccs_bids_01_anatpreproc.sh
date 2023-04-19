#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from Xi-Nian Zuo https://github.com/zuoxinian/CCS
## Ting Xu, Denoise using ANTS, if only one T1w, the name has to be T1w1.nii.gz, BIDS format input
## Use acpc aligned space as the main native space 
##########################################################################################################################

while test $# -gt 0; do
	case "$1" in
		-h|--help)
			shift
			echo "ANAT PRE-PROC 01"
			echo ""
			echo "USAGE:"
			echo ""
			echo "--ref_head: template head, e.g. MNI152_T1_1mm.nii.gz in FSL data/standard/"
			echo "--ref_init_mask: template head, e.g. MNI152_T1_1mm_first_brain_mask.nii.gz in FSL data/standard/"
			echo "--base_dir: Input base directory of preprocessed data (/path/to/preprocessed_data)"
			echo "--subject: Sub name (sub-032125)"
			echo "--anat_dir_name: "
			echo "--num_scans: Number of scans (how many runs?)"
			echo "--gcut: gcut = true"
			echo "--denoise: denoise = true"
			echo ""
			exit 0
			;;
		--ref_head)
			shift
			if test $# -gt 0; then
				export template_head=$1
			else
				echo "Please specify the template head image: e.g. \$\{FSLDIR\}/data/standard/MNI152_T1_1mm.nii.gz"
			fi
			shift
			;;
		--ref_init_mask)
			shift
			if test $# -gt 0; then
				export template_init_mask=$1
			else
				echo "Please specify the template mask to initiate template-based masking: e.g. \$\{FSLDIR\}/data/standard/MNI152_T1_1mm_first_brain_mask.nii.gz"
			fi
			shift
			;;
		--base_dir)
			shift
			if test $# -gt 0; then
				export base_directory=$1
			else
				echo "Need to input base working directory (/path/to/subject_folder)"
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
		--anat_dir_name*)
			shift
			if test $# -gt 0; then
				export anat_dir_name=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify anat_dir_name"
			fi
			shift
			;;
		--num_scans*)
			shift
			export num_scans=`echo $1 | sed -e 's/^[^=]*=//g'`
			shift
			;;
		--gcut)
			shift
			export do_gcut=true
			;;
		--denoise)
			shift
			export do_denoise=true
			;;
		--prior_mask*)
			shift
			if test $# -gt 0; then
				export prior_mask=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify mask image (path/to/mask-name)"
			fi
			shift
			;;
		--prior_anat*)
			shift
			if test $# -gt 0; then
				export prior_anat=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify prior anatomicl image (path/to/prior_anat)"
			fi
			shift
			;;
		
		*)
			echo "Unspecific input"
			exit 0
			;;
	esac
done


## Setting up logging
exec > >(tee "Logs/${subject}/01_anatpreproc_log.txt") 2>&1
set -x 

## Show parameters in log file
echo "------------------------------------------------"
echo "base directory path: ${base_directory}"
echo "subject ID: ${subject}"
echo "anatomy directory name: ${anat_dir_name}"
echo "Num of scans: ${num_scans}"
echo "Do gcut (FreeSurfer skullstripping): ${gcut}"
echo "Do denoise (ANTS): ${denoise}"
echo "Custimized mask: ${mask}"
echo "------------------------------------------------"

## Setting up some common filenames / places
# anat T1w
T1w=T1w
cwd=$( pwd )
anat_dir=${base_directory}/${subject}/${anat_dir_name}
SUBJECTS_DIR=${base_directory}/${subject}/${anat_dir_name}
# FSL BET threshold 
bet_thr_tight=0.3 ; bet_thr_loose=0.1

## ======================================================
## 
echo --------------------------------------
echo !!!! PREPROCESSING ANATOMICAL SCAN!!!!
echo --------------------------------------

cd ${anat_dir}
## 1. Denoise (ANTS)
if [[ "${do_denoise}" = "true" ]]
then
  	for (( n=1; n <= ${num_scans}; n++ )); do
    	if [ ! -e ${anat_dir}/${T1w}_${n}_denoise.nii.gz ]; then
    		DenoiseImage -i ${anat_dir}/${T1w}_${n}.nii.gz -o ${anat_dir}/${T1w}_${n}_denoise.nii.gz -d 3
    	fi
	done
fi
## 2.1 FS stage-1 (average T1w images if there are more than one)
echo "Preparing data for ${sub} in freesurfer ..."
mkdir -p ${SUBJECTS_DIR}/${subject}/mri/orig
if [[ "${do_denoise}" = "true" ]] 
then
	for (( n=1; n <= ${num_scans}; n++ ))
	do
		3drefit -deoblique ${anat_dir}/${T1w}_${n}_denoise.nii.gz
		mri_convert --in_type nii ${T1w}_${n}_denoise.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done	
else
	for (( n=1; n <= ${num_scans}; n++ ))
       	do
		3drefit -deoblique ${anat_dir}/${T1w}_${n}.nii.gz
		mri_convert --in_type nii ${T1w}_${n}.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done
fi
## 2.2 FS autorecon1 - skull stripping 
echo "Auto reconstruction stage in Freesurfer (Take half hour ...)"
if [ ${gcut} = 'true' ]; then
	recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend -gcut 
else
	recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend
fi
cp ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.fsinit.mgz

## generate the registration (FS - original)
echo "Generate the registration FS to original (rawavg) space ..."
tkregister2 --mov ${SUBJECTS_DIR}/${subject}/mri/brain.mgz --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --noedit --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --fslregout ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.FSL.mat --regheader

## Change the working directory ----------------------------------
mkdir -p mask 
pushd mask

## 2.3 Do other processing in mask directory (rawavg, the first T1w space)
echo "Convert FS brain mask to original space (orientation is the same as the first input T1w)..."
mri_vol2vol --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/${subject}/mri/T1.mgz --o T1.nii.gz
mri_vol2vol --targ ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --reg ${SUBJECTS_DIR}/${subject}/mri/xfm_fs_To_rawavg.reg --mov ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz --o brain_fs.nii.gz
fslmaths brain_fs.nii.gz -abs -bin brain_mask_fs.nii.gz

## 2.5. Final BET
echo "Simply register the T1 image to the MNI152 standard space ..."
flirt -in T1.nii.gz -ref ${template_head} -out tmp_head_fs2standard.nii.gz -omat tmp_head_fs2standard.mat -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12  -interp trilinear
convert_xfm -omat tmp_standard2head_fs.mat -inverse tmp_head_fs2standard.mat

echo "Perform a tight brain extraction ..."
bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_tight} -m
fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_tight.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref T1.nii.gz
fslmaths brain_mask_fs.nii.gz -add brain_mask_fsl_tight.nii.gz -bin brain_mask_tight.nii.gz
fslmaths T1.nii.gz -mas brain_mask_fsl_tight.nii.gz brain_fsl_tight.nii.gz
fslmaths T1.nii.gz -mas brain_mask_tight.nii.gz brain_tight.nii.gz
rm -f tmp.nii.gz
3dresample -master T1.nii.gz -inset brain_tight.nii.gz -prefix tmp.nii.gz
mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz
mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.tight.mgz

echo "Perform a loose brain extraction ..."
bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_loose} -m
fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_mask_fsl_loose.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref T1.nii.gz
fslmaths brain_mask_fs.nii.gz -mul brain_mask_fsl_loose.nii.gz -bin brain_mask_loose.nii.gz
fslmaths T1.nii.gz -mas brain_mask_fsl_loose.nii.gz brain_fsl_loose.nii.gz
fslmaths T1.nii.gz -mas brain_mask_loose.nii.gz brain_loose.nii.gz
rm -f tmp.nii.gz
3dresample -master T1.nii.gz -inset brain_loose.nii.gz -prefix tmp.nii.gz
mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz
mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.loose.mgz

## 3. make sure that prior mask is in the same FS space
if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
    flirt -in ${prior_anat} -ref ${anat_dir}/mask/T1.nii.gz -omat ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -dof 6
	flirt -in ${prior_mask} -ref ${anat_dir}/mask/T1.nii.gz -applyxfm -init ${anat_dir}/mask/xfm_prior_mask_To_T1.mat -out ${anat_dir}/mask/brain_mask_prior.nii.gz
fi

## 4. Quality check
overlay 1 1 T1.nii.gz -a brain_mask_fs.nii.gz 1 1 rendered_mask.nii.gz
#FS BET
rm -f rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_strip_fs.png
title=${subject}.ccs.anat.skullstrip.fs
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_strip_fs.png skull_strip_fs.png

#FS/FSL tight BET
rm -f rendered_mask.nii.gz
overlay 1 1 T1.nii.gz -a brain_mask_tight.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_strip_tightBET.png
title=${subject}.ccs.anat.skullstrip.tightBET
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_strip_tightBET.png skull_strip_tightBET.png
rm -f rendered_mask.nii.gz
fslmaths brain_mask_fs.nii.gz -sub brain_mask_tight.nii.gz -abs -bin diff_mask_tight.nii.gz
overlay 1 1 T1.nii.gz -a diff_mask_tight.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 diff_skull_strip_tightBET.png
title=${subject}.ccs.anat.skullstrip.diff_tightBET-fs
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" diff_skull_strip_tightBET.png diff_skull_strip_tightBET.png
rm -f rendered_mask.nii.gz

#FS/FSL loose BET
rm -f rendered_mask.nii.gz
overlay 1 1 T1.nii.gz -a brain_mask_loose.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_strip_looseBET.png
title=${subject}.ccs.anat.skullstrip.looseBET
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_strip_looseBET.png skull_strip_looseBET.png
rm -f rendered_mask.nii.gz
fslmaths brain_mask_fs.nii.gz -sub brain_mask_loose.nii.gz -abs -bin diff_mask_loose.nii.gz
overlay 1 1 T1.nii.gz -a diff_mask_loose.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 diff_skull_strip_looseBET.png
title=${subject}.ccs.anat.skullstrip.diff_fs-looseBET
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" diff_skull_strip_looseBET.png diff_skull_strip_looseBET.png
rm -f rendered_mask.nii.gz 

#prior mask
if [[ ! -z ${prior_mask} ]] && [[ ! -z ${prior_anat} ]]; then
    rm -f rendered_mask.nii.gz
    overlay 1 1 T1.nii.gz -a brain_mask_prior.nii.gz 1 1 rendered_mask.nii.gz
    slicer rendered_mask -S 10 1200 skull_strip_prior.png
    title=${subject}.ccs.anat.skullstrip.prior
    convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_strip_prior.png skull_strip_prior.png
    rm -f rendered_mask.nii.gz
    fslmaths brain_mask_fs.nii.gz -sub brain_mask_prior.nii.gz diff_mask_prior.nii.gz
    overlay 1 1 T1.nii.gz -a diff_mask_prior.nii.gz 1 1 rendered_mask.nii.gz
    slicer rendered_mask -S 10 1200 diff_skull_strip_prior.png
    title=${subject}.ccs.anat.skullstrip.diff_fs-prior
    convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" diff_skull_strip_prior.png diff_skull_strip_prior.png
    rm -f rendered_mask.nii.gz
fi

## Change the working directory ----------------------------------
popd

## 4 ACPC alignment 
mkdir ${anat_dir}/reg_acpc
flirt -interp spline -in ${anat_dir}/mask/brain_fs.nii.gz -ref ${template_head} -omat ${anat_dir}/reg_acpc/orig2std.mat -out ${anat_dir}/reg_acpc/orig2std.nii.gz -dof 12
flirt -interp spline -in ${anat_dir}/mask/T1.nii.gz -ref ${template_head} -out ${anat_dir}/${T1w}_acpc.nii.gz -dof 6 -omat ${anat_dir}/reg_acpc/acpc.mat


## Clean up 
for (( n=1; n <= ${num_scans}; n++ )); do
	rm -f ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
done

cd ${cwd}
