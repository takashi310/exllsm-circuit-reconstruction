def default_em_params() {
    def deconvrepo = 'registry.int.janelia.org/janeliascicomp'

    [
        deconvrepo: deconvrepo,

        datasets: '',
        data_dir: '',
        output_dir: '',

        stitching_output: 'stitching'

        // stitching params
        stitching_app: 'external-modules/stitching-spark/target/stitching-spark-1.8.2-SNAPSHOT.jar',
        driver_stack: '128m',
        stitching_output: 'stitching',
        resolution: '0.104,0.104,0.18',
        axis: '-y,-x,z',
        channels: '488nm,560nm,642nm',
        block_size: '128,128,64',
        psf_z_step_um: '0.1',
        retile_z_size: '64',
        stitching_mode: 'incremental',
        stitching_padding: '0,0,0',
        blur_sigma: '2',

        deconv_cpus: 4,
        iterations_per_channel: '10,10,10',

    ]
}

def get_value_or_default(Map ps, String param, String default_value) {
    if (ps[param])
        ps[param]
    else
        default_value
}

def get_list_or_default(Map ps, String param, List default_list) {
    def value
    if (ps[param])
        value = ps[param]
    else
        value = null
    return value
        ? value.tokenize(',').collect { it.trim() }
        : default_list
}
