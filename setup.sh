#!/bin/bash
# One-command prerequisite install for this repo (macOS or Linux).
# Installs Podman + podman-compose, Ollama, the Cline VS Code extension,
# and pulls a coding model. Safe to re-run; already-installed pieces are skipped.
#
# Usage: ./setup.sh
#  ./se  # pick a model from a menu (up/down + Enter)
#   OLLAMA_MODEL=qwen2.5-coder:14b ./setup.sh   # skip the menu, use this model
#   SKIP_MODEL=1 ./setup.sh                     # don't pull a model
#   SKIP_CLINE=1 ./setup.sh                     # don't install the VS Code extension

set -euo pipefail

cd "$(dirname "$0")"

OLLAMA_MODEL="${OLLAMA_MODEL:-}"
CLINE_EXTENSION="saoudrizwan.claude-dev"

have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS=mac
elif [[ "$OSTYPE" == "linux"* ]]; then
    OS=linux
else
    echo "Unsupported OS: $OSTYPE" >&2
    exit 1
fi

SUDO=""
if [[ "$OS" == "linux" && $EUID -ne 0 ]]; then
    have sudo || { echo "sudo is required to install packages." >&2; exit 1; }
    SUDO="sudo"
fi

# --- Hardware detection + model choice -----------------------------------------
# Approximate download sizes (GB) at Ollama's default 4-bit quantization.
MODEL_NAMES=("qwen2.5-coder:3b" "qwen2.5-coder:7b" "qwen2.5-coder:14b" "qwen3-coder:30b")
MODEL_SIZES=(2 5 9 19)
MODEL_NOTES=("tiny, weak tool calling" "light, okay tool calling" "solid tool calling" "best quality, needs a big machine")

detect_hardware() {
    GPU_NAME=""
    VRAM_GB=0
    if [[ "$OS" == "mac" ]]; then
        RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
        CPU_CORES=$(sysctl -n hw.ncpu)
        CPU_NAME=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
        if [[ "$(uname -m)" == "arm64" ]]; then
            GPU_NAME="Apple GPU (unified memory)"
            VRAM_GB=$RAM_GB   # unified memory is shared with the GPU
        fi
    else
        RAM_GB=$(awk '/MemTotal/ {printf "%d", $2 / 1024 / 1024 + 0.5}' /proc/meminfo)
        CPU_CORES=$(nproc)
        CPU_NAME=$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo)
        if have nvidia-smi; then
            local mib
            mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | sort -rn | head -n1 || true)
            if [[ -n "$mib" ]]; then
                VRAM_GB=$(( mib / 1024 ))
                GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
            fi
        fi
    fi
    # Memory the model can realistically use: a big dedicated GPU, else system RAM.
    if (( VRAM_GB >= 8 )); then USABLE_GB=$VRAM_GB; else USABLE_GB=$RAM_GB; fi
}

recommend_index() {
    if   (( USABLE_GB < 10 )); then echo 0
    elif (( USABLE_GB < 16 )); then echo 1
    elif (( USABLE_GB < 32 )); then echo 2
    else echo 3
    fi
}

# Arrow-key menu. Sets MENU_CHOICE to the chosen index. Reads from the terminal.
menu_select() {
    local cur=$1 count=${#MENU_LABELS[@]} key rest action i
    printf '\033[?25l'                       # hide cursor
    while true; do
        for ((i = 0; i < count; i++)); do
            if (( i == cur )); then
                printf '  \033[7m> %s\033[0m\033[K\n' "${MENU_LABELS[i]}"
            else
                printf '    %s\033[K\n' "${MENU_LABELS[i]}"
            fi
        done
        IFS= read -rsn1 key </dev/tty || { printf '\033[?25h'; return 1; }
        action=""
        case "$key" in
            $'\033')
                rest=""
                read -rsn2 -t 1 rest </dev/tty || true
                case "$rest" in
                    '[A') action=up ;;
                    '[B') action=down ;;
                esac ;;
            k) action=up ;;
            j) action=down ;;
            '') action=enter ;;
        esac
        case "$action" in
            up)    cur=$(( (cur + count - 1) % count )) ;;
            down)  cur=$(( (cur + 1) % count )) ;;
            enter) MENU_CHOICE=$cur; printf '\033[?25h'; return 0 ;;
        esac
        printf '\033[%dA' "$count"           # move back up to redraw
    done
}

