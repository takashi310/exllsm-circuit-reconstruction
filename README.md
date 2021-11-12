# ExLLSM Circuit Reconstruction Pipeline

[![DOI](https://zenodo.org/badge/323991895.svg)](https://zenodo.org/badge/latestdoi/323991895)

This is a pipeline for analyzing expansion lattice light-sheet microscopy data, consisting of several independent workflows, and integration with [VVD Viewer](https://github.com/takashi310/VVD_Viewer).

## Quick Start

The only software requirements for running this pipeline are [Nextflow](https://www.nextflow.io) (version 20.10.0 or greater) and [Singularity](https://sylabs.io) (version 3.5 or greater). If you are running in an HPC cluster, ask your system administrator to install Singularity on all the cluster nodes.

To [install Nextflow](https://www.nextflow.io/docs/latest/getstarted.html):

    curl -s https://get.nextflow.io | bash 

Alternatively, you can install it as a conda package:

    conda create --name exm -c bioconda nextflow

To [install Singularity](https://sylabs.io/guides/3.7/admin-guide/installation.html) on CentOS Linux:

    sudo yum install singularity

Clone the multifish repository with the following command:

    git clone https://github.com/JaneliaSciComp/expansion-microscopy-pipeline.git

Before running the pipeline for the first time, run setup to pull in external dependencies:

    ./setup.sh

You can now launch a pipeline, e.g.:

    ./stitch_pipeline.nf [arguments]

## Pipeline Overview

This pipeline is containerized and portable across the various platforms supported by [Nextflow](https://www.nextflow.io). So far it has been tested on a standalone Linux workstation and the LSF cluster at Janelia Research Campus. If you run it successfully on any other platform, please let us know so that we can update this documentation.

The pipeline includes the following workflows:

* **[Stitching](docs/Stitching.md)** - distributed stitching pipeline including flatfield correction and deconvolution
* **[Image Processing](docs/ImageProcessing.md)** - file conversion, Fiji macros for cropping, cross-talk subtraction, thresholding, and more
* **[Neuron Segmentation](docs/NeuronSegmentation.md)** - semi-automated workflows for neuron segmentation
* **[Synapse Prediction](docs/SynapsePrediction.md)** - workflows for synapse masking and prediction

## Pipeline Execution

### Run the pipeline locally

To run the pipeline locally, you can use the standard profile:

    ./main.nf [arguments]

### Run the pipeline on IBM Platform LSF

To run this pipeline in distributed mode on a cluster, all input and output paths must be mounted and accessible on all the cluster nodes.

Edit `nextflow.config` to create a profile for your local environment. A profile for the Janelia Compute Cluster is provided and can be used like this:

    ./main.nf -profile lsf --lsf_opts "-P project_code" [arguments]

Usage examples are available in the [examples](examples) directory.

## User Manual

Further detailed documentation is available here:

* [General Parameters](docs/Parameters.md)
* Workflows
  * [Stitching](docs/Stitching.md)
  * [Image Processing](docs/ImageProcessing.md)
  * [Neuron Segmentation](docs/NeuronSegmentation.md)
  * [Synapse Prediction](docs/SynapsePrediction.md)
* [Troubleshooting](docs/Troubleshooting.md)
* [Development Guide](docs/Development.md)

## Open Source License

This software is made available under [Janelia's Open Source Software](https://www.janelia.org/open-science/software-licensing) policy which uses the BSD 3-Clause License.
