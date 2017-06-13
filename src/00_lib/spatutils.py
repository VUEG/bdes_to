#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Utility functions for spatial processing."""
import click
import logging
import numpy as np
import numpy.ma as ma
import os
import pandas as pd
import rasterio
import scipy.stats

from importlib.machinery import SourceFileLoader
from joblib import Memory
from scipy.signal import medfilt

utils = SourceFileLoader("lib.utils", "src/00_lib/utils.py").load_module()

# Define caching dir
memory = Memory(cachedir="./.cache", verbose=2)


def get_profile(input_rasters, warn_inconistent=True, pick="first",
                logger=None):
    """ Construct a raster profile base on a list of input raster files.

    Function will loop over a list of input raster files, extract raster
    profile (metadata), possibly check for inconsistencies and return
    a profile. The profile returned is always that of the raster last in the
    list.

    :param input_rasters: String list of raster paths.
    :param warn_inconistent: Boolean should inconsistent profiles cause a
                             warning?
    :param pick: String of either value "first" or "last". Former picks the
                 profile from the first raster in the list, "last" the last.
    :param logger: Logger object.
    :return: Dict profile (raster metadata).
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('get_profile')
        llogger.setLevel(logging.INFO)
    else:
        llogger = logger

    if pick not in ["first", "last"]:
        raise ValueError("Value for 'pick' must be either 'first' or 'last'")

    current_profile = None
    for i, raster in enumerate(input_rasters):
        with rasterio.open(raster) as src:
            profile = src.profile
            if i == 0:
                current_profile = profile
            else:
                if warn_inconistent and profile != current_profile:
                    llogger.warning(" [WARN] Inconsistent raster profiles " +
                                    "detected")
                    warn_inconistent = False
                if pick == 'last':
                    current_profile = profile
    return current_profile


def normalize(x):
    """ Rescale all numeric values in range [0, 1].

    Input must be a numpy ndarray, no coercion is tried.

    :param x: numpy ndarray to be rescaled.
    :return: numpy ndarray with rescaled values.
    """
    if type(x) is not np.ndarray and type(x) is not ma.core.MaskedArray:
        raise TypeError("x must be a numpy.ndarray or numpy.ma.MaskedArray")

    # NOTE: the approach commented out below would be more memory efficient,
    # but doesn't work as such with masked arrays
    # np.true_divide(x, np.max(np.abs(x)), out=x, casting='unsafe')
    # Data may have negative values, thus first add the abs(min(x)) to
    # everything.
    x_min = ma.min(x)
    x_max = ma.max(x)
    return (x - x_min) / (x_max - x_min)


def ol_normalize(x):
    """ Normalize layer based on occurrence levels in the array.

    The value of each element is divided by the sum off all elements. Input
    must be a numpy ndarray, no coercion is tried.

    :param x: numpy ndarray to be rescaled.
    :return: numpy ndarray with transformed values.
    """
    if type(x) is not np.ndarray and type(x) is not ma.core.MaskedArray:
        raise TypeError("x must be a numpy.ndarray or numpy.ma.MaskedArray")

    min_val = ma.min(x)

    return (x - min_val) / (ma.sum(x - min_val))


def get_range_size(input_raster, verbose=False, logger=None):
    """ Get range size of an input raster based on stat provided.

    :param input_raster: String path to an input raster.
    :param stat: String defining which type of statistic is used to calculate
                 the range size. Currently implemented:

    :param pick: String of either value "first" or "last". Former picks the
                 profile from the first raster in the list, "last" the last.
    :param logger: Logger object.
    :return: A Pandas dataframe of numeric values for the following statistics:
            "count": number of cells with positive values
            "sum": summed values of all cells
            "median_ol": median occurrence level over all cells > 0
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('get_range_size')
    else:
        llogger = logger
    llogger.setLevel(logging.DEBUG if verbose else logging.INFO)

    if not os.path.exists(input_raster):
        raise OSError("Input raster {} not found".format(input_raster))

    with rasterio.open(input_raster) as in_src:
        # Read the first band
        src_data = in_src.read(1, masked=True)
        stat_count = np.sum(src_data > 0)
        stat_sum = np.sum(src_data)
        # Compress data
        src_data = src_data.compressed()
        src_data_ol = ol_normalize(src_data)
        stat_q75, stat_q25 = np.nanpercentile(src_data_ol, (75, 25))
        stat_mean_ol = np.mean(src_data_ol[src_data_ol > 0])
        stat_median_ol = np.median(src_data_ol[src_data_ol > 0])

        stat = pd.DataFrame({"feature": [input_raster],
                             "count": [stat_count],
                             "sum": [stat_sum],
                             "q25_ol": [stat_q25],
                             "mean_ol": [stat_mean_ol],
                             "median_ol": [stat_median_ol],
                             "q75_ol": [stat_q75]})
        llogger.debug(stat)

    return stat


