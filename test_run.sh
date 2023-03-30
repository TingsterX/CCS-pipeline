#!/usr/bin/env bash

## Test running the whole pipeline for one subject
./ccs_preproc_bids_docker.sh -d /home/salldritt/projects/Func_Pipeline/CCS-pipeline/Data/site-ucdavis --subject sub-032127 --session ses-001 --run run-1 --num-runs 1 --func-name sub-032127_ses-001_task-resting_run-1_bold --func-name-2 sub-032127_ses-001_task-resting_acq-RevPol_run-1_bold --drop-vols 5 --mask /home/salldritt/projects/Func_Pipeline/CCS-pipeline/Data/site-ucdavis/sub-032127/ses-001/anat/sub-032127_ses-001_run-1_T1w_mask --distortion-correction omni