source ~/.bashrc

echo "Options:: $@"

# NCCL_DEBUG=INFO ACCELERATE_LOG_LEVEL=info accelerate launch --config_file recipes/accelerate_configs/zero3.yaml src/open_r1/grpo.py \
#     --config recipes/qwen/Qwen2.5-1.5B-Instruct/grpo/confg_full.yaml \
#     --output_dir DeepSeek-R1-Distill-Qwen-7B-GRPO \
#     --model_name_or_path deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
#     --dataset_name AI-MO/NuminaMath-TIR \
#     --max_prompt_length 256 \
#     --per_device_train_batch_size 2 \
#     --gradient_accumulation_steps 4 \
#     --logging_steps 10 \
#     --bf16 

# ACCELERATE_LOG_LEVEL=info accelerate launch \
#     --config_file recipes/accelerate_configs/zero3.yaml \
#     --num_processes 7 \
#     src/open_r1/grpo.py \
#     --config recipes/qwen/Qwen2.5-1.5B-Instruct/grpo/confg_full.yaml

#SBATCH --job-name=open-r1-grpo
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --exclusive
#SBATCH --gres=gpu:8
#SBATCH --partition=hopper-prod 
#SBATCH --output=./logs/%x-%j.out
#SBATCH --err=./logs/%x-%j.err

set -x -e

source ~/.bashrc
# conda activate openr1
echo "START TIME: $(date)"
echo "PYTHON ENV: $(which python)"

MODEL_PATH=$1
DATASET_PATH=$2
ACCELERATOR=$3


# so processes know who to talk to
# MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
# MASTER_PORT=6000

export CMD=" \
    src/open_r1/grpo.py \
    --model_name_or_path $MODEL_PATH \
    --dataset_name $DATASET_PATH \
    --learning_rate 2.0e-5 \
    --num_train_epochs 1 \
    --max_completion_length 1024 \
    --max_prompt_length 512 \
    --per_device_train_batch_size 4 \
    --per_device_eval_batch_size 4 \
    --gradient_accumulation_steps 4 \
    --gradient_checkpointing \
    --bf16 \
    --use_vllm \
    --vllm_device auto \
    --vllm_gpu_memory_utilization 0.7 \
    --logging_steps 5 \
    --eval_strategy steps \
    --eval_steps 100 \
    --output_dir data/Qwen2.5-1.5B-Open-R1-GRPO
    "

export LAUNCHER="HF_HUB_ENABLE_HF_TRANSFER=1 ACCELERATE_LOG_LEVEL=info TRANSFORMERS_VERBOSITY=info accelerate launch \
    --config_file recipes/accelerate_configs/$ACCELERATOR.yaml  \
    $@ \
    --gradient_accumulation_steps 4 \
    --rdzv_conf "rdzv_backend=c10d,rdzv_endpoint=$MASTER_ADDR:$MASTER_PORT" \
    --max_restarts 1 \
    --role \$(hostname -s): \
    --tee 3 \
    "

# force crashing on nccl issues like hanging broadcast
export NCCL_ASYNC_ERROR_HANDLING=1
# export NCCL_DEBUG=INFO
# export NCCL_DEBUG_SUBSYS=COLL
# export NCCL_SOCKET_NTHREADS=1
# export NCCL_NSOCKS_PERTHREAD=1
# export CUDA_LAUNCH_BLOCKING=1

# Specific configuration optimized for the Hugging Face Compute Cluster
# Be ye warned this may not work on other clusters!
# module load cuda/12.1

# srun error handling:
# --wait=60: wait 60 sec after the first task terminates before terminating all remaining tasks
# --kill-on-bad-exit=1: terminate a step if any task exits with a non-zero exit code
SRUN_ARGS=" \
    --wait=60 \
    --kill-on-bad-exit=1 \
    "

clear;
bash -c "$LAUNCHER $CMD deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B AI-MO/NuminaMath-TIR grpo" 
# clear; srun $SRUN_ARGS --jobid $SLURM_JOB_ID bash -c "$LAUNCHER --role \$SLURMD_NODENAME: $CMD" 2>&1

echo "END TIME: $(date)"