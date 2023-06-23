#!/bin/bash
############################################################
## Utilities functions
## Custimized from micapipe (https://github.com/MICA-MNI/micapipe)
############################################################
export Version="v0.1 'pathfinder'"

############################################################
#-------------- FUNCTION: PRINT ERROR & Note --------------#
# The following functions are only to print on the terminal colorful messages:
# This is optional on the pipelines
#     Error messages
#     Warning messages
#     Note messages
#     Warn messages
#     Title messages
Error() {
echo -e "\033[38;5;9m\n-------------------------------------------------------------\n\n[ ERROR ]..... $1\n
-------------------------------------------------------------\033[0m\n"
}
Note(){
# Ting: replaced color \033[38;5;197m to \033[38;5;122m
if [[ ${quiet} != TRUE ]]; then echo -e "\t$1\t\033[38;5;122m$2\033[0m"; fi
}
Info() {
Col="38;5;75m" # Color code
if [[ ${quiet} != TRUE ]]; then echo  -e "\033[$Col\n[ INFO ]..... $1 \033[0m"; fi
}
Warning() {
Col="38;5;184m" # Color code
if [[ ${quiet} != TRUE ]]; then echo  -e "\033[$Col\n[ WARNING ]..... $1 \033[0m"; fi
}
Title() {
Col="38;5;42m" # Color code
if [[ ${quiet} != TRUE ]]; then echo -e "\n\033[$Col
-------------------------------------------------------------
\t$1
-------------------------------------------------------------\033[0m"; fi
}

#---------------- FUNCTION: PRINT COLOR COMMAND ----------------#
function Do_cmd() {
# do_cmd sends command to stdout before executing it.
str="$(whoami) @ $(uname -n) $(date)"
local l_command=""
local l_sep=" "
local l_index=1
while [ ${l_index} -le $# ]; do
    eval arg=\${$l_index}
    if [ "$arg" = "-fake" ]; then
      arg=""
    fi
    if [ "$arg" = "-no_stderr" ]; then
      arg=""
    fi
    if [ "$arg" == "-log" ]; then
      nextarg=$(("${l_index}" + 1))
      eval logfile=\${"${nextarg}"}
      arg=""
      l_index=$[${l_index}+1]
    fi
    l_command="${l_command}${l_sep}${arg}"
    l_sep=" "
    l_index=$[${l_index}+1]
   done
if [[ ${quiet} != TRUE ]]; then echo -e "\033[38;5;118m\n${str}:\nCOMMAND -->  \033[38;5;122m${l_command}  \033[0m"; fi
if [ -z "$TEST" ]; then $l_command; fi
}

# vcheck image for registration
function vcheck_mask() {
	underlay=$1
	overlay=$2
	figout=$3
	echo "-->> vcheck mask "
  wk_dir=$(dirname ${figout})/_tmp_$(basename ${figout})
  mkdir -p ${wk_dir}
	overlay 1 1 ${underlay} -a ${overlay} 1 1 ${wk_dir}/tmp_rendered_mask.nii.gz
	slicer ${wk_dir}/tmp_rendered_mask.nii.gz -S 10 1200 ${figout}
	rm -f ${wk_dir}
}

function vcheck_acpc() {
	underlay=$1
	figout=$2
  title="ACPC alignment"
	echo "-->> vcheck acpc"
  wk_dir=$(dirname ${figout})/_tmp_$(basename ${figout})
  mkdir -p ${wk_dir}
  3dcalc -a ${underlay} -expr "step(x)+step(y)+step(z)" -prefix ${wk_dir}/tmp_acpc_mask_${underlay}.nii.gz
	overlay 1 1 ${underlay} -a ${wk_dir}/tmp_acpc_mask_${underlay}.nii.gz 1 4 ${wk_dir}/tmp_rendered_mask.nii.gz
	slicer ${wk_dir}/tmp_rendered_mask.nii.gz -a ${figout} -L
	rm -f ${wk_dir}
}

function vcheck_reg() {
  underlay=$1
  edge_image=$2
  figout=$3
  echo "-->> vcheck registration "
  wk_dir=$(dirname ${figout})/_tmp_$(basename ${figout})
  mkdir -p ${wk_dir}
  pushd $(dirname ${figout})/_tmp_$(basename ${figout})
  rm -f tmp_edge.nii.gz
  3dedgedog -input ${edge_image} -prefix tmp_edge.nii.gz
  overlay 1 1 ${underlay} -a tmp_edge.nii.gz 1 1 tmp_rendered.nii.gz
  slicer tmp_rendered -s 2 \
    -x 0.30 sla.png -x 0.45 slb.png -x 0.50 slc.png -x 0.55 sld.png -x 0.70 sle.png \
    -y 0.30 slg.png -y 0.40 slh.png -y 0.50 sli.png -y 0.60 slj.png -y 0.70 slk.png \
    -z 0.30 slm.png -z 0.40 sln.png -z 0.50 slo.png -z 0.60 slp.png -z 0.70 slq.png  
  pngappend sla.png + slb.png + slc.png + sld.png  + sle.png render_vcheck1.png 
  pngappend slg.png + slh.png + sli.png + slj.png  + slk.png render_vcheck2.png
  pngappend slm.png + sln.png + slo.png + slp.png  + slq.png render_vcheck3.png
  pngappend render_vcheck1.png - render_vcheck2.png - render_vcheck3.png ${figout}
  popd
  rm -r ${wk_dir}
}