def rescale_raster(input_raster, output_raster, method, fill_w_zeros=False,
                   only_positive=False, compress='DEFLATE', verbose=False,
                   logger=None):
    """ Rescale all numeric values of a raster according ot a given method.

    Currently two methods are implemented:
        1. 'normalize'
        2. 'normalize_ol'
        3. 'standardize'

    :param input_raster: String path to raster file to be normalized.
    :param output_raster: String path to raster file to be created.
    :param method: String method to use.
    :param fill_w_zeros:  Boolean indicating whether NoData is encoded as real
                          NoData or filled with zeros.
    :param only_positive: Boolean indicating if negative values (in the
                          original raster) should be ignored.
    :param compress: String compression level used for the output raster.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: Logger object.
    :return Boolean True if success, False otherwise
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('rescale_raster')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger
    NODATA_VALUE = -3.4e+38
    llogger.debug("Using internal NoData value {}".format(NODATA_VALUE))

    if not os.path.exists(input_raster):
        raise OSError("Input raster {} not found".format(input_raster))

    with rasterio.open(input_raster) as in_src:
        # Read the first band
        src_data = in_src.read(1, masked=True)
        # Cast data to float32 as that's what's used anyways
        src_data = src_data.astype(np.float32)
        # Check min and max
        decimals = 12
        src_min = np.round(src_data.min(), decimals)
        src_max = np.round(src_data.max(), decimals)
        if src_min == 0.0 and src_max == 0.0:
            llogger.warning('{} has all zero values, '.format(input_raster +
                            'skipping'))
            return False

        # Get information on the distribution of values before rescaling
        src_q75, src_q25 = np.nanpercentile(ma.filled(src_data, np.nan),
                                            (75, 25))
        src_q25 = np.round(src_q25, decimals)
        src_q75 = np.round(src_q75, decimals)
        src_mean = np.round(src_data.mean(), decimals)
        llogger.debug(" Before rescaling (min, q25, mean, q75, max): " +
                      "{0}, {1}, {2}, {3}, {4}".format(src_min, src_q25,
                                                       src_mean, src_q75,
                                                       src_max))
        # Only positive values?
        if only_positive:
            if src_min < 0:
                llogger.info("Ignoring negative values")
                src_data = src_data.clip(min=0)
            else:
                llogger.warning("Ignore negative values requested but " +
                                " there are none")

        # Do the actual rescaling
        if method == 'normalize':
            rescaled_data = normalize(src_data)
        elif method == 'ol_normalize':
            rescaled_data = ol_normalize(src_data)
        elif method == 'standardize':
            pass
        else:
            raise TypeError("Method {} not implemented".format(method))

        dst_q75, dst_q25 = np.nanpercentile(ma.filled(rescaled_data, np.nan),
                                            (75, 25))
        dst_q25 = np.round(dst_q25, decimals)
        dst_q75 = np.round(dst_q75, decimals)
        dst_min = np.round(rescaled_data.min(), decimals)
        dst_mean = np.round(rescaled_data.mean(), decimals)
        dst_max = np.round(rescaled_data.max(), decimals)
        llogger.debug("  After rescaling (min, q25, mean, q75, max): " +
                      "{0}, {1}, {2}, {3}, {4}".format(dst_min, dst_q25,
                                                       dst_mean, dst_q75,
                                                       dst_max))

        # Write the product.
        profile = in_src.profile
        # Rescaled data is always float32, and we have only 1 band.
        profile.update(dtype=rasterio.float32, compress=compress,
                       nodata=NODATA_VALUE)
        # Replace the NoData values and set the fill value for NoData, unless
        # the result is to be filled with zeros
        if fill_w_zeros:
            rescaled_data = ma.filled(rescaled_data, 0)
            llogger.debug("Filling NoData with zeros")
        else:
            rescaled_data = ma.filled(rescaled_data, NODATA_VALUE)

        with rasterio.open(output_raster, 'w', **profile) as dst:
            if not fill_w_zeros:
                # Set the NoData mask
                dst.write_mask(in_src.read_masks(1))
            dst.write(rescaled_data, 1)
            llogger.debug("Wrote raster {}".format(output_raster))
        return True


def smooth_raster(input_raster, output_raster, method, log_transform=False,
                  fill_w_zeros=False, compress='DEFLATE', verbose=False,
                  logger=None):
    """ Smooth a raster according ot a given method.

    Currently only one method is implemented:
        1. 'medfilt'

    :param input_raster: String path to raster file to be normalized.
    :param output_raster: String path to raster file to be created.
    :param method: String method to use.
    :param log_transform: Boolean indicating whether values are log transformed.
    :param fill_w_zeros:  Boolean indicating whether NoData is encoded as real
                          NoData or filled with zeros.
    :param compress: String compression level used for the output raster.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: Logger object.
    :return Boolean True if success, False otherwise
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('smooth_raster')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    if not os.path.exists(input_raster):
        raise OSError("Input raster {} not found".format(input_raster))

    with rasterio.open(input_raster) as in_src:
        NODATA_VALUE = in_src.nodata
        llogger.debug("Using internal NoData value {}".format(NODATA_VALUE))

        # Read the first band
        src_data = in_src.read(1, masked=True)
        # Check min and max
        decimals = 12
        src_min = np.round(src_data.min(), decimals)
        src_max = np.round(src_data.max(), decimals)
        if src_min == 0.0 and src_max == 0.0:
            llogger.warning('{} has all zero values, '.format(input_raster +
                            'skipping'))
            return False

        if log_transform:
            llogger.debug("Log transforming data")
            src_data = ma.log(src_data)

        # Do the actual rescaling
        if method == 'medfilt':
            llogger.debug("Using method '{}'".format(method))
            smoothed_data = medfilt(src_data, kernel_size=9)
        else:
            raise TypeError("Method {} not implemented".format(method))

        # Write the product
        profile = in_src.profile
        # Remember to fill the data into Float32
        profile.update(compress=compress, dtype=rasterio.float32)
        # Replace the NoData values and set the fill value for NoData, unless
        # the result is to be filled with zeros
        if fill_w_zeros:
            rescaled_data = ma.filled(smoothed_data, 0)
            llogger.debug("Filling NoData with zeros")
        else:
            rescaled_data = ma.filled(smoothed_data, NODATA_VALUE)

        with rasterio.open(output_raster, 'w', **profile) as dst:
            if not fill_w_zeros:
                # Set the NoData mask
                dst.write_mask(in_src.read_masks(1))
            dst.write(rescaled_data.astype(profile['dtype']), 1)
            llogger.debug("Wrote raster {}".format(output_raster))
        return True


