## Zonation setups


### Variants

| id | name           | description                 | n_features |
|----|----------------|-----------------------------|------------|
| 1  | 01_abf_bio     | Biodiversity                | 763        |
| 2  | 02_abf_car     | Carbon                      | 1          |
| 3  | 03_abf_esc     | ESs capacity                | 7          |
| 4  | 04_abf_esf     | ESs flow                    | 39599      |
| 5  | 05_abf_bio_car | Biodiversity + carbon       | 764        |
| 6  | 06_abf_bio_esc | Biodiversity + ESs capacity | 770        |
| 7  | 07_abf_bio_esf | Biodiversity + ESs flow     | 40362      |

### Pre-load variants

These variants look the performance of prioritization solution from 02-07 only from BD's perspective, i.e. cell-removal order is preloaded from 02-07 and features from 01. 

| id  | name              | description                              | n_features |
|-----|-------------------|------------------------------------------|------------|
| 8   | 08_prl_car_bio    | Pre-load carbon, BD features             | 763        |
| 9   | 09_prl_esc_bio    | Pre-load ESs capactiy, BD features       | 763        |
| 10  | 10_prl_esf_bio    | Pre-load ESs flowzones, BD features      | 763        |
| 11  | 11_prl_biocar_bio | Pre-load BD & carbon, BD features        | 763        |
| 12  | 12_prl_bioesc_bio | Pre-load BD & ESs capacity, BD features  | 763        |
| 13  | 13_abf_bioesf_esc | Pre-load BD & ESs flowzones, BD features | 763        |

### Weights

TBA