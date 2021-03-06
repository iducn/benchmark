#!bin/bash
set -xe

if [[ $# -lt 1 ]]; then
    echo "running job dict is {1: speed, 2:mem, 3:profiler, 6:max_batch_size}"
    echo "Usage: "
    echo "  CUDA_VISIBLE_DEVICES=0 bash run_benchmark.sh 1|2|3|6 sp|mp 1(max_epoch)"
    exit
fi

function _set_params(){
    index="$1"
    run_mode=${2:-"sp"}

    max_epoch=${3}
    if [[ ${index} -eq 3 ]]; then is_profiler=1; else is_profiler=0; fi

    run_log_path=${TRAIN_LOG_DIR:-$(pwd)}
    profiler_path=${PROFILER_LOG_DIR:-$(pwd)}

    model_name="DeepLab_V3+"
    skip_steps=1
    keyword="step/sec"
    separator=" "
    position=4
    range=9:13
    model_mode=3

    device=${CUDA_VISIBLE_DEVICES//,/ }
    arr=($device)
    num_gpu_devices=${#arr[*]}

    if [[ ${index} -eq 6 ]]; then base_batch_size=9; else base_batch_size=2; fi
    batch_size=`expr ${base_batch_size} \* ${num_gpu_devices}`

    log_file=${run_log_path}/${model_name}_${index}_${num_gpu_devices}_${run_mode}
    log_with_profiler=${profiler_path}/${model_name}_3_${num_gpu_devices}_${run_mode}
    profiler_path=${profiler_path}/profiler_${model_name}
    if [[ ${is_profiler} -eq 1 ]]; then log_file=${log_with_profiler}; fi

    log_parse_file=${log_file}

}

function _set_env(){
   export FLAGS_eager_delete_tensor_gb=0.0
   export FLAGS_fast_eager_deletion_mode=1
   export FLAGS_allocator_strategy=naive_best_fit
}

function _train(){
    PRETRAINED_MODEL_DIR="pretrained_model/deeplabv3p_xception65_bn_cityscapes"
#    total_step=240
    echo "Train on ${num_gpu_devices} GPUs"
    echo "current CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES, gpus=$num_gpu_devices, batch_size=$batch_size"

    train_cmd=" --use_gpu \
                --use_mpio \
                --cfg ./configs/deeplabv3p_xception65_cityscapes.yaml \
                --is_profiler=${is_profiler} \
                --profiler_path=${profiler_path} \
                BATCH_SIZE ${batch_size} \
                TRAIN.PRETRAINED_MODEL_DIR ${PRETRAINED_MODEL_DIR} \
                SOLVER.LR 0.001 \
                TRAIN_CROP_SIZE (513,513) \
                SOLVER.NUM_EPOCHS ${max_epoch} \
                AUG.AUG_METHOD unpadding \
                AUG.FIX_RESIZE_SIZE (513,513) \
                AUG.MIRROR False \
                TRAIN.SNAPSHOT_EPOCH ${max_epoch}
               "
#                TRAIN.PRETRAINED_MODEL_DIR u"${PRETRAINED_MODEL_DIR}" \
    case ${run_mode} in
    sp) train_cmd="python -u pdseg/train.py "${train_cmd} ;;
    mp)
        train_cmd="python -m paddle.distributed.launch --log_dir=./mylog --selected_gpus=${CUDA_VISIBLE_DEVICES} pdseg/train.py "${train_cmd}
        log_parse_file="mylog/workerlog.0" ;;
    *) echo "choose run_mode(sp or mp)"; exit 1;
    esac

    ${train_cmd} > ${log_file} 2>&1
    # Python multi-processing is used to read images, so need to
    # kill those processes if the main train process is aborted.
    #ps -aux | grep "$PWD/train.py" | awk '{print $2}' | xargs kill -9
    kill -9 `ps -ef|grep python |awk '{print $2}'`

    if [ $run_mode = "mp" -a -d mylog ]; then
        rm ${log_file}
        cp mylog/workerlog.0 ${log_file}
    fi
}

source ${BENCHMARK_ROOT}/scripts/run_model.sh
_set_params $@
_set_env
_run
