#!/usr/bin/env zsh
set -euo pipefail

GEMINI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai/"
ZSH_RC="$HOME/.zshrc"

echo "=================================================="
echo "  Freebuff CLI - Zsh Gemini BYOK Setup"
echo "=================================================="
echo ""

# 1. Prompt securely for the Gemini API Key
read -rs "GEMINI_KEY?1) Paste your Google Gemini API Key (AIza...): "
echo ""

if [[ -z "$GEMINI_KEY" ]]; then
  echo "❌ Error: API key cannot be empty."
  exit 1
fi

# 2. Validate API Key against Google's OpenAI-compatible endpoint
echo ""
echo "⏳ Verifying Gemini API key..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${GEMINI_KEY}" \
  "${GEMINI_BASE_URL}models")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "❌ API key verification failed (HTTP $HTTP_STATUS). Check your key and try again."
  exit 1
fi
echo "✅ API key verified!"

# 3. Ensure freebuff CLI is installed
if ! command -v freebuff >/dev/null 2>&1; then
  echo "⏳ 'freebuff' not found in PATH. Installing freebuff@latest..."
  npm install -g freebuff@latest
fi

# 4. Clean up any old block in ~/.bashrc if it was created earlier
if [[ -f "$HOME/.bashrc" ]]; then
  sed -i.bak '/# >>> freebuff-gemini-setup >>>/,/# <<< freebuff-gemini-setup <<</d' "$HOME/.bashrc" && rm -f "$HOME/.bashrc.bak"
fi

# 5. Add GEMINI_API_KEY cleanly to ~/.zshrc
touch "$ZSH_RC"
sed -i.bak '/# >>> freebuff-gemini-setup >>>/,/# <<< freebuff-gemini-setup <<</d' "$ZSH_RC" && rm -f "${ZSH_RC}.bak"

cat >> "$ZSH_RC" <<EOT

# >>> freebuff-gemini-setup >>>
export GEMINI_API_KEY="${GEMINI_KEY}"
# <<< freebuff-gemini-setup <<<
EOT

echo "✅ Saved GEMINI_API_KEY to $ZSH_RC"
echo ""
echo "=================================================="
echo "🎉 Shell setup complete! Run this command next:"
echo "   source ~/.zshrc && freebuff"
echo "=================================================="
