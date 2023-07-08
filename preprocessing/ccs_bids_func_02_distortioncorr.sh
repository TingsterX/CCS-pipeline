#!/usr/bin/env bash

##########################################################################################################################
## Sam Alldritt, Tng Xu
##########################################################################################################################

Usage() {
	cat <<EOF

${0}: Function Pipeline: distortion correction ()

Usage: ${0}
  --func_dir=<functional directory>, e.g. base_dir/subID/func/sub-X_task-X/
  --func_name=[func], name of the functional data, default=func (e.g. <func_dir>/func.nii.gz)
  --anat_dir=<anatomical directory>, specify the anat directory 
  --anat_ref_name=<T1w, T2w>, name of the anatomical reference name, default=T1w
  --dc_method=[none, topup, fugue, omni]
  --dc_dir=[path to the distortion corrected directory which contains example_func_bc_dc.nii.gz]
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
func=`getopt1 "--func_name" $@`
anat_dir=`getopt1 "--anat_dir" $@`
anat_ref_name=`getopt1 "--anat_ref_name" $@`
dc_method=`getopt1 "--dc_method" $@`
dc_dir=`getopt1 "--dc_dir" $@`

## default parameter
func=`defaultopt ${func} func`
anat_ref_name=`defaultopt ${anat_ref_name} T1w`
dc_method=`defaultopt ${dc_method} none`
func_min_dir_name=`defaultopt ${func_min_dir_name} func_minimal`


## Setting up logging
#exec > >(tee "Logs/${func_dir}/${0/.sh/.txt}") 2>&1
#set -x 

Title "Function Pipeline: registration (func->anat) "
Note "func_name=           ${func}"
Note "func_dir=            ${func_dir}"
Note "anat_dir=            ${anat_dir}"
Note "anat_ref_name=       ${anat_ref_name}"
Note "dc_method=           ${dc_method}"
Note "dc_dir=              ${dc_dir}"
Note "func_min_dir_name=   ${func_min_dir_name}"
echo "------------------------------------------------"


        --program)
            shift
            export program=$1
            shift
            ;;
        ## do we need to run fsl_prepare_fieldmap
        --prepare-fieldmap*)
            shift
            if test $# -gt 0; then
                export prepare_fieldmap=true
                export fieldmap_name=$1
            else
                echo "Need to specify the name of your desired/existing fieldmap file"
            fi
            shift
            ;;
        --dwell-time*)
            shift
            export dwell_time=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --polarity-direction*)
            shift
            if test $# -gt 0; then
                if [ $1 == 'x' ] || [ $1 == 'y' ] || [ $1 == 'z' ]; then
                    export polarity_direction=$1
                fi
            else
                echo "Invalid polarity direction (accepted: x, y, z)"
            fi
            shift
            ;;
        ## path to phase image
        --phase-image-name*)
            shift
            export phase_image=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        ## path to magnitude image
        --magnitude-image-name*)
            shift
            export mag_image=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        ## do we need to brain extract magnitude image
        --mag-bet)
            export mag_bet=true
            shift
            ;;
        ## do we need to convert phase image to radians
        --convert-radians)
            export convert_to_radians=true
            shift
            ;;
        ## do we have delta-TE?
        --delta-TE*)
            shift
            export delta_TE=`echo $1 | sed -e 's/^[^=]*=//g'`
            shift
            ;;
        --subject*)
            shift
            if test $# -gt -0; then
                export subject=$1
            else
                echo "No subject ID specified (sub-******)"
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
        --func-name)
            shift
			if test $# -gt 0; then
				export func_name=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify session number"
			fi
			shift
			;;
        --func-name-2*)
            shift
			if test $# -gt 0; then
				export func_name_2=`echo $1 | sed -e 's/^[^=]*=//g'`
			fi
			shift
			;;
        --n-vols*)
            shift
			if test $# -gt 0; then
				export ndvols=`echo $1 | sed -e 's/^[^=]*=//g'`
			else
				echo "Need to specify subject number (sub-******)"
			fi
			shift
			;;
        ## if anything else: break and echo invalid input
        *)
            echo "invalid input"
            exit 0
            ;;
    esac
done

exec > >(tee "Logs/${subject}/1.5_funcdistortioncorr_log.txt") 2>&1
set -x 

## Set variables to "false" that have not been passed as flags
if [ -z $prepare_fieldmap ]; then prepare_fieldmap=false; fi
if [ -z $topup ]; then topup=false; fi
if [ -z $omni ]; then omni=false; fi
if [ -z $fugue ]; then fugue=false; fi
if [ -z $program ]; then program=afni; fi


## Change flag from one or the other to --topup, --fugue, --omni (so we can run it at the same time in the same run)
## If pass none of them, skip this step
## Section of the code to check if necessary input, if not, exit

## Setting up common directories
fieldmap_dir=${base_directory}/${subject}/${session}/fmap
anat_dir=${base_directory}/${subject}/${session}/anat
func_dir=${base_directory}/${subject}/${session}
fugue_dir=${base_directory}/${subject}/${session}/func_fugue
topup_dir=${base_directory}/${subject}/${session}/func_topup
omni_dir=${base_directory}/${subject}/${session}/func_omni
no_dc_dir=${base_directory}/${subject}/${session}/func_no-dc

## IF RUNNING PREPARE FIELDMAP 

