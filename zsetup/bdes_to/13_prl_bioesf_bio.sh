#!/bin/sh
zig4 -l07_abf_bio_esf/07_abf_bio_esf_out/07_abf_bio_esf.rank_expanded.compressed.tif 13_prl_bioesf_bio/13_prl_bioesf_bio.dat 13_prl_bioesf_bio/13_prl_bioesf_bio.spp 13_prl_bioesf_bio/13_prl_bioesf_bio_out/13_prl_bioesf_bio.txt 0 0 1 0 --grid-output-formats=compressed-tif --image-output-formats=png
