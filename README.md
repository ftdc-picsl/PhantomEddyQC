# PhantomEddyQC
Script to check a phantom scan for eddy distortions affecting the b=0 volumes

## System requirements

* FSL (select_dwi_vol)
* ANTs
* R (with the following packages: ggplot2, dplyr, tidyr)

## Usage

```
  ./phantom_b0_slice_distortion.sh dwi.nii.gz dwi.bval b0_stats
```

## Method

A series of slices in the middle of the phantom are extracted for all b=0 volumes in the
data. The first one, b0_1, is the reference. The second one, b0_2 follows immediately and
serves as a reference. The remaining b=0 volumes follow b>0 volumes.

Each slice from each b=0 volume is registered to the same slice in the first b=0 volume.

The Jacobian determinant of the transformation is calculated for each slice and each b=0
volume, within a mask around the edges of the phantom.


## Output

jacobian.csv: Jacobian values for each slice (rows) and each b=0 volume (columns)
registered to the first b=0.

jacobian_qc_plot.pdf: Plot of the Jacobian values for each slice and b=0 volume.

qc_score.tst: A summary score = median(jacobian of b0_[3,...,N]) / median(jacobian of
b0_2).