if [[ $prepare_fieldmap = "true" ]]; then
    if [[ "$mag_bet" = "true" ]]; then
        3dresample -prefix ${fieldmap_dir}/tmp_mask.nii.gz -input ${anat_dir}/mask/brain_fs_mask.nii.gz -master ${fieldmap_dir}/${mag_image}.nii.gz
        fslmaths ${fieldmap_dir}/${mag_image}.nii.gz -mas ${fieldmap_dir}/tmp_mask.nii.gz ${fieldmap_dir}/${mag_image}_brain.nii.gz
        rm ${fieldmap_dir}/tmp_mask.nii.gz
    else
        cp ${fieldmap_dir}/${mag_image}.nii.gz ${fieldmap_dir}/${mag_image}_brain.nii.gz 
    fi
    if [ "$convert_to_radians" = "true" ]; then
        fslmaths ${fieldmap_dir}/${phase_image}.nii.gz -mul 3.14159 -div 2048 ${fieldmap_dir}/${phase_image}_rads.nii.gz -odt float
    else
        cp ${fieldmap_dir}/${phase_image}.nii.gz ${fieldmap_dir}/${phase_image}_rads.nii.gz
    fi
    fsl_prepare_fieldmap SIEMENS ${fieldmap_dir}/${phase_image}_rads.nii.gz ${fieldmap_dir}/${mag_image}_brain.nii.gz ${fugue_dir}/${fieldmap_name}.nii.gz ${delta_TE} --nocheck
fi

## UNWARPING BASED ON DISTORTION CORRECTION
if [[ $fugue == "true" ]]; then
    # Make directory if it doesn't exist
    if [ ! -d $fugue_dir ]; then
        mkdir -p $fugue_dir
    fi
    ## need to run unwarping on the whole functional set 
    fugue -i ${func_dir}/func_minimal/ --dwell=${dwell_time} --loadfmap=${fugue_dir}/${fieldmap_name} -u ${fugue_dir}/example_func_bc_unwarped.nii.gz

    ## Prepare visual check images
    3dedge3 -input ${func_dir}/func_minimal/highres2examplefunc.nii.gz -prefix ${fugue_dir}/anat2func_edge.nii.gz
    overlay 1 1 ${fugue_dir}/example_func_bc_unwarped.nii.gz -a ${fugue_dir}/anat2func_edge.nii.gz 1 1 ${fugue_dir}/overlay.nii.gz
    slicer ${fugue_dir}/overlay -S 5 3000 ${fugue_dir}/anat2func_edge_vcheck.png
    slicer ${fugue_dir}/overlay -a ${fugue_dir}/anat2func_edge_vcheck_2.png
    rm ${fugue_dir}/overlay.nii.gz

elif [[ $omni == "true" ]]; then

    ./preprocessing/Omni/ccs_bids_1.5_synth_unwarp.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --program ${program}

elif [[ $topup == "true" ]]; then

    if [ ! -d ${topup_dir} ]; then
        mkdir -p ${topup_dir}
    fi

    ## Make the datain_params.txt file
    if [ -f ${topup_dir}/datain_param.txt ]; then
        rm ${topup_dir}/datain_param.txt
    fi
    touch ${topup_dir}/datain_param.txt
    if [[ $polarity_direction == 'x' ]]; then
        echo "1 0 0 ${dwell_time}" >> ${topup_dir}/datain_param.txt
        echo "-1 0 0 ${dwell_time}" >> ${topup_dir}/datain_param.txt
    elif [[ $polarity_direction == 'y' ]]; then
        echo "0 1 0 ${dwell_time}" >> ${topup_dir}/datain_param.txt
        echo "0 -1 0 ${dwell_time}" >> ${topup_dir}/datain_param.txt
    elif [[ $polarity_direction == 'z' ]]; then
        echo "0 0 1 ${dwell_time}" >> ${topup_dir}/datain_param.txt
        echo "0 0 -1 ${dwell_time}" >> ${topup_dir}/datain_param.txt
    fi

    ## Take one volume of each of the scans to make b0 images
    fslroi ${func_dir}/func_minimal/${func_name}_mc.nii.gz ${topup_dir}/b0_image_1.nii.gz 7 1
    fslroi ${func_dir}/func/${func_name_2}.nii.gz ${topup_dir}/b0_image_2.nii.gz 7 1
    ## Now merge them
    fslmerge -t ${topup_dir}/b0_images.nii.gz ${topup_dir}/b0_image_1.nii.gz ${topup_dir}/b0_image_2.nii.gz

    ## Now we can run topup
    topup --imain=${topup_dir}/b0_images.nii.gz --datain=${topup_dir}/datain_param.txt --out=${topup_dir}/topup_unwarping

    ## make sure the dimensions of the first and second image are the same
    nvols=`fslnvols ${func_dir}/func/${func_name_2}.nii.gz`
    TRstart=${ndvols}
    let "TRend = ${nvols} - 1"
    3dcalc -a ${func_dir}/func/${func_name_2}.nii.gz[${TRstart}..${TRend}] -expr 'a' -prefix ${topup_dir}/${func_name_2}_dr.nii.gz -datum float

    ## Then we apply topup
    applytopup --imain=${func_dir}/func_minimal/${func_name}_mc,${topup_dir}/${func_name_2}_dr --topup=${topup_dir}/topup_unwarping --datain=${topup_dir}/datain_param.txt --inindex=1,2 --out=${topup_dir}/${func_name}_unwarped.nii.gz

    fslroi ${topup_dir}/${func_name}_unwarped.nii.gz ${topup_dir}/example_func_unwarped.nii.gz 7 1
    fslmaths ${topup_dir}/example_func_unwarped.nii.gz -mas ${func_dir}/func_minimal/example_func_mask.nii.gz ${func_dir}/func_minimal/example_func_unwarped_brain.nii.gz

    cp ${topup_dir}/${func_name}_unwarped.nii.gz ${func_dir}/func_minimal/.

## Need to have a nondc distortion correction step as well
elif [[ $no_dc == "true" ]]; then

    if [ ! -d ${no_dc_dir} ]; then
        mkdir ${no_dc_dir}
    fi

fi


    
    