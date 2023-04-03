#!/usr/bin/env python
## Needs to read the parameters file output from MCFlirt and choose the lowest sum of the parameters to use as a reference EPI
## Returns the index of the volume needed
## Sam Alldritt

import numpy as np
import sys

parameters_file = sys.argv[1]

## Reads the file and stores it as a (<VOLS>, 6) numpy array
f = open(parameters_file, 'r')
matrix = []
index = 0                   ## want to skip the first 5 lines, as those are the volumes we will be skipping
for line in f:
    if index < 5:
        index += 1
        continue
    line = line.strip()
    line = line.split()
    row = []
    line_index = 0
    for num in line:
        ## convert radians to degrees for rotation parameters 
        if line_index < 3:                  
            num = float(num) * (180/np.pi)
        row.append(float(num))
    matrix.append(row)

matrix = np.array(matrix)
sum_array = np.sum(matrix, axis=1)
min_index = np.argmin(sum_array)
print(min_index)
    

