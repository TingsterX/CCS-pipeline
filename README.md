# Connectome Computation System (CCS)

Connectome Computation System (CCS) is designed for Discovery Science of the human brain from Lab For Functional Connectome and Development (LFCD). **Source version** of the CCS pipeline is on Github: https://github.com/zuoxinian/CCS. 

This repo includes **custimized versions** for different data.


If you use or are inspired by CCS, please credit it both the github link and the two key references:

1. Ting Xu, Zhi Yang, Lili Jiang, Xiu-Xia Xing, Xi-Nian Zuo (2015) [A Connectome Computation System for discovery science of brain](https://github.com/zuoxinian/CCS/blob/master/manual/ccs.paper.pdf). *Science Bulletin*, 60(1): 86-95.
2. Xia-Xiu Xing, Ting Xu, Chao Jiang, Yin-Shan Wang, Xi-Nian Zuo (2022) [Connectome Computation System: 2015–2021 updates](https://github.com/zuoxinian/CCS/blob/master/manual/ccs.updates.2015-2021.pdf). *Science Bulletin*, 67(5): 448-451.


## data structure



```
anat_dir_name=anat # or anat_dir_name=ses-001/anat
anat_dir=${base_directory}/${subject}/${anat_dir_name}
SUBJECTS_DIR=${anat_dir}
```

anat preprocessed data structure
```
subject                                 # FS folder
    |-mri 
        |-rawavg.mgz                    # rawavg T1w space in mgz format
        |-xfm_fs_To_rawavg.FSL.mat      # transformation FS to raw space - FSL format
        |-xfm_fs_To_rawavg.reg          # transformation FS to raw space - FS format

anat
    |-T1w_?.nii.gz                      # (symbolic link or source file)
    |-T1w_?_denoise.nii.gz      
    |-T1w.nii.gz                        # averaged T1 if multiple T1 files
    |-T1w_bc.nii.gz                     # averaged T1 + N4
    |-mask
        |-T1.nii.gz                     # averaged T1 (FS intensity corrected) in original space
        |-brain_mask_init.nii.gz        # symbolic link to prior (if it exits) or FS result

        |-brain_mask_fs.nii.gz          # brain mask - FS pipeline
        |-brain_mask_fsl_tight.nii.gz   # brain mask - FSL tight pipeline (bigger mask)
        |-brain_mask_fsl_loose.nii.gz   # brain mask - FSL loose pipeline (smaller mask)
        |-brain_mask_fs+.nii.gz         # brain mask - FS + FSL tight pipeline
        |-brain_mask_fs-.nii.gz         # brain mask - FS * FSL loose pipeline
        

        |-brain_fs.nii.gz               # brain - FS pipeline
        |-brain_fs+.nii.gz              # brain - FSL + BET tight pipeline
        |-brain_fs-.nii.gz              # brain - FSL * BET loose pipeline

        |-brain_prior.nii.gz
        |-xfm_prior_mask_To_T1.mat      # linear (dof=6) prior space to T1 orig space
        |-xfm_T1_To_prior_mask.mat      # linear (dof=6) T1 orig space to prior space

        |-FS                            # FS recon-all for the brain mask
            |-mri
                |-brainmask.mgz 
    
    |-reg
        |-T1w_?_-iscale.txt             # iscaleout from averaging step
        |-T1w_?.lta                     # transformation from averaging step
        



```