choose_model() {
    detect_hardware
    local rec i label
    rec=$(recommend_index)

    echo "==> Your machine"
    echo "    CPU:    $CPU_NAME ($CPU_CORES cores)"
    echo "    Memory: ${RAM_GB} GB RAM"
    [[ -n "$GPU_NAME" ]] && echo "    GPU:    $GPU_NAME${VRAM_GB:+ (${VRAM_GB} GB)}"
    echo "    Suggested model: ${MODEL_NAMES[rec]}"
    echo

    if [[ -n "$OLLAMA_MODEL" ]]; then
        echo "==> Using OLLAMA_MODEL=$OLLAMA_MODEL"
        return
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
        OLLAMA_MODEL="${MODEL_NAMES[rec]}"
        echo "==> Not a terminal; using suggested model $OLLAMA_MODEL"
        return
    fi

    MENU_LABELS=()
    for ((i = 0; i < ${#MODEL_NAMES[@]}; i++)); do
        label=$(printf '%-20s ~%2d GB  %s' "${MODEL_NAMES[i]}" "${MODEL_SIZES[i]}" "${MODEL_NOTES[i]}")
        (( i == rec )) && label+="  [suggested]"
        (( MODEL_SIZES[i] + 3 > USABLE_GB )) && label+="  [likely too large]"
        MENU_LABELS+=("$label")
    done
    MENU_LABELS+=("Other (type a model name)")
    MENU_LABELS+=("Skip (don't pull a model)")

    echo "Select a model (Up/Down to move, Enter to confirm):"
    menu_select "$rec"
    local n=${#MODEL_NAMES[@]}
    if (( MENU_CHOICE < n )); then
        OLLAMA_MODEL="${MODEL_NAMES[MENU_CHOICE]}"
    elif (( MENU_CHOICE == n )); then
        read -rp "Model name (e.g. llama3.1:8b): " OLLAMA_MODEL </dev/tty
        [[ -n "$OLLAMA_MODEL" ]] || SKIP_MODEL=1
    else
        SKIP_MODEL=1
    fi
    echo
}

if [[ -z "${SKIP_MODEL:-}" ]]; then
    choose_model
fi

# --- Podman + podman-compose -------------------------------------------------
install_podman_mac() {
    have brew || { echo "Homebrew is required: https://brew.sh" >&2; exit 1; }
    brew update
    brew install podman podman-compose

    if ! podman machine list --format "{{.Name}}" 2>/dev/null | grep -q .; then
        echo "==> Creating Podman machine..."
        podman machine init --cpus 4 --memory 4096 --disk-size 60
    fi
    if ! podman machine list --format "{{.Running}}" | grep -q true; then
        echo "==> Starting Podman machine..."
        podman machine start
    fi
}

install_podman_linux() {
    if have dnf; then
        $SUDO dnf install -y podman podman-compose curl
    elif have apt-get; then
        $SUDO apt-get update
        $SUDO apt-get install -y podman podman-compose curl
    else
        echo "No supported package manager found (need dnf or apt-get)." >&2
        echo "Install podman and podman-compose manually, then re-run." >&2
        exit 1
    fi
}

echo "==> Podman"
if have podman && have podman-compose; then
    echo "    already installed."
    [[ "$OS" == "mac" ]] && install_podman_mac   # still ensures the VM exists/runs
else
    "install_podman_$OS"
fi

# --- Ollama ------------------------------------------------------------------
echo "==> Ollama"
if have ollama; then
    echo "    already installed ($(ollama --version 2>&1 | tail -n1))."
elif [[ "$OS" == "mac" ]]; then
    brew install ollama
else
    # Official installer from ollama.com; it also sets up the systemd service.
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Make sure the Ollama server is reachable before pulling a model.
start_ollama() {
    curl -s -o /dev/null http://localhost:11434 && return 0
    if [[ "$OS" == "mac" ]]; then
        brew services start ollama >/dev/null
    elif have systemctl && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
        $SUDO systemctl enable --now ollama
    else
        nohup ollama serve >/dev/null 2>&1 &
    fi
    for _ in $(seq 1 30); do
        curl -s -o /dev/null http://localhost:11434 && return 0
        sleep 1
    done
    return 1
}

# --- Model -------------------------------------------------------------------
if [[ -z "${SKIP_MODEL:-}" ]]; then
    echo "==> Model: $OLLAMA_MODEL (large download)"
    if start_ollama; then
        ollama pull "$OLLAMA_MODEL"
    else
        echo "    Ollama did not start; skipping model pull. Run: ollama pull $OLLAMA_MODEL" >&2
    fi
fi

# --- Cline -------------------------------------------------------------------
if [[ -z "${SKIP_CLINE:-}" ]]; then
    echo "==> Cline (VS Code extension)"
    if have code; then
        code --install-extension "$CLINE_EXTENSION"
    else
        echo "    'code' CLI not found; install Cline manually from the VS Code Extensions view."
    fi
fi

cat <<EOF

==> Setup complete.
Next steps:
  1. ./start.sh        # starts SearXNG and Open WebUI
  2. Configure Cline (see README.md, section 4) to use Ollama at http://localhost:11434
EOF
