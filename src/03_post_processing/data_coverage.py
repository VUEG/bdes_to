#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Functions and utilities for exploring and manipulating data coverages.

Module can be used alone or as part of Snakemake workflow.
"""
import logging
import numpy as np
import numpy.ma as ma
import rasterio

from timeit import default_timer as timer


def create_value_coverage(input_raster, output_raster, compress='DEFLATE',
                          verbose=False, logger=None):
    """ Create a binary raster based on informative cell values.

    All values that have information in input_raster are given value 1 in the
    output_raster.

    :param input_raster: String path to input raster.
    :param output_raster: String path to output raster.
    :param compress: String compression level used for the output raster.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: logger object to be used.
    :return Boolean success.
    """
    # 1. Setup  --------------------------------------------------------------

    all_start = timer()

    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('create_value_coverage')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    # 2. Read and process raster  ---------------------------------------------
    # Read raster bands directly to Numpy arrays.
    with rasterio.open(input_raster) as raster:
        llogger.info("Reading and processing raster {}".format(input_raster))
        input_nodata = raster.nodata
        # Read in the data
        src = raster.read(1, masked=True)
        mask = ma.getmask(src)
        llogger.debug("Number of informative cells: {}".format(np.sum(~mask)))
        # Binarize input where there are values
        np.place(src, mask == False, 1)

        profile = raster.profile
        profile.update(dtype=rasterio.uint8, count=1, compress=compress,
                       nodata=255)

        # Since we're saving a byte, replace old NoData value with 255
        np.place(src, src == input_nodata, 255)

        with rasterio.open(output_raster, 'w', **profile) as dst:
            llogger.info("Writing output raster {}".format(output_raster))
            dst.write_mask(mask)
            dst.write(src.astype(rasterio.uint8), 1)

    all_end = timer()
    all_elapsed = round(all_end - all_start, 2)
    llogger.info(" [TIME] Binarizing took {} sec".format(all_elapsed))


def expand_value_coverage(input_raster, expand_raster, output_raster,
                          union=False, compress='DEFLATE', verbose=False,
                          logger=None):
    """ Expand a raster based on occurrence of informative cells in another.

    Argument "intersect" can be used to define if only the mask of the
    expand raster should be used, or an union between masks of input and
    expand raster.

    :param input_raster: String path to input raster.
    :param expand_raster: String path to mask raster.
    :param output_raster: String path to output raster.
    :param union: Boolean should masks of input_raster and expand_raster
                  be unioned.
    :param compress: String compression level used for the output raster.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: logger object to be used.
    :return Boolean success.
    """
    # 1. Setup  --------------------------------------------------------------

    all_start = timer()

    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('maskvalue_coverage')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    # 2. Read and process raster  ---------------------------------------------

    # First, get the mask and dtype from the mask raster
    expand_raster = rasterio.open(expand_raster)
    expand_raster_src = expand_raster.read(1, masked=True)
    expand_mask = expand_raster_src.mask

    # Read raster bands directly to Numpy arrays.
    with rasterio.open(input_raster) as raster:
        llogger.info("Reading and processing raster {}".format(input_raster))
        input_nodata = raster.nodata

        # Read in the data
        src = raster.read(1, masked=True)
        src_dtype = src.dtype
        src_mask = src.mask

        # Perform a union on the masks if needed
        if union:
            llogger.info("[NOTE] Using union of masks")
            expand_mask = ma.mask_or(expand_mask, src_mask)

        llogger.debug("Number of informative cells in the data: {}".format(np.sum(~src_mask)))
        llogger.debug("Number of informative cells in the expand mask: {}".format(np.sum(~expand_mask)))

        # Change the mask and the underlying values
        src.mask = expand_mask
        src.data[src.mask] = input_nodata
        # There might be some NoData values lurking around, replace them with
        # zero.
        src.data[src == input_nodata] = 0.0
        
        profile = raster.profile
        profile.update(dtype=src_dtype, count=1, compress=compress,
                       nodata=input_nodata)

        with rasterio.open(output_raster, 'w', **profile) as dst:
            llogger.info("Writing output raster {}".format(output_raster))
            #import pdb; pdb.set_trace()
            dst.write(src.astype(src_dtype), 1)

    all_end = timer()
    all_elapsed = round(all_end - all_start, 2)
    llogger.info(" [TIME] Masking took {} sec".format(all_elapsed))
