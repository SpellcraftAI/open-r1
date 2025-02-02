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

source ~/.bashrc
# conda activate openr1
echo "START TIME: $(date)"
echo "PYTHON ENV: $(which python)"

MODEL_PATH=deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B
DATASET_PATH=AI-MO/NuminaMath-TIR
ACCELERATOR=zero3


# so processes know who to talk to
# MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
# MASTER_PORT=6000

GRADIENT_ACC_STEPS=16

export CMD=" \
    src/open_r1/grpo.py \
    --model_name_or_path $MODEL_PATH \
    --dataset_name $DATASET_PATH \
    --learning_rate 2.0e-5 \
    --num_train_epochs 1 \
    --max_completion_length 1024 \
    --max_prompt_length 512 \
    --per_device_train_batch_size 1 \
    --per_device_eval_batch_size 4 \
    --gradient_accumulation_steps $GRADIENT_ACC_STEPS \
    --gradient_checkpointing \
    --bf16 \
    --logging_steps 5 \
    --eval_strategy steps \
    --eval_steps 100 \
    --output_dir data/Qwen2.5-1.5B-Open-R1-GRPO
    "

export LAUNCHER="HF_HUB_ENABLE_HF_TRANSFER=1 ACCELERATE_LOG_LEVEL=info TRANSFORMERS_VERBOSITY=info accelerate launch \
    --config_file recipes/accelerate_configs/$ACCELERATOR.yaml  \
    $@ \
    --gradient_accumulation_steps $GRADIENT_ACC_STEPS \
    --max_restarts 1 \
    --role \$(hostname -s): \
    --tee 3 \
    "

# force crashing on nccl issues like hanging broadcast
export NCCL_ASYNC_ERROR_HANDLING=1

clear;
bash -c "$LAUNCHER $CMD";
# clear; srun $SRUN_ARGS --jobid $SLURM_JOB_ID bash -c "$LAUNCHER --role \$SLURMD_NODENAME: $CMD" 2>&1

echo "END TIME: $(date)"