#!/bin/bash

# Script to calculate the distortion of a phantom b0 image in 2D over a series of slices

# Assumptions
# 1. Phase encode P-A or A-P
# 2. Fixed threshold to separate phantom from background
# 3. First two volumes are consecutive b=0, which provide the reference distortion values

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <phantom_b0_image> <bvals> <output_root>

    Script to calculate the distortion of a phantom b0 image in 2D over a series
    Assumptions

      1. Phase encode P-A or A-P
      2. Fixed threshold to separate phantom from background
      3. First two volumes are consecutive b=0, which provide the reference distortion values

    Output is output_root_[suffixes]:

        1. _jacobian.csv: CSV file with the mean jacobian for each slice
        2. _jacobian_qc_plot.pdf: Plot of the jacobian values for each slice
        3. _qc_score.csv: CSV file with the QC score

      Requirements: FSL, ANTs, R

    "
    exit 1
fi

data=$1
bvals=$2
outputRoot=$3

backgroundThreshold=250

if [[ ! $TMPDIR ]]; then
    tmpDir=$(mktemp -p /tmp -d phantom_b0.XXXXXX.tmpdir)
else
    tmpDir=$(mktemp -p $TMPDIR -d phantom_b0.XXXXXX.tmpdir)
fi

echo "Writing temporary files to $tmpDir"

# Extract all b0 volumes
select_dwi_vols $data $bvals ${tmpDir}/all_b0.nii.gz 0

ImageMath 4 ${tmpDir}/b0_vol_.nii.gz TimeSeriesDisassemble ${tmpDir}/all_b0.nii.gz

b0_vols=($(ls ${tmpDir}/b0_vol_10*.nii.gz))

numVols=${#b0_vols[@]}


# Take a series of slices from the middle to compare
minSlice=32
maxSlice=48

# Use reference to define a mask
ThresholdImage 3 ${b0_vols[0]} ${tmpDir}/ref_mask.nii.gz $backgroundThreshold Inf

# Make a donut mask, take the center out where the deformations are noisy
ImageMath 3 ${tmpDir}/ref_mask_dilate.nii.gz MD ${tmpDir}/ref_mask.nii.gz 2
ImageMath 3 ${tmpDir}/ref_mask_erode.nii.gz ME ${tmpDir}/ref_mask.nii.gz 10

jacobianMask=${tmpDir}/jacobian_mask.nii.gz

ImageMath 3 $jacobianMask - ${tmpDir}/ref_mask_dilate.nii.gz ${tmpDir}/ref_mask_erode.nii.gz

# Get mask for each slice
for ((slice=$minSlice; slice < $maxSlice; slice++)) {
    ExtractSliceFromImage 3 ${jacobianMask} ${tmpDir}/jacobian_mask_slice_${slice}.nii.gz 2 $slice 0
}

# Get slices from each volume
echo "Extracting slices in range $minSlice to $maxSlice"
for ((i=0; i < $numVols; i++)) {
    b0=${b0_vols[$i]}

    for ((slice=$minSlice; slice < $maxSlice; slice++)) {
        ExtractSliceFromImage 3 $b0 ${tmpDir}/b0_vol_${i}_slice_${slice}.nii.gz 2 $slice 0
        DenoiseImage -d 2 -p 2x2 -r 4x4 -i ${tmpDir}/b0_vol_${i}_slice_${slice}.nii.gz -o ${tmpDir}/b0_vol_${i}_slice_${slice}.nii.gz
    }
}

# Register each slice to the reference slice
echo "Registering slices to reference"
for ((i=1; i < $numVols; i++)) {
    for ((slice=$minSlice; slice < $maxSlice; slice++)) {
        fixed=${tmpDir}/b0_vol_0_slice_${slice}.nii.gz
        moving=${tmpDir}/b0_vol_${i}_slice_${slice}.nii.gz

        antsRegistration -d 2 \
          -t SyN[0.2,3,1] -f 1x1 -s 1x0.5vox -m CC[ ${fixed}, ${moving}, 1, 5 ] -c 10x10 \
          -o ${tmpDir}/vol_${i}_to_ref_slice_${slice}_

        CreateJacobianDeterminantImage 2 ${tmpDir}/vol_${i}_to_ref_slice_${slice}_0Warp.nii.gz \
          ${tmpDir}/vol_${i}_to_ref_slice_${slice}_logjacobian.nii.gz 1

        # We want the absolute value of the jacobian
        ImageMath 2 ${tmpDir}/vol_${i}_to_ref_slice_${slice}_logjacobian.nii.gz abs \
          ${tmpDir}/vol_${i}_to_ref_slice_${slice}_logjacobian.nii.gz
    }
}

# Calculate the mean jacobian for each slice, and output
header="Slice"

for ((i=1; i < $numVols; i++)) {
    header="${header},LogJacobian${i}"
}

echo $header > ${outputRoot}_jacobian.csv

echo "Calculating stats"
for ((slice=$minSlice; slice < $maxSlice; slice++)) {
    line="${slice}"
    for ((i=1; i < $numVols; i++)) {
        mean=$(fslstats ${tmpDir}/vol_${i}_to_ref_slice_${slice}_logjacobian.nii.gz -k ${tmpDir}/jacobian_mask_slice_${slice}.nii.gz -m)
        # trim whitespace
        mean=$(echo $mean | tr -d ' ')
        line="${line},${mean}"
    }
    echo $line >> ${outputRoot}_jacobian.csv
}

# Call the R script to generate the QC plot
Rscript $(dirname $0)/phantom_b0_jacobian_analysis.R \
  ${outputRoot}_jacobian.csv \
  ${outputRoot}_jacobian_qc_plot.pdf \
  ${outputRoot}_qc_score.txt

rm ${tmpDir}/*
rmdir ${tmpDir}