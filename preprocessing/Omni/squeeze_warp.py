#!/usr/bin/env python
## Reads in Synth-Unwarp warp file output and squeezes out the 5th dimension to make it a 4 dimensional image
## Should output a 4d image with 3 volumes
## Usage: squeeze_warp.py <input> <output>
## Sam Alldritt

import nibabel as nib
import numpy as np
import sys

path_to_image = sys.argv[1]
output_dir = sys.argv[2]

image = nib.load(path_to_image)
image_data = image.get_fdata()
image_data = np.squeeze(image_data)
image_header = image.header
temp = image_header['dim'][4]
image_header['dim'][4] = image_header['dim'][5]
image_header['dim'][5] = temp

new_img = nib.Nifti1Image(image_data, image.affine, image_header)
nib.save(new_img, output_dir)

