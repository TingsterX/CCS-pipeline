#!/usr/bin/env bash

##########################################################################################################################
## CCS SCRIPT TO PREPROCESS THE ANATOMICAL SCAN (INTEGRATE AFNI/FSL/FREESURFER/ANTS)
## Revised from https://github.com/zuoxinian/CCS
## Ting Xu, Denoise using ANTS; T1w and masks are all in raw space
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Registration

Usage: ${0}
	--ref_head=[template head ], default=${FSLDIR}/data/standard/MNI152_T1_2mm.nii.gz
	--ref_brain=[initial template mask], default=${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz
        --ref_mask=[initial template mask], default=${FSLDIR}/data/standard/MNI152_T1_2mm_brain_mask_dil.nii.gz
	--anat_dir=<anatomical directory>, e.g. base_dir/subID/anat or base_dir/subID/sesID/anat
	--subject=<subject ID>, e.g. sub001 
	--T1w_name=[T1w name], default=T1w
        --reg_method=[FSL, ANTS], default=FNIRT
        --fnirt_config=[fnirt configuration], default=${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf
        --ref_nonlinear=[head, brain], default=head
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
template_mask=`getopt1 "--ref_mask" $@`
anat_dir=`getopt1 "--anat_dir" $@`
subject=`getopt1 "--subject" $@`
T1w=`getopt1 "--T1w_name" $@`
reg_method=`getopt1 "--reg_method" $@`
fnirt_config=`getopt1 "--fnirt_config" $@`

## default parameter
template_head=`defaultopt ${template_head} ${FSLDIR}/data/standard/MNI152_T1_2mm.nii.gz`
template_brain=`defaultopt ${template_init_mask} ${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz`
template_mask=`defaultopt ${template_init_mask} ${FSLDIR}/data/standard/MNI152_T1_2mm_brain_mask_dil.nii.gz`
T1w=`defaultopt ${T1w} T1w`
reg_method=`defaultopt ${reg_method} FNIRT`
fnirt_config=`defaultopt ${fnirt_config} ${FSLDIR}/etc/flirtsch/T1_2_MNI152_2mm.cnf`
ref_nonlinear=`defaultopt ${ref_nonlinear} head`

## If prior_mask is provided, make sure prior_anat is also provided
if [ ! ${reg_method} = "FSL" ] || [ ! ${reg_method} = "ANTS" ]; then
        Error "Specify registration method! FNIRT or ANTS"
        exit 1
fi
if [ ! ${ref_nonlinear} = "head" ] || [ ! ${ref_nonlinear} = "brain" ]; then
        Error "Specify reference for nonlinear registration: head(default) or brain"
        exit 1
fi

## Setting up logging
#exec > >(tee "Logs/${subject}/${0/.sh/.txt}") 2>&1
#set -x 

## Show parameters in log file
Title "anat preprocessing step 1: brain extraction"
Note "ref_head=            ${template_head}"
Note "ref_brain=           ${template_head}"
Note "ref_mask=            ${template_mask}"
Note "anat_dir=            ${anat_dir}"
Note "subject=             ${subject}"
Note "T1w_name             ${T1w}"
Note "reg_method=          ${reg_method}"
Note "fnirt_config=        ${fnirt_config}"
echo "------------------------------------------------"


# ----------------------------------------------------
anat_reg_dir_name=xfms
## directory setup
anat_seg_dir=${anat_dir}/segment
atlas_space_dir=${anat_dir}/TemplateSpace
anat_reg_dir=${anat_dir}/TemplateSpace/${anat_reg_dir_name}

T1w_image=${T1w}_acpc_dc
T1w_head=${anat_dir}/${T1w_image}.nii.gz
T1w_brain=${anat_dir}/${T1w_image}_brain.nii.gz
T1w_mask=${anat_dir}/${T1w_image}_brain_mask.nii.gz
RegTransform=acpc_dc2standard.nii.gz
RegInvTransform=standard2acpc_dc.nii.gz

if [ ${ref_nonlinear} = "brain" ]; then
  native_image=${T1w_brain}
  ref_nonlinear=${template_brain}
else
  native_image=${T1w_head}
  ref_nonlinear=${template_head}
fi
# ----------------------------------------------------

# Link T1w_acpc_dc -> T1w_acpc
if [ ! -f ${T1w_brain} ]; then
        pushd ${anat_dir}
        ln -s ${T1w}_acpc.nii.gz ${T1w}_acpc_dc.nii.gz
        ln -s ${T1w}_acpc_brain.nii.gz ${T1w}_acpc_dc_brain.nii.gz
        ln -s ${T1w}_acpc_brain_mask.nii.gz ${T1w}_acpc_dc_brain_mask.nii.gz
        popd
fi

# ----------------------------------------------------
# vcheck the registration quality
vcheck_reg() {
  underlay=$1
  edge_image=$2
  figout=$3
  mkdir -p $(dirname ${figout})/tmp
  pushd $(dirname ${figout})/tmp
  3dedgedog -input ${edge_image} -prefix tmp_edge.nii.gz
  overlay 1 1 ${underlay} -a tmp_edge.nii.gz 1 1 tmp_rendered.nii.gz
  slicer tmp_rendered.nii.gz -S 10 1200 ${figout}
  popd
  rm -f $(dirname ${figout})/tmp
}
# ----------------------------------------------------


echo -----------------------------------------
echo !!!! RUNNING ANATOMICAL REGISTRATION !!!!
echo -----------------------------------------

pushed ${anat_reg_dir}
if [ ${reg_method} = "FSL" ]; then
  Note "Registration using FSL"
  Do_cmd flirt -dof 12 -ref ${template_brain} -in ${T1w_brain} -omat ${anat_reg_dir}/acpc2standard.mat -cost corratio-searchcost   corratio -interp spline -out ${anat_reg_dir}/flirt_${T1w_image}_to_standard.nii.gz
  Do_cmd convert_xfm -omat standard2acpc.mat -inverse acpc2standard.mat
  Do_cmd fnirt --in=${native_image} --ref=${ref_nonlinear} --aff=acpc2standard.mat --refmask=${template_mask} --fout=$  {RegTransform} --jout=NonlinearRegJacobians.nii.gz --refout=IntensityModulatedT1nii.gz --iout=fnirt_${T1w_image}_to_standard.nii.gz --logout=NonlinearReg.txt --intout=NonlinearIntensities.nii.gz --cout=NonlinearReg.nii.gz --config=${FNIRTConfig}
  Do_cmd invwarp -w ${RegTransform} -o ${RegInvTransform} -r ${template_head}

elif [ ${reg_method} = "ANTS" ]; then
  Note "Registration using ANTS (flirt affine)"
  Do_cmd flirt -dof 12 -ref ${template_brain} -in ${T1w_brain} -omat ${anat_reg_dir}/acpc2standard.mat -cost corratio-searchcost   corratio -interp spline -out ${anat_reg_dir}/flirt_${T1w_native}_to_standard.nii.gz
  Do_cmd convert_xfm -omat standard2acpc.mat -inverse acpc2standard.mat
  Do_cmd c3d_affine_tool standard2acpc.mat -ref ${template_brain} -src ${T1w_brain} -fsl2ras -oitk acpc2standard_itk_affine.mat
  Do_cmd antsRegistrationSyN.sh -d 3 -f ${ref_nonlinear} -m ${native_image} -i acpc2standard_itk_affine.mat -t so -o ${T1w_image}_to_template_

  # combine all the affine and non-linear warps in the order: W1, A1
  Do_cmd antsApplyTransforms -d 3 -i ${native_image} -r ${ref_nonlinear} -t ${T1w_image}_to_template_1Warp.nii.gz -t acpc2standard_itk_affine.mat -o [ANTs_CombinedWarp.nii.gz,1] 
  # combine inverse warps in the order A1, W1
  Do_cmd antsApplyTransforms -d 3 -i ${native_image} -r ${ref_nonlinear} -t [acpc2standard_itk_affine.mat,1] -t ${T1w_image}_to_template_1InverseWarp.nii.gz -o [ANTs_CombinedInvWarp.nii.gz,1]


  #Conversion of ANTs to FSL format
  Note " ANTs to FSL warp conversion"
  # split 3 component vectors
  Do_cmd c4d -mcs ANTs_CombinedWarp.nii.gz -oo e1.nii.gz e2.nii.gz e3.nii.gz
  # split 3 component vectors for Inverse Warps
  Do_cmd c4d -mcs ANTs_CombinedInvWarp.nii.gz -oo e1inv.nii.gz e2inv.nii.gz e3inv.nii.gz
  # reverse y_hat
  Do_cmd fslmaths e2.nii.gz -mul -1 e-2.nii.gz
  # reverse y_hat for Inverse
  Do_cmd fslmaths e2inv.nii.gz -mul -1 e-2inv.nii.gz
  # merge to get FSL format warps
  # later on clean up the eX.nii.gz
  Do_cmd fslmerge -t ${RegTransform} e1.nii.gz e-2.nii.gz e3.nii.gz
  # merge to get FSL format Inverse warps
  Do_cmd fslmerge -t ${RegInvTransform} e1inv.nii.gz e-2inv.nii.gz e3inv.nii.gz
  # Combine the inverse warps and get it in FSL format
  # create Jacobian determinant
  Do_cmd CreateJacobianDeterminantImage 3 ${RegTransform} NonlinearRegJacobians.nii.gz [doLogJacobian=0] [useGeometric=0]

fi
popd

# applywarp to native space to template space T1w_acpc_* 
Do_cmd applywarp --rel --interp=spline -i ${T1w_head} -r ${template_head} -w ${RegTransform} -o ${atlas_space_dir}/${T1w_image}.nii.gz
Do_cmd applywarp --rel --interp=nn -i ${T1w_mask} -r ${template_head} -w ${RegTransform} -o ${atlas_space_dir}/${T1w_image}_brain_mask.nii.gz
Do_cmd fslmaths ${atlas_space_dir}/${T1w_image}.nii.gz -mas ${atlas_space_dir}/${T1w_image}_brain_mask.nii.gz ${atlas_space_dir}/${T1w_image}_brain.nii.gz


if [ ! -f ${anat_reg_dir}/vcheck/figure_acpc2standard_AnatBoundary.png ]; then
  Do_cmd mkdir -f ${anat_reg_dir}/vcheck
  Do_cmd vcheck_reg ${atlas_space_dir}/${T1w_image}.nii.gz ${template_brain} ${anat_reg_dir}/vcheck/figure_acpc2standard_RefBoundary.png
  Do_cmd vcheck_reg ${template_head} ${atlas_space_dir}/${T1w_image}_brain.nii.gz ${anat_reg_dir}/vcheck/figure_acpc2standard_AnatBoundary.png
else
  Note "Vcheck figures for the registration have been done for this session!"
fi

cd ${cwd}
