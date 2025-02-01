source ~/.bashrc

echo "Options:: $@"

NCCL_DEBUG=INFO ACCELERATE_LOG_LEVEL=info accelerate launch --config_file recipes/accelerate_configs/zero3.yaml src/open_r1/grpo.py \
    --config recipes/qwen/Qwen2.5-1.5B-Instruct/grpo/confg_full.yaml \
    --output_dir DeepSeek-R1-Distill-Qwen-7B-GRPO \
    --model_name_or_path deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
    --dataset_name AI-MO/NuminaMath-TIR \
    --max_prompt_length 256 \
    --per_device_train_batch_size 2 \
    --gradient_accumulation_steps 4 \
    --logging_steps 10 \
    --bf16 