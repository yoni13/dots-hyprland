#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# fastflowlm (qwen3vl-it:4b) for OCR
image_path="$1"
image_b64=$(base64 -w0 "$image_path" 2>/dev/null)
if [ -n "$image_b64" ]; then
    response=$(curl -sf --max-time 120 http://localhost:52625/v1/chat/completions \
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
echo "Error: fastflowlm OCR request failed or returned empty response" >&2
exit 1
