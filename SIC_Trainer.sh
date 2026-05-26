#!/bin/bash
#===============================================================================
# SIC_Trainer.sh — Scarface Intelligence Core | Model Trainer Module
#
# Collects successful phase scripts from past SIC runs, builds a training
# dataset, fine-tunes a model with Unsloth, exports to GGUF, and imports
# into Ollama for use by other SIC modules.
#
# Usage:
#   ./SIC_Trainer.sh "train coder model on past runs"
#   ./SIC_Trainer.sh "list dataset"
#   MODEL_TO_TRAIN=qwen2.5-coder:7b ./SIC_Trainer.sh "train on last 50 runs"
#
# Part of: SIC Platform v1.4.1
#===============================================================================

SIC_CORE="$(cd "$(dirname "$0")" && pwd)/sic_core.sh"
[[ ! -f "$SIC_CORE" ]] && SIC_CORE="/usr/local/lib/sic_core.sh"
source "$SIC_CORE"

sic_register_module \
    --name "SIC_Trainer" \
    --tools "python3, unsloth, curl, ollama, jq, find, grep, awk" \
    --danger 'mkfs|dd of=/dev/sd|nc -e|bash -i >|sh -i >|chmod 777 /' \
    --plan \
        "1. Collect successful phase scripts from past SIC runs" \
        "2. Build structured training dataset (plan -> bash script pairs)" \
        "3. Fine-tune base model with Unsloth (LoRA/QLoRA)" \
        "4. Export fine-tuned model to GGUF format" \
        "5. Import into Ollama and update pipeline config"

# Check for Unsloth
_check_unsloth() {
    if python3 -c "import unsloth" 2>/dev/null; then
        echo "available"
    elif python3 -c "import torch; import transformers; from datasets import Dataset; from trl import SFTTrainer" 2>/dev/null; then
        echo "partial-no-unsloth"
    else
        echo "missing-deps"
    fi
}

# ── Phase 1: Collect runs ──
_collect_runs() {
    local out_dir="$1" max_runs="${2:-50}"
    mkdir -p "$out_dir"
    local count=0

    # Source: ~/.sic/runs/
    for rundir in "$SIC_RUNS_DIR"/*/; do
        [[ -d "$rundir" ]] || continue
        [[ "$count" -ge "$max_runs" ]] && break
        local plan="$rundir/plan.txt"
        local scripts_dir="$rundir/scripts"
        [[ -f "$plan" ]] && [[ -d "$scripts_dir" ]] || continue
        for script in "$scripts_dir"/phase_*.sh; do
            [[ -f "$script" ]] || continue
            local desc; desc=$(grep -oP '# \K.*' "$script" 2>/dev/null | head -1 || echo "Phase")
            python3 -c "
import json
with open('$script') as f: content = f.read()
entry = {'instruction': '$desc', 'output': content}
with open('$out_dir/dataset.jsonl', 'a') as f:
    f.write(json.dumps(entry) + chr(10))
" 2>/dev/null || true
            count=$(( count + 1 ))
        done
    done

    # Also scan /tmp/sic_*/
    for tmpdir in /tmp/sic_*/; do
        [[ -d "$tmpdir" ]] || continue
        [[ "$count" -ge "$max_runs" ]] && break
        local plan="$tmpdir/plan.txt"
        local scripts_dir="$tmpdir/scripts"
        [[ -f "$plan" ]] && [[ -d "$scripts_dir" ]] || continue
        for script in "$scripts_dir"/phase_*.sh; do
            [[ -f "$script" ]] || continue
            local desc; desc=$(grep -oP '# \K.*' "$script" 2>/dev/null | head -1 || echo "Phase")
            python3 -c "
import json
with open('$script') as f: content = f.read()
entry = {'instruction': '$desc', 'output': content}
with open('$out_dir/dataset.jsonl', 'a') as f:
    f.write(json.dumps(entry) + chr(10))
" 2>/dev/null || true
            count=$(( count + 1 ))
        done
    done

    echo "$count"
}

# ── Phase 3: Train ──
_train_model() {
    local dataset="$1" model_name="${2:-qwen2.5-coder:7b}" output_dir="$3"
    local base_model="${UNSLOTH_BASE:-Qwen/Qwen2.5-Coder-7B-Instruct}"
    mkdir -p "$output_dir"

    local trainer_script
    trainer_script="$(cd "$(dirname "$0")" && pwd)/train_unsloth.py"
    if [[ -f "$trainer_script" ]]; then
        python3 "$trainer_script" "$base_model" "$dataset" "$output_dir" 2>&1 | while IFS= read -r line; do echo "     $line"; done
    else
        echo "     train_unsloth.py not found in module directory"
        return 1
    fi
}

