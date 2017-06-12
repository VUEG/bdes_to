#!/usr/bin/python3
# -*- coding: utf-8 -*-
""" Utility module for the workflow."""
import logging
import numpy as np
import os
import pprint
import yaml
from colorlog import ColoredFormatter
from tabulate import tabulate

# Classes ---------------------------------------------------------------------


class DataManager(object):

    """ Class for a data manager read data manifests.

    Methods of this class can be used to access the content of the data
    manifest file in various ways.
    """

    def __init__(self, infile):
        if os.path.exists(infile):
            self._infile = infile
        else:
            raise IOError("Input data manifest file does not exist")

        # Read and parse the data manifest file
        self._data = self.parse_data_manifest()

    def __len__(self):
        return len(self.data)

    @property
    def data(self):
        """ Data property accessor."""
        return self._data

    def count(self, **kwargs):
        """ Count the number of feaures in a given grouping.

        For allowed query keys, see get_resources().
        """
        return len(self.get_resources(**kwargs))

    def get_category(self, **kwargs):
        """ Get the category associated with a hierarchy level.

        Following hierarchy levels can be used:
            - collection
            - subcollection

        :param **kwargs: key-value -pair, where key must be in ["collection",
                         "subcollection"].
        :return list of String name(s) of the category.
        """
        # List allowed query keys
        allowed_keys = ["collection", "subcollection"]
        # Get the key provided.
        query_keys = list(kwargs.keys())
        # Only one query key allowed.
        if len(query_keys) > 1:
            raise ValueError("Only one query key allowed at time")
        query_key = query_keys[0]

        # Multiple collections can have the same name. Store matches into a
        # list.
        collection_match = []

        # Check that the quey key is allowed
        if query_key in allowed_keys:
            # Construct the actual query key
            item_key = "{}_name".format(query_key)
            for item in self.data:
                # collection category is always present, subcollection category
                # not necessarily.
                if item_key in list(item.keys()):
                    if item[item_key] == kwargs[query_key]:
                        collection_match.append(item['collection_category'])
        else:
            raise ValueError("Allowed query args are: {}".format(", ".join(allowed_keys)))

        if len(collection_match) > 1:
            print("WARNING: multiple collection with the same name")
        return collection_match

    def get_collection(self, **kwargs):
        """ Get the ceollection associated with a hierarchy level.

        Following hierarchy levels can be used:
            - uri
            - provider
            - collection

        :param **kwargs: key-value -pair, where key must be in ["uri",
                         "provider", "collection"].
        :return list of collections.
        """
        pass

    def get_resources(self, full_path=False, **kwargs):
        """ Get the resources associated with a hierarchy level.

        Following hierarchy levels can be used:
            - uri
            - provider
            - collection
            - subcollection
            - category

        :param **kwargs: key-value -pair, where key must be in ["uri",
                         "provider", "collection", "subcollection".
        :return list of String file names.
        """
        # List allowed query keys
        allowed_keys = ["uri", "provider", "collection", "subcollection",
                        "category"]
        # Get the key provided.
        query_keys = list(kwargs.keys())
        # Only one query key allowed.
        if len(query_keys) > 1:
            raise ValueError("Only one query key allowed at time")
        query_key = query_keys[0]

        resource_match = []

        # Check that the quey key is allowed
        if query_key in allowed_keys:
            # Construct the actual query key
            if query_key == "uri":
                item_key = query_key
            elif query_key == "category":
                item_key = "collection_category"
            else:
                item_key = "{}_name".format(query_key)
            for item in self.data:
                # uri, provider and collection category are always present,
                # subcollection category not necessarily.
                if item_key in list(item.keys()):
                    if item[item_key] == kwargs[query_key]:
                        if full_path:
                            url = "{0}/{1}/{2}".format(item['uri'],
                                                       item['provider_name'],
                                                       item['collection_name'])
                            if "subcollection_name" in list(item.keys()):
                                url = "{0}/{1}".format(url,
                                                       item['subcollection_name'])
                            resources = []
                            for resource in item['collection_resources']:
                                resources.append("{0}/{1}".format(url, resource))
                        else:
                            resources = item['collection_resources']
                        resource_match += resources
        else:
            raise ValueError("Allowed query args are: {}".format(", ".join(allowed_keys)))

        return resource_match

    def get_tabular(self, **kwargs):
        """ Get a hierarchy level as a tabular table.

        Following hierarchy levels can be used:
            - collection
            - subcollection

        :param **kwargs: key-value -pair, where key must be in ["collection",
                         "subcollection"]
        :return list of String file names.
        """
        # List allowed query keys
        allowed_keys = ["collection", "subcollection"]
        # Get the key provided.
        query_keys = list(kwargs.keys())
        # Only one query key allowed.
        if len(query_keys) > 1:
            raise ValueError("Only one query key allowed at time")
        query_key = query_keys[0]

        tablerows = []

        # Check that the quey key is allowed
        if query_key in allowed_keys:
            # Construct the actual query key
            item_key = "{}_name".format(query_key)
            for item in self.data:
                # collection category is always present,
                # subcollection category not necessarily.
                if item_key in list(item.keys()):
                    if item[item_key] == kwargs[query_key]:
                        for resource in item['collection_resources']:
                            spp_name = self.resource_to_name(resource)
                            if query_key == "collection":
                                if "subcollection_name" in list(item.keys()):
                                    tablerows.append([item['subcollection_name'],
                                                     spp_name])
                                else:
                                    tablerows.append([spp_name])
                            elif query_key == "subcollection":
                                tablerows.append([spp_name])
        else:
            raise ValueError("Allowed query args are: {}".format(", ".join(allowed_keys)))

        if len(tablerows[0]) == 1:
            table = tabulate(tablerows, headers=["species"])
        elif len(tablerows[0]) == 2:
            table = tabulate(tablerows, headers=["group", "species"])
        return(table)


    def parse_data_manifest(self):
        """ Parse datasets from a data manifest file.

        Current implementation can work with the following hierarchy:
            [URI]: dict
                "provider": str
                "collections": list
                    [NAME]: dict
                        "category": str
                        "metadata": list
                        "resources": list
        """
        def parse_collection(collection, collection_name):
            collection_data = {}
            collection_item = collection[collection_name]
            # Get the values for checking
            collection_keys = list(collection_item.keys())
            # Category is optional
            if 'category' in collection_keys:
                collection_data['collection_category'] = collection_item['category']
            # Metadata is optional
            if 'metadata' in collection_keys:
                collection_data['collection_metadata'] = collection_item['metadata']
            # Resources is required
            if 'resources' in collection_keys:
                collection_data['collection_resources'] = collection_item['resources']
            else:
                raise ValueError("Collection {} contains no resources".format(collection_name))

            return collection_data

        items = []

        data_manifest = yaml.safe_load(open(self._infile, 'r'))
        for item in data_manifest:
            # Item should only have one key, which is the URI
            uri = list(item.keys())[0]
            # Loop over the provider content. A single provider can have
            # multiple collections.
            for provider_content in item[uri]:
                # Get the textual name of the provider
                provider_name = provider_content['provider']
                # Loop over the collections for this provider
                for collection in provider_content['collections']:
                    # Collection name is the only key
                    collection_name = list(collection.keys())[0]
                    # Check whether collection item is a dict or a list
                    # (indicating subgroups)
                    if isinstance(collection[collection_name], dict):
                        collection_data = parse_collection(collection,
                                                           collection_name)
                        collection_data['uri'] = uri
                        collection_data['provider_name'] = provider_name
                        collection_data['collection_name'] = collection_name
                        items.append(collection_data)
                    elif isinstance(collection[collection_name], list):
                        for subcollection in collection[collection_name]:
                            subcollection_name = list(subcollection.keys())[0]
                            subcollection_data = parse_collection(subcollection,
                                                                  subcollection_name)
                            subcollection_data['uri'] = uri
                            subcollection_data['provider_name'] = provider_name
                            subcollection_data['collection_name'] = collection_name
                            subcollection_data['subcollection_name'] = subcollection_name
                            items.append(subcollection_data)
                    else:
                        raise ValueError("Invalid collection type")

        return items

    def resource_to_name(self, resource):
        """ Convert raster file name to a species name."""
        spp_name = resource.replace(".tif", "").replace("_", " ").capitalize()
        return(spp_name)

    def manifest(self):
        pprint.pprint(self.data)

