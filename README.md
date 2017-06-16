[![Snakemake](https://img.shields.io/badge/snakemake-≥3.13.0-brightgreen.svg?style=flat-square)](http://snakemake.bitbucket.org)

## Trade-offs between biodiversity and ecosystem services in Europe

__Version:__ 0.1.0  

### Introduction

### Installation

The project relies both on Python and R scripts to pre- and post-procesing the data as well as running some of the analyses. While the project might run on Windows machines, it has never been tested on one. Your safest bet is running everything on a Ubuntu 14.04 (Trusty) machine. Everything else should run on other Linux distributions as well, but Zonation currently works nicely only Ubuntu 14.04 (though it is possible to compile it on 16.04 as well).

#### 1. Getting this project

You need to first have `git` installed on the system you want to run this project on. Install `git` by:

```
sudo apt-get install git
```

Next, get everything in this project using git:

```
git clone https://github.com/VUEG/bdes_to.git
```

#### 2. Installing necessary dependencies using conda

This project uses [conda](https://conda.io/docs/) package, dependency and environment management system for setting everything up. It comes with simple installer script `bootsrap_conda.sh` that will install the right version of `conda` command line program for you. To run it, type:

```
# Get into the project directory
cd bdes_to

# Install conda
./bootsrap_conda.sh
```

After installation is finished and assuming everythign went well, you create a new enviroment with all the necessary (Python and R) pacakages installed by doing the following (still in the same directory):

```
conda env create -n bdes_to
```

This command will create a new virtual environment called `bdes_to` and install all the dependencies listed in `environment.yml` in it. 

#### 2. Installing Zonation

[Zonation](https://github.com/cbig/zonation-core) is not yet available through conda, so you will have to install it separately and system-wide. Follow the installation instructions found [here](https://github.com/cbig/zig4-compilation-scripts). 

#### 3. Running the processing and analysis workflow

This project uses [snakemake](https://snakemake.readthedocs.io/en/stable/) workflow management system to run the different stages in sequence. It has already been installed in step 1. You can list all the individual snakemake rules (i.e. stages) by typing in:

```
snakemake -l
```

or run the whole sequence (not recommended as this will also run all the Zonation analyses) by:

```
snakemake
```

### Project organization


------------

    ├── LICENSE
    ├── environment.yml    <- Conda environment file
    ├── README.md          <- The top-level README for developers using this project.
    ├── data
    │   ├── external       <- Data from third party sources.
    │   ├── interim        <- Intermediate data that has been transformed.
    │   ├── processed      <- The final, canonical data sets for modeling.
    │
    ├── docs               <- A default Sphinx project; see sphinx-doc.org for details
    │
    ├── notebooks          <- Jupyter notebooks. Naming convention is a number (for ordering),
    │                         the creator's initials, and a short `-` delimited description, e.g.
    │                         `1.0-jqp-initial-data-exploration`.
    │
    ├── references         <- Data dictionaries, manuals, and all other explanatory materials.
    │
    ├── reports            <- Generated analysis as HTML, PDF, LaTeX, etc.
    │   └── figures        <- Generated graphics and figures to be used in reporting
    │
    ├── requirements.txt   <- The requirements file for reproducing the analysis environment, e.g.
    │                         generated with `pip freeze > requirements.txt`
    │
    ├── src                <- Source code for use in this project.
    │   ├── __init__.py    <- Makes src a Python module
    │   │
    │   ├── data           <- Scripts to download or generate data
    │   │   └── make_dataset.py
    │   │
    │   ├── features       <- Scripts to turn raw data into features for modeling
    │   │   └── build_features.py
    │   │
    │   ├── models         <- Scripts to train models and then use trained models to make
    │   │   │                 predictions
    │   │   ├── predict_model.py
    │   │   └── train_model.py
    │   │
    │   └── visualization  <- Scripts to create exploratory and results oriented visualizations
    │       └── visualize.py
    │
    └── tests              <- tests scripts


### License

See [LICENSE file](LICENSE.md).

### Contributors

+ Joona Lehtomäki <joona.lehtomaki@gmail.com>
