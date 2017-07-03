#!/bin/sh
zig4 -l04_abf_esf/04_abf_esf_out/04_abf_esf.rank_expanded.compressed.tif 10_prl_esf_bio/10_prl_esf_bio.dat 10_prl_esf_bio/10_prl_esf_bio.spp 10_prl_esf_bio/10_prl_esf_bio_out/10_prl_esf_bio.txt 0 0 1 0 --grid-output-formats=compressed-tif --image-output-formats=png
