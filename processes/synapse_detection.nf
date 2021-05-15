process create_n5_volume {
    label 'small'

    container { params.exm_synapse_dask_container }

    input:
    tuple val(template_image), val(output_image)

    output:
    tuple val(template_image), val(output_image)

    script:
    """
    mkdir -p ${file(output_image).parent}
    /entrypoint.sh create_n5 -o ${output_image} -t ${template_image} --compression ${params.n5_compression}
    """
}

process read_n5_metadata {
    label 'small'

    container { params.exm_synapse_dask_container }

    input:
    val(n5_stack)

    output:
    tuple val(n5_stack), env(n5_attributes)

    script:
    def n5_attributes_file = "${n5_stack}/s0/attributes.json"
    """
    if [[ -e ${n5_attributes_file} ]]; then
        n5_attributes=`cat ${n5_attributes_file}`
    else
        n5_attributes=null
    fi
    """
}

process tiff_to_n5 {
    container { params.exm_synapse_dask_container }
    cpus { params.tiff2n5_cpus }
    memory { params.tiff2n5_memory }

    input:
    tuple val(input_stack_dir), val(output_n5_stack)

    output:
    tuple val(input_stack_dir), val(output_n5_stack)

    script:
    def chunk_size = params.block_size
    def create_empty_n5 = """
    cat > "${output_n5_stack}/attributes.json" <<EOF
    {"n5":"2.2.0"}
    EOF
    """.stripIndent()

    """
    mkdir -p ${file(output_n5_stack).parent}

    if [[ -f "${input_stack_dir}/s0/attributes.json" ]]; then
        mkdir ${output_n5_stack}
        ln -s "${input_stack_dir}/s0" "${output_n5_stack}/s0" || true
        ${create_empty_n5}
    else
        /entrypoint.sh tif_to_n5 -i ${input_stack_dir} -o ${output_n5_stack} -c ${chunk_size} --compression ${params.n5_compression}
    fi
    """
}

process n5_to_tiff {
    container { params.exm_synapse_dask_container }
    cpus { params.n52tiff_cpus }
    memory { params.n52tiff_memory }

    input:
    tuple val(input_n5_file), val(output_dir)

    output:
    tuple val(input_n5_file), val(output_dir)

    script:
    """
    mkdir -p ${output_dir}
    /entrypoint.sh n5_to_tif.py -i ${input_n5_file} -o ${output_dir}
    """
}

process unet_classifier {
    container { params.exm_synapse_container }
    cpus { params.unet_cpus }
    memory { params.unet_memory }
    accelerator 1
    label 'withGPU'

    input:
    tuple val(input_image), val(output_image_arg), val(vol_size), val(start_subvolume), val(end_subvolume)
    val(synapse_model)

    output:
    tuple val(input_image), val(output_image), val(vol_size), val(start_subvolume), val(end_subvolume)

    script:
    output_image = output_image_arg ? output_image_arg : input_image
    """
    python /scripts/unet_gpu.py \
        -i ${input_image} \
        -m ${synapse_model} \
        --start ${start_subvolume} \
        --end ${end_subvolume} \
        -o ${output_image}
    """
}

process segmentation_postprocessing {
    container { params.exm_synapse_container }
    cpus { params.postprocessing_cpus }
    memory { params.postprocessing_memory }

    input:
    tuple val(input_image), val(mask_image), val(output_image_arg), val(output_csv_dir), val(vol_size), val(start_subvolume), val(end_subvolume)
    val(threshold)
    val(percentage)

    output:
    tuple val(input_image), val(mask_image), val(output_image), val(output_csv_dir), val(vol_size), val(start_subvolume), val(end_subvolume)

    script:
    output_image = output_image_arg ? output_image_arg : input_image
    def mask_arg = mask_image ? "-m ${mask_image}" : ''
    """
    mkdir -p ${output_csv_dir}

    /scripts/postprocess_cpu.sh \
        -i ${input_image} \
        -o ${output_image} \
        --csv_output_path ${output_csv_dir} \
        --start ${start_subvolume} \
        --end ${end_subvolume} \
        -t ${threshold} \
        -p ${percentage} \
        ${mask_arg}
    """
}

process aggregate_csvs {
    container { params.exm_synapse_container }
    label 'small'

    input:
    tuple val(input_csvs_dir), val(output_csv)

    output:
    tuple val(input_csvs_dir), val(output_csv)

    script:
    """
    python /scripts/aggregate_csvs.py \
        -i ${input_csvs_dir} \
        -o ${output_csv}
    """
}