#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Utility functions for spatial processing."""
import click
import functools
import glob
import logging
import multiprocessing
import os
import sys
import time
from subprocess import call


def timing(f):
    def wrap(*args, **kwargs):
        time1 = time.time()
        ret = f(*args, **kwargs)
        time2 = time.time()
        print('{} function took {} ms'.format(f.__name__,
                                              (time2 - time1) * 1000.0))
        return ret
    return wrap


def parse_nodata(dtype):
    """
    """

    dtype_nodata = {
        'Byte': 0,
        'Uint8': 0,
        'Int16': -32768,
        'Uint16': 0,
        'Int32': -2147483648,
        'Uint32': 0,
        'Float32': -3.40282e+38
    }

    if dtype not in list(dtype_nodata.keys()):
        raise ValueError("Invalid dtype: {}".format(dtype))
    else:
        return dtype_nodata[dtype]


def warp_raster(srcraster, outdir, dtype, verbose=False):
    """
    """
    logger = multiprocessing.get_logger()

    dst_raster = os.path.join(outdir, os.path.basename(srcraster))
    dst_vrt_raster = dst_raster.replace(".tif", ".vrt")

    if dtype == "Float32":
        trsl_raster = dst_raster.split(".")[0] + "_tmp.tif"
    else:
        trsl_raster = dst_raster

    logger.info('Warping {} into {}'.format(srcraster, dst_raster))

    nodata_value = parse_nodata(dtype)

    cmd_warp = ["gdalwarp", "-of", "vrt", srcraster, dst_vrt_raster,
                "-te", "2000000.0 ", "1000000.0", "6526000.0", "5410000.0",
                "-multi", "-ot", dtype, "-dstnodata", str(nodata_value)]
    cmd_trsl = ["gdal_translate", "-co", "COMPRESS=DEFLATE",
                "-a_nodata", str(nodata_value), "-a_srs", "EPSG:3035",
                "-ot", dtype, dst_vrt_raster, trsl_raster]

    warp_res = call(cmd_warp, shell=False)
    trsl_res = call(cmd_trsl, shell=False)

    # Float32 rasters need additional processing to correct the NoData value.
    if dtype == "Float32":
        cmd_calc = ['rio', 'calc', '(where (== (take a 1) 0) -3.40282e+38 a)',
                    '--name', 'a={}'.format(trsl_raster),
                    '--co', 'compress=DEFLATE', dst_raster]
        print(cmd_calc)
        calc_res = call(cmd_calc, shell=False)
        os.remove(trsl_raster)

    os.remove(dst_vrt_raster)

    return (warp_res, trsl_res)


@timing
def multi_warp(indir, outdir, cpus, dtype, logger=None, verbose=False):
    """
    """

    if logger is None:
        logger = logging.basicConfig()

    # List rasters in indir
    src_rasters = glob.glob(indir + os.path.sep + "*.tif")

    logger.info('Warping {} rasters'.format(len(src_rasters)))

    # Set up the worker pool
    pool = multiprocessing.Pool(processes=cpus)
    # Multitprocessing map only takes 1 argument, so we have to use
    # partials
    pool.map(functools.partial(warp_raster, dtype=dtype, outdir=outdir),
             src_rasters)
    return(True)


@click.command()
@click.option('-v', '--verbose', is_flag=True)
@click.argument('indir', nargs=1, type=click.Path(exists=True))
@click.argument('outdir', nargs=1)
@click.option('-d', '--dtype', type=str, default="float32")
@click.option('-c', '--cpus', type=int, default=1)
def cli(indir, outdir, dtype, cpus, verbose):
    """ Command-line interface."""

    if verbose:
        multiprocessing.log_to_stderr(logging.DEBUG)
    else:
        multiprocessing.log_to_stderr(logging.INFO)
    logger = multiprocessing.get_logger()

    # Create dir if it doesn not exist
    if not os.path.exists(outdir):
        os.mkdir(outdir)

    if cpus is None:
        # Default to 1
        cpus = 1
    else:
        cpus = int(cpus)

    available_cpus = multiprocessing.cpu_count()
    if cpus > available_cpus:
        logger.warning(('Assigning more jobs ({}) than '.format(cpus) +
                        'available CPUs ({1})'.format(available_cpus)))

    assert cpus > 0, 'ERROR: number of jobs must be a positive integer'

    success = multi_warp(indir=indir, outdir=outdir,  dtype=dtype, cpus=cpus,
                         logger=logger, verbose=verbose)
    if success:
        return(0)
    else:
        return(-1)


if __name__ == '__main__':
    sys.exit(cli())
