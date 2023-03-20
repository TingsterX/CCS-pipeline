#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from Xi-Nian Zuo https://github.com/zuoxinian/CCS
## Ting Xu, Denoise using ANTS, if only one T1w, the name has to be T1w1.nii.gz, BIDS format input
##########################################################################################################################

while test $# -gt 0; do
	case "$1" in
		-h|--help)
			shift
			echo "ANAT PRE-PROC 01"
			echo ""
			echo "USAGE:"
			echo ""
			echo "-d: Input base working directory (/path/to/subject_folder)"
			echo "--subject: Sub name (sub-032125)"
			echo "--session: Ses name (ses-001)"
			echo "--num-scans: Number of scans (how many runs?)"
			echo "--gcut: gcut = true"
			echo "--denoise: denoise = true"
			echo ""
			exit 0
			;;
		-d)
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
		--session*)
			shift
			if test $# -gt 0; then
				export session=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify session number"
			fi
			shift
			;;
		--num-scans*)
			shift
			export num_scans=`echo $1 | sed -e 's/^[^=]*=//g'`
			shift
			;;
		--gcut)
			shift
			export gcut=true
			;;
		--denoise)
			shift
			export do_denoise=true
			;;
		--mask*)
			shift
			if test $# -gt 0; then
				export mask=`echo $1 | sed -e 's/^[^=]*=//g'`
				export use_mask=true
			else
				echo "Need to specify mask directory (path/to/mask-name)"
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
echo "Base-directory: $base_directory"
echo "Subject: $subject"
echo "Session: $session"
echo "Num-scans: $num_scans"
echo "Gcut: $gcut"
echo "Denoise: $denoise"
echo "Mask: $use_mask"
echo "------------------------------------------------"

## Setting up some common filenames / places
# anat T1w
anat=${subject}_${session}
cwd=$( pwd )
anat_dir=${base_directory}/${subject}/${session}/anat
SUBJECTS_DIR=${base_directory}/${subject}/${session}




## template
template_init_mask=${base_directory}/../../templates/MacaqueYerkes19_T1w_1.0mm_brain_mask.nii.gz
echo --------------------------------------
echo !!!! PREPROCESSING ANATOMICAL SCAN!!!!
echo --------------------------------------

cd ${anat_dir}
bet_thr_tight=0.3 ; bet_thr_loose=0.1
## 1. Denoise (ANTS)
if [[ "${do_denoise}" = "true" ]]
then
  	for (( n=1; n <= ${num_scans}; n++ )); do
    	if [ ! -e ${anat_dir}/${anat}_run-${n}_T1w_denoise.nii.gz ]; then
    		DenoiseImage -i ${anat_dir}/${anat}_run-${n}_T1w.nii.gz -o ${anat_dir}/${anat}_run-${n}_T1w_denoise.nii.gz -d 3
    	fi
	done
fi
## 2. FS stage-1
echo "Preparing data for ${sub} in freesurfer ..."
mkdir -p ${SUBJECTS_DIR}/${subject}/mri/orig
if [[ "${do_denoise}" = "true" ]] 
then
	for (( n=1; n <= ${num_scans}; n++ ))
	do
		3drefit -deoblique ${anat_dir}/${anat}_run-${n}_T1w_denoise.nii.gz
		mri_convert --in_type nii ${anat}_run-${n}_T1w_denoise.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done	
else
	for (( n=1; n <= ${num_scans}; n++ ))
       	do
		3drefit -deoblique ${anat_dir}/${anat}_run-${n}_T1w.nii.gz
		mri_convert --in_type nii ${anat}_run-${n}_T1w.nii.gz ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
	done
fi
echo "Auto reconstruction stage in Freesurfer (Take half hour ...)"
if [ ${gcut} = 'true' ]; then
	recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -gcut -no-isrunning -noappend
	if [ ${use_mask} = 'true' ]; then
		mri_convert -it nii ${mask}.nii.gz -ot mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
	fi
	cp ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.fsinit.mgz
else
	recon-all -s ${subject} -autorecon1 -notal-check -clean-bm -no-isrunning -noappend
	if [ ${use_mask} = 'true' ]; then
		mri_convert -it nii ${mask}.nii.gz -ot mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz
	fi
	cp ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.fsinit.mgz
fi

## Do other processing in VCHECK directory
mkdir -p mask 
cd mask
echo "Preparing extracted brain for FSL registration ..."
mri_convert -it mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.mgz -ot nii ${anat_dir}/mask/brainmask.nii.gz
mri_convert -it mgz ${SUBJECTS_DIR}/${subject}/mri/T1.mgz -ot nii ${anat_dir}/mask/T1.nii.gz

