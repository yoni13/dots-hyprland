#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try fastflowlm (qwen3vl-it:4b) for OCR if the server is reachable
if curl -sf --max-time 2 http://localhost:52625/v1/models >/dev/null 2>&1; then
    image_path="$1"
    image_b64=$(base64 -w0 "$image_path" 2>/dev/null)
    if [ -n "$image_b64" ]; then
        response=$(curl -s http://localhost:52625/v1/chat/completions \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg model "qwen3vl-it:4b" \
                --arg b64 "$image_b64" \
                '{
                    model: $model,
                    messages: [{
                        role: "user",
                        content: [
                            {type: "text", text: "Please perform OCR on this image. Return only the extracted text, without any commentary or explanation."},
                            {type: "image_url", image_url: {url: ("data:image/png;base64," + $b64)}}
                        ]
                    }],
                    stream: false
                }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)
        if [ -n "$response" ]; then
            echo "$response"
            exit 0
        fi
    fi
fi

# Fallback: easyOCR via Python venv
source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate"
"$SCRIPT_DIR/ocr.py" "$@"
deactivate
