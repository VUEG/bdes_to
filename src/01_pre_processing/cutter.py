#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Utility functions for spatial processing."""
import click
import fiona
import logging
import numpy as np
import numpy.ma as ma
import os
import rasterio
import sys


def cookie_cut(infile, clipfile, field, outfile, verbose=False):
    ""

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
            click.echo(click.style("WARNING: {} contains multiple same values. Only one instance is retained.".format(field),
                                   fg='orange'))

        n_field_values = len(unique_field_values)

        click.echo(click.style('Clipping {} into {} parts'.format(infile, n_field_values),
                               fg='green'))
        i = 1
        for field_value in unique_field_values:
            click.echo(click.style('[{}/{}] Processing {} '.format(i, n_field_values, field_value),
                                   fg='green'))
            i += 1
            


@click.command()
@click.option('-v', '--verbose', is_flag=True)
@click.argument('infile', nargs=1, type=click.Path(exists=True))
@click.argument('clipfile', nargs=1, type=click.Path(exists=True))
@click.option('-f', '--field')
@click.argument('outfile', nargs=1)
def cli(infile, clipfile, field, outfile, verbose):
    """ Command-line interface."""

    if field == "":
        click.echo(click.style('ERROR: field name must be provided!',
                               fg='red'))
        sys.exit(-1)

    success = cookie_cut(infile, clipfile, field, outfile, verbose=verbose)
    if success:
        click.echo(click.style('Done!', fg='green'))
    else:
        click.echo(click.style('Clipping failed', fg='red'))


if __name__ == '__main__':
    cli()
