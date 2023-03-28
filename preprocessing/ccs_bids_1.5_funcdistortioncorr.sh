#!/usr/bin/env bash
## File takes in func directory, functional data, fieldmap data (if any), and distortion correction type
## Need to have 3 types of distortion correction, usage dictated by input parameter
## IFS:
## If fsl_prepare_fieldmap, need to know if its already in radians

## set default values if not supplied
delta_TE=2.46

## Put in flag architecture

exec > >(tee "Logs/${subject}/1.5_funcdistortioncorr_log.txt") 2>&1
set -x 

while test $# -gt 0; do 
    case "$1" in
        -d)
            shift
            if test $# -gt 0; then
                export base_directory=$1
            else
                echo "No base directory specified (path/to/subject_folder)"
                exit 1
            fi
            shift
            ;;
        --distortion-type*)
            shift
            export dist_corr_type=`echo $1 | sed -e 's/^[^=]*=//g'`
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

## Setting up common directories
fieldmap_dir=${base_directory}/${subject}/${session}/fmap
anat_dir=${base_directory}/${subject}/${session}/anat
func_dir=${base_directory}/${subject}/${session}/func

## IF RUNNING PREPARE FIELDMAP 

if [ $prepare_fieldmap = "true" ]; then
    if [ "$mag_bet" = "true" ]; then
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
    fsl_prepare_fieldmap SIEMENS ${fieldmap_dir}/${phase_image}_rads.nii.gz ${fieldmap_dir}/${mag_image}_brain.nii.gz ${func_dir}/fmap_diss_corr/${fieldmap_name}.nii.gz ${delta_TE} --nocheck
fi

## UNWARPING BASED ON DISTORTION CORRECTION
if [[ $dist_corr_type == "fugue" ]]; then
    ## need to run unwarping on the whole functional set 
    fugue -i ${func_dir}/func_minimal/ --dwell=${dwell_time} --loadfmap=${func_dir}/fmap_diss_corr/${fieldmap_name} -u ${func_dir}/fmap_diss_corr/example_func_bc_unwarped.nii.gz

    ## Prepare visual check images
    3dedge3 -input ${func_dir}/func_minimal/highres2examplefunc.nii.gz -prefix ${func_dir}/fmap_diss_corr/anat2func_edge.nii.gz
    overlay 1 1 ${func_dir}/fmap_diss_corr/example_func_bc_unwarped.nii.gz -a ${func_dir}/fmap_diss_corr/anat2func_edge.nii.gz 1 1 ${func_dir}/fmap_diss_corr/overlay.nii.gz
    slicer ${func_dir}/fmap_diss_corr/overlay -S 5 3000 ${func_dir}/fmap_diss_corr/anat2func_edge_vcheck.png
    slicer ${func_dir}/fmap_diss_corr/overlay -a ${func_dir}/fmap_diss_corr/anat2func_edge_vcheck_2.png
    rm ${func_dir}/fmap_diss_corr/overlay.nii.gz

elif [[ $dist_corr_type == "omni" ]]; then

    ./preprocessing/Omni/ccs_bids_1.5_synth_unwarp.sh -d ${base_directory} --subject ${subject} --session ${session} --run ${run} --func-name ${func_name} --program afni

elif [[ $dist_corr_type == "topup" ]]; then

    if [ ! -d ${func_dir}/topup_diss_corr ]; then
        mkdir ${func_dir}/topup_diss_corr
    fi

    ## Make the datain_params.txt file
    rm ${func_dir}/topup_diss_corr/datain_param.txt
    touch ${func_dir}/topup_diss_corr/datain_param.txt
    if [ $polarity_direction == 'x' ]; then
        echo "1 0 0 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
        echo "-1 0 0 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
    elif [ $polarity_direction == 'y' ]; then
        echo "0 1 0 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
        echo "0 -1 0 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
    elif [ $polarity_direction == 'z' ]; then
        echo "0 0 1 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
        echo "0 0 -1 ${dwell_time}" >> ${func_dir}/topup_diss_corr/datain_param.txt
    fi

    ## Take one volume of each of the scans to make b0 images
    fslroi ${func_dir}/func_minimal/${func_name}_mc.nii.gz ${func_dir}/topup_diss_corr/b0_image_1.nii.gz 7 1
    fslroi ${func_dir}/${func_name_2}.nii.gz ${func_dir}/topup_diss_corr/b0_image_2.nii.gz 7 1
    ## Now merge them
    fslmerge -t ${func_dir}/topup_diss_corr/b0_images.nii.gz ${func_dir}/topup_diss_corr/b0_image_1.nii.gz ${func_dir}/topup_diss_corr/b0_image_2.nii.gz

    ## Now we can run topup
    topup --imain=${func_dir}/topup_diss_corr/b0_images.nii.gz --datain=${func_dir}/topup_diss_corr/datain_param.txt --out=${func_dir}/topup_diss_corr/topup_unwarping

    ## make sure the dimensions of the first and second image are the same
    nvols=`fslnvols ${func_dir}/${func_name_2}.nii.gz`
    TRstart=${ndvols}
    let "TRend = ${nvols} - 1"
    3dcalc -a ${func_dir}/${func_name_2}.nii.gz[${TRstart}..${TRend}] -expr 'a' -prefix ${func_dir}/topup_diss_corr/${func_name_2}_dr.nii.gz -datum float

    ## Then we apply topup
    applytopup --imain=${func_dir}/func_minimal/${func_name}_mc,${func_dir}/topup_diss_corr/${func_name_2}_dr --topup=${func_dir}/topup_diss_corr/topup_unwarping --datain=${func_dir}/topup_diss_corr/datain_param.txt --inindex=1,2 --out=${func_dir}/topup_diss_corr/${func_name}_unwarped.nii.gz

    fslroi ${func_dir}/topup_diss_corr/${func_name}_unwarped.nii.gz ${func_dir}/topup_diss_corr/example_func_unwarped.nii.gz 7 1
    fslmaths ${func_dir}/topup_diss_corr/example_func_unwarped.nii.gz -mas ${func_dir}/func_minimal/example_func_mask.nii.gz ${func_dir}/func_minimal/example_func_unwarped_brain.nii.gz

    cp ${func_dir}/topup_diss_corr/${func_name}_unwarped.nii.gz ${func_dir}/func_minimal/.
    

fi


    
    