## 2. Reorient to fsl-friendly space
echo "Reorienting ${subject} anatomical"
rm -f brain_fs.nii.gz
3dresample -orient RPI -inset brainmask.nii.gz -prefix brain_fs_tmp.nii.gz
rm -f head_fs.nii.gz
3dresample -orient RPI -inset T1.nii.gz -prefix head_fs.nii.gz
3dresample -inset brain_fs_tmp.nii.gz -prefix brain_fs.nii.gz -master T1.nii.gz
fslmaths brain_fs.nii.gz -abs -bin brain_fs_mask.nii.gz
#rm -rf brainmask.nii.gz ; 
for (( n=1; n <= ${num_scans}; n++ ))
do
	rm -f ${SUBJECTS_DIR}/${subject}/mri/orig/00${n}.mgz
done

## 3. Final BET
echo "Simply register the T1 image to the MNI152 standard space ..."
flirt -in head_fs.nii.gz -ref ${base_directory}/../../templates/MacaqueYerkes19_T1w_1.0mm.nii.gz -out tmp_head_fs2standard.nii.gz -omat tmp_head_fs2standard.mat -bins 256 -cost corratio -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -dof 12  -interp trilinear
convert_xfm -omat tmp_standard2head_fs.mat -inverse tmp_head_fs2standard.mat
echo "Perform a tight brain extraction ..."
bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_tight} -m
fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_fsl_mask_tight.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref head_fs.nii.gz
fslmaths brain_fs_mask.nii.gz -add brain_fsl_mask_tight.nii.gz -bin brain_mask_tight.nii.gz
fslmaths head_fs.nii.gz -mas brain_fsl_mask_tight.nii.gz brain_fsl_tight.nii.gz
fslmaths head_fs.nii.gz -mas brain_mask_tight.nii.gz brain_tight.nii.gz
rm -f tmp.nii.gz
3dresample -master T1.nii.gz -inset brain_tight.nii.gz -prefix tmp.nii.gz
mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz
mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_tight.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.tight.mgz
echo "Perform a loose brain extraction ..."
bet tmp_head_fs2standard.nii.gz tmp.nii.gz -f ${bet_thr_loose} -m
fslmaths tmp_mask.nii.gz -mas ${template_init_mask} tmp_mask.nii.gz
flirt -in tmp_mask.nii.gz -applyxfm -init tmp_standard2head_fs.mat -out brain_fsl_mask_loose.nii.gz -paddingsize 0.0 -interp nearestneighbour -ref head_fs.nii.gz
fslmaths brain_fs_mask.nii.gz -mul brain_fsl_mask_loose.nii.gz -bin brain_mask_loose.nii.gz
fslmaths head_fs.nii.gz -mas brain_fsl_mask_loose.nii.gz brain_fsl_loose.nii.gz
fslmaths head_fs.nii.gz -mas brain_mask_loose.nii.gz brain_loose.nii.gz
rm -f tmp.nii.gz
3dresample -master T1.nii.gz -inset brain_loose.nii.gz -prefix tmp.nii.gz
mri_convert --in_type nii tmp.nii.gz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz
mri_mask ${SUBJECTS_DIR}/${subject}/mri/T1.mgz ${SUBJECTS_DIR}/${subject}/mri/brain_loose.mgz ${SUBJECTS_DIR}/${subject}/mri/brainmask.loose.mgz
## 4. Quality check
#rm -f tmp* T1.nii.gz
overlay 1 1 head_fs.nii.gz -a brain_fs_mask.nii.gz 1 1 rendered_mask.nii.gz
#FS BET
slicer rendered_mask -S 10 1200 skull_fs_strip.png
title=${subject}.ccs.anat.fs.skullstrip
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_fs_strip.png skull_fs_strip.png
#FS/FSL tight BET
rm -f rendered_mask.nii.gz
overlay 1 1 head_fs.nii.gz -a brain_mask_tight.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_tight_strip.png
title=${subject}.ccs.anat.skullstrip
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_tight_strip.png skull_tight_strip.png
rm -f rendered_mask.nii.gz
fslmaths brain_fs_mask.nii.gz -sub brain_mask_tight.nii.gz -abs -bin diff_mask_tight.nii.gz
overlay 1 1 head_fs.nii.gz -a diff_mask_tight.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_tight_strip_diff.png
title=${subject}.ccs.anat.skullstrip.diff
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_tight_strip_diff.png skull_tight_strip_diff.png
rm -f rendered_mask.nii.gz
#FS/FSL loose BET
rm -f rendered_mask.nii.gz
overlay 1 1 head_fs.nii.gz -a brain_mask_loose.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_loose_strip.png
title=${subject}.ccs.anat.skullstrip
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_loose_strip.png skull_loose_strip.png
rm -f rendered_mask.nii.gz
fslmaths brain_fs_mask.nii.gz -sub brain_mask_loose.nii.gz -abs -bin diff_mask_loose.nii.gz
overlay 1 1 head_fs.nii.gz -a diff_mask_loose.nii.gz 1 1 rendered_mask.nii.gz
slicer rendered_mask -S 10 1200 skull_loose_strip_diff.png
title=${subject}.ccs.anat.skullstrip.diff
convert -font helvetica -fill white -pointsize 36 -draw "text 30,50 '$title'" skull_loose_strip_diff.png skull_loose_strip_diff.png
rm -f rendered_mask.nii.gz

cd ${cwd}
