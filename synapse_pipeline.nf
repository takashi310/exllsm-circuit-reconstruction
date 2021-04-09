#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include {
    default_em_params;
    default_synapse_ch_dir;
    default_n1_ch_dir;
    default_n2_ch_dir;
    get_value_or_default;
    get_list_or_default;
    get_stitched_data_dir;
    exm_synapse_container_param;
} from './param_utils'

// app parameters
final_params = default_em_params() + params

include {
    get_stitched_data;
} from './processes/stitching' addParams(final_params)

synapse_params = final_params + [
    exm_synapse_container: exm_synapse_container_param(final_params),
]
include {
    presynaptic_n1_to_n2;
} from './workflows/synapse_detection' addParams(synapse_params)

stitched_data_dir = get_stitched_data_dir(final_params)
pipeline_output_dir = get_value_or_default(final_params, 'output_dir', stitched_data_dir)
create_output_dir(pipeline_output_dir)

workflow {
    def datasets = get_list_or_default(final_params, 'datasets', [])
    def stitched_data = Channel.fromList(
        get_stitched_data(
            stitched_data_dir,
            pipeline_output_dir,
            datasets,
            final_params.stitching_output
        )
    ) // [ dataset, dataset_stitched_dir, dataset_output_dir ]

    def synapse_res;
    switch(final_params.pipeline) {
        case 'presynaptic_n1_to_n2':
            synapses_res = presynaptic_n1_to_n2(
                stitched_data.map { default_synapse_ch_dir(final_params, it[1]) }, // synapse channel stack
                stitched_data.map { default_n1_ch_dir(final_params, it[1]) }, // n1 channel stack
                stitched_data.map { default_n2_ch_dir(final_params, it[1]) }, // n2 channel stack
                stitched_data.map { "${it[2]}/synapses" } // output dir
            )
            break;
        case 'presynaptic_in_volume':
        default:
            synapse_res = presynaptic_in_volume(
                stitched_data.map { default_synapse_ch_dir(final_params, it[1]) }, // synapse channel stack
                stitched_data.map { "${it[2]}/synapses" } // output dir
            )
            break;
    }

    synapses_res | view
}

def create_output_dir(output_dirname) {
    def output_dir = file(output_dirname)
    output_dir.mkdirs()
}
