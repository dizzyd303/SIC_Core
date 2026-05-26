#!/usr/bin/env python3
"""SIC Unsloth Trainer — fine-tune a model on collected SIC phase scripts."""
import json, os, sys
from datasets import Dataset
from transformers import TrainingArguments

def main():
    base_model = sys.argv[1]
    dataset_path = sys.argv[2]
    output_dir = sys.argv[3]

    data = []
    with open(dataset_path) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                entry = json.loads(line)
                data.append({
                    "instruction": entry.get("instruction", ""),
                    "output": entry.get("output", ""),
                })
            except: pass

    if len(data) < 3:
        print(f"Only {len(data)} samples — need at least 3")
        sys.exit(0)

    print(f"Loaded {len(data)} training samples")

    try:
        from unsloth import FastLanguageModel, is_bfloat16_supported
        import torch

        model, tokenizer = FastLanguageModel.from_pretrained(
            model_name=base_model,
            max_seq_length=2048,
            dtype=None,
            load_in_4bit=True,
        )
        model = FastLanguageModel.get_peft_model(
            model, r=16, lora_alpha=16, lora_dropout=0,
            target_modules=["q_proj","k_proj","v_proj","o_proj",
                            "gate_proj","up_proj","down_proj"],
            use_rslora=True,
        )

        def fmt(example):
            return tokenizer.apply_chat_template(
                [{"role":"user","content":example["instruction"]},
                 {"role":"assistant","content":example["output"]}],
                tokenize=False)

        ds = Dataset.from_list(data)
        ds = ds.map(lambda x: {"text": fmt(x)})

        from trl import SFTTrainer
        trainer = SFTTrainer(
            model=model, tokenizer=tokenizer, train_dataset=ds,
            args=TrainingArguments(
                per_device_train_batch_size=2,
                gradient_accumulation_steps=4,
                num_train_epochs=3,
                learning_rate=2e-4,
                fp16=not is_bfloat16_supported(),
                bf16=is_bfloat16_supported(),
                logging_steps=1,
                output_dir=output_dir,
                save_strategy="no",
            ),
        )
        trainer.train()

        print("Exporting to GGUF...")
        model.save_pretrained_gguf(
            os.path.join(output_dir, "gguf"),
            tokenizer,
            quantization_method="q4_k_m"
        )
        print(f"Model saved to {output_dir}/gguf/")

    except ImportError:
        print("Unsloth not available — dataset saved for later use")
        print(f"Dataset: {dataset_path} ({len(data)} samples)")

if __name__ == "__main__":
    main()
