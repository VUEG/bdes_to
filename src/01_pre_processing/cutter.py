#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Utility functions for spatial processing."""
import click
import fiona
import functools
import logging
import multiprocessing
import os
import sys
import time
from importlib.machinery import SourceFileLoader
from subprocess import call

utils = SourceFileLoader("lib.utils", "src/00_lib/utils.py").load_module()


def timing(f):
    def wrap(*args, **kwargs):
        time1 = time.time()
        ret = f(*args, **kwargs)
        time2 = time.time()
        print('{} function took {} ms'.format(f.__name__,
                                              (time2 - time1) * 1000.0))
        return ret
    return wrap


def extract_by_value(field_value, infile, clipfile, field, outdir,
                     verbose=False):

        if verbose:
            multiprocessing.log_to_stderr(logging.DEBUG)
        else:
            multiprocessing.log_to_stderr(logging.INFO)
        logger = multiprocessing.get_logger()

        out_raster = infile.split(".")[0] + "_" + field_value + ".tif"
        out_raster = os.path.join(outdir, os.path.basename(out_raster))

        #logger.info("Processing {} into {}".format(infile, out_raster))

        cmd_seq = ["gdalwarp", "-cutline", clipfile,
                   "-cwhere", "{}='{}'".format(field, field_value),
                   infile, out_raster, "-co", "COMPRESS=DEFLATE"]

        call(cmd_seq)


@timing
def cookie_cut(infile, clipfile, field, outdir, cpus, logger=None,
               verbose=False):
    ""

    if logger is None:
        logger = logging.basicConfig()

    # Read in the clipfile and get all the values in the field
    with fiona.open(clipfile, 'r') as clip_src:
        # Check that the provided field exists
        field_names = list(clip_src.meta['schema']['properties'].keys())
        if field not in field_names:
            raise ValueError("Field name {} not found".format(field))
        # Get the field values.
        field_values = [item['properties'][field] for item in clip_src]
        # Check if there are multiple same values
        unique_field_values = list(set(field_values))
        unique_field_values.sort()
        if len(field_values) != len(unique_field_values):
            logger.warning("{} contains multiple same values. Only one instance is retained.".format(field))

        n_field_values = len(unique_field_values)

        logger.info('Clipping {} into {} parts'.format(infile, n_field_values))

        # Set up the worker pool
        pool = multiprocessing.Pool(processes=cpus)
        # Multitprocessing map only takes 1 argument, so we have to use
        # partials
        pool.map(functools.partial(extract_by_value, infile=infile,
                                   clipfile=clipfile, field=field,
                                   outdir=outdir),
                 unique_field_values)
        return(True)


@click.command()
@click.option('-v', '--verbose', is_flag=True)
@click.argument('infile', nargs=1, type=click.Path(exists=True))
@click.argument('clipfile', nargs=1, type=click.Path(exists=True))
@click.option('-f', '--field')
@click.argument('outdir', nargs=1)
@click.option('-c', '--cpus', type=int)
def cli(infile, clipfile, field, outdir, cpus, verbose):
    """ Command-line interface."""

    if verbose:
        multiprocessing.log_to_stderr(logging.DEBUG)
    else:
        multiprocessing.log_to_stderr(logging.INFO)
    logger = multiprocessing.get_logger()

    if field == "":
        click.echo(click.style('ERROR: field name must be provided!',
                               fg='red'))
        sys.exit(-1)

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
        logger.warning('Assigning more jobs ({0}) than available CPUs ({1})'.format(cpus,
                                                                                    available_cpus))

    assert cpus > 0, 'ERROR: number of jobs must be a positive integer'

    success = cookie_cut(infile=infile, clipfile=clipfile, field=field,
                         outdir=outdir, cpus=cpus, logger=logger,
                         verbose=verbose)

    return(0)


if __name__ == '__main__':
    cli()