# Functions -------------------------------------------------------------------

def find_nearest(array, value):
    idx = (np.abs(array - value)).argmin()
    return array[idx]


def get_iteration_prefix(i, total):
    """ Return a String prefix for itarative task phases.

    :param i int current step.
    :param total int total steps.
    """
    return " [{0}/{1}]".format(i, total)


def get_local_logger(name, log_file=None, debug=False):
    """ Return a local logger."""
    date_format = "%Y-%m-%d %H:%M:%S"
    colFormatter = ColoredFormatter("%(log_color)s %(message)s%(reset)s",
                                    datefmt=date_format,
                                    reset=True,
                                    log_colors={'DEBUG':    'cyan',
                                                'INFO':     'green',
                                                'WARNING':  'yellow',
                                                'ERROR':    'red',
                                                'CRITICAL': 'red',
                                                })
    llogger = logging.getLogger(name)
    llogger.setLevel(logging.DEBUG)
    consoleHandler = logging.StreamHandler()
    consoleHandler.setFormatter(colFormatter)
    if not debug:
        consoleHandler.setLevel(logging.INFO)
    llogger.addHandler(consoleHandler)

    if log_file is not None:
        fileFormatter = logging.Formatter("%(asctime)s [%(name)-10s] " +
                                          "[%(levelname)-5.5s] %(message)s",
                                          datefmt=date_format)

        fileHandler = logging.FileHandler(log_file, mode='w')

        fileHandler.setFormatter(fileFormatter)
        llogger.addHandler(fileHandler)

    return llogger


def pick_from_list(items, suffix):
    """ Pick an element from list ending with suffix.

    If no match is found, return None.

    :param items list of items to be searched.
    :suffix String suffix defining the match.
    """
    match = None
    for item in items:
        if item.endswith(suffix):
            match = item
    return match


def process_stdout(x, prefix=""):
    """Process stdout string returned by a shell command.

    If x is None, return an empty list.
    """
    if x is None or x == "":
        return []
    x = x.decode('utf-8')
    return [prefix + " " + item for item in x.split("\n") if item != ""]
