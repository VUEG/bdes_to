#!/bin/sh
zig4 -l05_abf_bio_car/05_abf_bio_car_out/05_abf_bio_car.rank_matched.compressed.tif 11_prl_biocar_bio/11_prl_biocar_bio.dat 11_prl_biocar_bio/11_prl_biocar_bio.spp 11_prl_biocar_bio/11_prl_biocar_bio_out/11_prl_biocar_bio.txt 0 0 1 0 --grid-output-formats=compressed-tif --image-output-formats=png
