DIR=$(cd "$(dirname "$0")"; pwd)

source ${DIR}/container-versions.sh

docker build \
    -t registry.int.janelia.org/exm-analysis/synapse:${synapse_version} \
    -t synapse:${synapse_version} \
    -t synapse \
    containers/synapse

docker build \
    -t registry.int.janelia.org/exm-analysis/synapse-dask:${synapse_dask_version} \
    -t synapse-dask:${synapse_dask_version} \
    -t synapse-dask \
    containers/synapse-dask

docker build \
    -t registry.int.janelia.org/exm-analysis/neuron-segmentation:${neuron_segmentation} \
    -t neuron-segmentation:${neuron_segmentation} \
    -t neuron-segmentation \
    containers/neuron-segmentation
