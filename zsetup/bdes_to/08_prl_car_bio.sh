#!/bin/sh
zig4 -l02_abf_car/02_abf_car_out/02_abf_car.rank_expanded.compressed.tif 08_prl_car_bio/08_prl_car_bio.dat 08_prl_car_bio/08_prl_car_bio.spp 08_prl_car_bio/08_prl_car_bio_out/08_prl_car_bio.txt 0 0 1 0 --grid-output-formats=compressed-tif --image-output-formats=png