@memory.cache(ignore=['logger', 'verbose'])
def sum_raster(input_rasters, olnormalize=False, weights=None, verbose=False,
               logger=None):
    """ Sum a group of input rasters.

    Read in a group of input rasters and sum the values in each cell. All
    rasters must have the same dimensions, no broadcasting allowed.

    Optionally, values in all rasters can occurrence level (OL) normalized
    before summation.

    It is possible to provide a list (vector) of weights for each features.
    These values are used as simple multipliers for each feature when summing
    the values over all features. If provided, the list must match the number
    of input rasters exactly.

    NOTE: sum_raster uses Memory from joblib to cache the computed sum raster.

    :param input_rasters: String list of input raster paths.
    :param ol_normalize: Boolean indicating wether OL normalization is done.
    :param weights: list of weights. Length must match the number of input
                    rasters.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: Logger object.
    :return: numpy masked array of summed values.
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('sum_raster')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    if ol_normalize:
        llogger.info(" [NOTE] Using occurrence level normalization")
    if weights:
        llogger.info(" [NOTE] Using weights")

    # Check inputs
    assert len(input_rasters) > 0, "Input rasters list cannot be empty"
    if weights:
        assert_msg = "Length of weights must match the number of input rasters"
        assert len(weights) == len(input_rasters), assert_msg

    # Initiate the data structure for holding the summed values.
    sum_array = None
    # The final analysis mask is constructed as the union of all masks. 0 is
    # legitimate value, so converting NoData to 0s is not an option.
    union_mask = None
    # Track that the shape of the rasters is consistent
    template_shape = None

    n_rasters = len(input_rasters)

    for i, input_raster in enumerate(input_rasters):
        no_raster = i + 1

        if not os.path.exists(input_raster):
            raise OSError("Input raster {} not found".format(input_raster))

        with rasterio.open(input_raster) as in_src:
            prefix = utils.get_iteration_prefix(no_raster, n_rasters)
            llogger.info("{0} Processing raster {1}".format(prefix,
                                                            input_raster))
            llogger.debug("{0} Reading in data".format(prefix))

            # Read the first band as a masked array
            src_data = in_src.read(1, masked=True)
            # If this is the first raster, use its dimensions to build an array
            # that holds the summed values.
            if i == 0:
                # Start tracking the masked values. Convert the Boolean
                # mask to an int mask. Get the complement of the mask so that
                # mask = True becomes 0.
                union_mask = (~ma.getmask(src_data)).astype(int)
                # Get the template shape against which all the consecutive
                # rasters are compared to
                template_shape = src_data.shape
                # Set up an array of zeros that has the correct dimensions
                sum_array = np.zeros(template_shape, dtype=np.float32)
            else:
                # Check the shape
                if src_data.shape != template_shape:
                    raise ValueError("Array (raster) shapes do not match")
                # Union the mask from the current raster with those from all
                # of the previous
                union_mask += (~ma.getmask(src_data)).astype(int)

            if olnormalize:
                # 1. Occurrence level normalize data --------------------------
                llogger.debug("{0} OL normalizing data".format(prefix))
                src_data = ol_normalize(src_data)

            # Sum OL normalized data ---------------------------------------
            if weights:
                llogger.debug("{0} Summing weighted values".format(prefix))
                src_data *= weights[i]
            else:
                llogger.debug("{0} Summing values".format(prefix))

            # Fill the actual data with 0s
            src_data = ma.filled(src_data, 0)

            sum_array += src_data

    # Re-mask the data based on the union mask constructed dynamically. At this
    # point, union_mask = 0 means that the cell doesn't have a value in any of
    # the inputs.
    sum_array = ma.masked_where(union_mask == 0, sum_array)

    return sum_array


def winsorize(x, limits=0.05):
    """ Winsorize values in an array.

    The distribution of many statistics can be heavily influenced by outliers.
    A typical strategy is to set all outliers to a specified percentile of the
    data; for example, a 90% winsorization would see all data below the 5th
    percentile set to the 5th percentile, and data above the 95th percentile
    set to the 95th percentile. Winsorized estimators are usually more robust
    to outliers than their more standard forms.

    See https://en.wikipedia.org/wiki/Winsorizing

    :param x: numpy ndarray to be rescaled.
    :param limits: Tuple of the percentages to cut on each side of the array,
                   with respect to the number of unmasked data, as floats
                   between 0. and 1. Noting n the number of unmasked data
                   before trimming, the (n*limits[0])th smallest data and the
                   (n*limits[1])th largest data are masked, and the total
                   number of unmasked data after trimming is n*(1.-sum(limits))
                   The value of one limit can be set to None to indicate an
                   open interval.
    :return: numpy ndarray with transformed values.
    """
    if type(x) is not np.ndarray and type(x) is not ma.core.MaskedArray:
        raise TypeError("x must be a numpy.ndarray or numpy.ma.MaskedArray")

    return scipy.stats.mstats.winsorize(x, limits=limits)


@click.command()
@click.option('-m', '--method', default='normalize',
              help='Rescaling method used.')
@click.option('-v', '--verbose', is_flag=True)
@click.argument('infile', nargs=1, type=click.Path(exists=True))
@click.argument('outfile', nargs=1)
def cli(infile, outfile, method, verbose):
    """ Command-line interface."""
    click.echo(click.style('Rescaling (method: {0}) file {1}'.format(method,
                                                                     infile),
                           fg='green'))
    success = rescale_raster(infile, outfile, method=method, verbose=verbose)
    if success:
        click.echo(click.style('Done!', fg='green'))
    else:
        click.echo(click.style('Normalization failed', fg='red'))


if __name__ == '__main__':
    cli()
