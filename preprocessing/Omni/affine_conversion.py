## Function to convert transformation affine between .mat and .aff12.1D format
## Usage: affine_conversion.py -i <.mat/.aff12.1D> -f <AFNI/FSL> -o <output>
## Specifying <FSL> or <AFNI> as the second argument tells the program to convert input affine to this format
## Sam Alldritt

import numpy as np
import argparse
import os, sys

parser=argparse.ArgumentParser(description='Converting affine transform to FSL or AFNI format', formatter_class=argparse.ArgumentDefaultsHelpFormatter)
required=parser.add_argument_group('Required arguments')
required.add_argument('-i', '--in_affine', required=True, type=str, help='Path of the affine transform')
required.add_argument('-f', '--output_format', required=True, type=str, help='Final format')
required.add_argument('-o', '--output', required=True, type=str, help='Path of the output transform')

args = parser.parse_args()
args = vars(args)

input_affine = args['in_affine']
final_format = args['output_format']
output_dir = args['output']

#temp_mat = '/home/salldritt/projects/Omni/DCAN_omni_implementation/INPUT/site-uwmadison/sub-2353/ses-None/files/Synth-Unwarp/T1_to_epi.mat'
#temp_output = '/home/salldritt/projects/Omni/DCAN_omni_implementation/INPUT/site-uwmadison/sub-2353/ses-None/files/Synth-Unwarp/T1_to_epi.aff12.1D'

def one_d_to_mat(one_d_filename):
    """Convert a .1D file to a .mat directory
    Parameters
    ----------
    one_d_filename : str
        The filename of the .1D file to convert
    Returns
    -------
    mat_filenames : list of str
        The of paths in the .mat directory created
    """
    mat_dirname = one_d_filename.replace('.aff12.1D', '.mat')
    with open(one_d_filename, 'r') as one_d_file:
        rows = [np.reshape(row, (4, 4)).astype('float') for row in [[
            term.strip() for term in row.split(' ') if term.strip()
        ] + [0, 0, 0, 1] for row in [
            line.strip() for line in one_d_file.readlines() if
            not line.startswith('#')]]]
    try:
        os.mkdir(mat_dirname)
    except FileExistsError:
        pass
    for i, row in enumerate(rows):
        np.savetxt(os.path.join(mat_dirname, f'MAT_{i:04}'),
                   row, fmt='%.5f', delimiter=' ')
        mat_filenames = [os.path.join(mat_dirname, filename) for
            filename in os.listdir(mat_dirname)]
        mat_filenames.sort()
    return mat_filenames

def mat_to_one_d(mat_filename, output_filename):
    """Convert a .mat file to a .1D file
    Parameters
    ----------
    mat : str
        The filename of the .mat file to convert
    Returns
    -------
    1D_filenames : list of str
        The of paths in the .1D directory created
    """
    afni_filename = mat_filename.replace('.mat', '.aff12.1D')
    print(afni_filename)
    with open(mat_filename, 'r') as mat_file:
        rows = np.asarray([row.split() for row in [line.strip() for line in mat_file.readlines()]])
        rows = np.delete(rows, 3, 0)
        rows = np.reshape(rows, (1, 12))
        rows = np.squeeze(rows)
    with open(output_filename, 'w') as output:
        first_string = '# 3d Allineate matrices (DICOM-to-DICOM, row-by-row):'
        output.write(first_string + '\n')
        for row in rows:
            output.write('\t' + row)    

if final_format == 'FSL':
    mat_to_one_d(input_affine, output_dir)
elif final_format == 'AFNI':
    mat_filenames = one_d_to_mat(input_affine)
    print("AFNI format not completed yet")
else:
    print("Choose 'FSL' or 'AFNI' for -f flag")

