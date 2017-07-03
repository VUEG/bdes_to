#!/bin/sh
zig4 -l03_abf_esc/03_abf_esc_out/03_abf_esc.rank_expanded.compressed.tif 09_prl_esc_bio/09_prl_esc_bio.dat 09_prl_esc_bio/09_prl_esc_bio.spp 09_prl_esc_bio/09_prl_esc_bio_out/09_prl_esc_bio.txt 0 0 1 0 --grid-output-formats=compressed-tif --image-output-formats=png