# ── Phase 5: Import to Ollama ──
_import_ollama() {
    local gguf_dir="$1" tag="${2:-sic-coder:latest}"
    local gguf_file; gguf_file=$(ls "$gguf_dir"/*.gguf 2>/dev/null | head -1)
    [[ -z "$gguf_file" ]] && { echo "No GGUF found"; return 1; }

    local modelfile="$gguf_dir/Modelfile"
    cat > "$modelfile" <<OLLAMAEOF
FROM $gguf_file
TEMPLATE """{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
"""
PARAMETER temperature 0.3
PARAMETER top_p 0.9
OLLAMAEOF

    if command -v ollama &>/dev/null; then
        ollama create "$tag" -f "$modelfile" 2>&1 | while IFS= read -r line; do echo "     $line"; done
        echo "     Imported: ollama run $tag"
        echo ""
        echo "  Next: CODER_MODEL=$tag ./SIC_Skip.sh \"...\""
    else
        echo "     Ollama not found — GGUF at $gguf_dir"
        echo "     Manual: ollama create $tag -f $modelfile"
    fi
}

# ── Module Suite ──
sic_run_module_suite() {
    local target="$1" tmp_dir="$2"
    local model="${MODEL_TO_TRAIN:-qwen2.5-coder:7b}"
    local max_runs="${MAX_RUNS:-50}"
    local tag="${MODEL_TAG:-sic-coder:latest}"

    echo ""
    echo -e "${PURPLE}🧠 SIC TRAINER: Model fine-tuning pipeline${NC}"
    echo ""

    # Phase 1: Collect
    echo -e "${CYAN}  [1/5] Collecting past runs...${NC}"
    local collected
    collected=$(_collect_runs "$tmp_dir/dataset" "$max_runs")
    echo "     Collected $collected script samples"

    if [[ "$collected" -eq 0 ]]; then
        echo -e "${YELLOW}     No past runs — writing seed dataset${NC}"
        python3 /dev/stdin << 'SEEDEOF'
import json
seeds = [
    {"instruction": "Scan target for open ports using nmap",
     "output": "#!/bin/bash\nnmap -Pn -T4 --top-ports 1000 \"$TARGET\" -oN phase_ports.txt 2>/dev/null || true"},
    {"instruction": "Search social media for person name using sherlock",
     "output": "#!/bin/bash\nwhich sherlock 2>/dev/null && timeout 60 sherlock \"$TARGET\" --output phase_sherlock.txt 2>/dev/null || true"},
    {"instruction": "Run web technology fingerprinting with whatweb",
     "output": "#!/bin/bash\nwhatweb \"$TARGET\" --log-verbose=phase_whatweb.txt 2>/dev/null || true"},
]
with open('/tmp/sic_seed_dataset.jsonl', 'w') as f:
    for s in seeds:
        f.write(json.dumps(s) + '\n')
SEEDEOF
        cp /tmp/sic_seed_dataset.jsonl "$tmp_dir/dataset/dataset.jsonl"
        echo "     Created 3 seed samples"
    fi

    # Phase 2: Check Unsloth
    echo -e "${CYAN}  [2/5] Checking dependencies...${NC}"
    local us; us=$(_check_unsloth)
    case "$us" in
        available) echo "     Unsloth ready ✓" ;;
        partial-no-unsloth)
            echo -e "${YELLOW}     PyTorch/Transformers OK, Unsloth not installed${NC}"
            echo -e "${YELLOW}     Install: pip install unsloth${NC}"
            ;;
        missing-deps)
            echo -e "${YELLOW}     Missing ML dependencies${NC}"
            echo -e "${YELLOW}     Install: pip install unsloth torch transformers datasets trl${NC}"
            ;;
    esac

    # Phase 3: Train
    echo -e "${CYAN}  [3/5] Fine-tuning...${NC}"
    echo "     Base model: $model"
    echo "     Samples: $(wc -l < "$tmp_dir/dataset/dataset.jsonl" 2>/dev/null || echo 0)"
    if [[ "$us" == "available" ]]; then
        _train_model "$tmp_dir/dataset/dataset.jsonl" "$model" "$tmp_dir/finetuned"
    else
        echo -e "${YELLOW}     Skipping training — Unsloth not available${NC}"
        echo "     Dataset saved for later use: $tmp_dir/dataset/dataset.jsonl"
        mkdir -p "$tmp_dir/finetuned"
    fi

    # Phase 4: Verify
    echo -e "${CYAN}  [4/5] Export check...${NC}"
    if [[ -d "$tmp_dir/finetuned/gguf" ]] && ls "$tmp_dir/finetuned/gguf"/*.gguf &>/dev/null 2>/dev/null; then
        echo "     GGUF: $(ls "$tmp_dir/finetuned/gguf"/*.gguf)"
    else
        echo -e "${YELLOW}     No GGUF export (expected until Unsloth is installed)${NC}"
        echo "     Adapter weights: $tmp_dir/finetuned/"
    fi

    # Phase 5: Import
    echo -e "${CYAN}  [5/5] Ollama import...${NC}"
    _import_ollama "$tmp_dir/finetuned/gguf" "$tag"

    # Summary
    echo ""
    echo -e "${GREEN}═══ TRAINING SUMMARY ═══${NC}"
    echo "  Dataset:   $(wc -l < "$tmp_dir/dataset/dataset.jsonl" 2>/dev/null || echo 0) samples"
    echo "  Base:      $model"
    echo "  Tag:       $tag"
    echo "  Output:    $tmp_dir/finetuned/"
    echo ""
    echo -e "${YELLOW}  Next: CODER_MODEL=$tag ./SIC_Skip.sh \"Find social media for John Doe\"${NC}"
    echo -e "${YELLOW}  Or:   export CODER_MODEL=$tag && ./SIC_Skip.sh \"...\"${NC}"
}

sic_run "$@"
