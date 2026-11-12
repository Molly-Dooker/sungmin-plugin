#!/usr/bin/env bash
# SessionStart hook: print work-principles (without frontmatter) and the task routing lines.
# Claude Code adds this stdout to the session context.
set -euo pipefail

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
skill="$root/skills/work-principles/SKILL.md"

echo "# sungmin-plugin: 세션 시작 지침"
echo
echo "아래 작업 공통 원칙은 이 세션의 모든 작업에 적용한다(sungmin-plugin work-principles, 세션 시작 때 자동으로 넣음)."
echo
echo "작업별 skill: 해당 작업을 시작하기 전에 그 skill을 먼저 읽는다."
echo "- A0 모델 브링업(aviron-skills, aviron-model-bringup 플러그인, run 실행·감시, skills 변경, 차수 문서) -> sungmin:a0-bringup"
echo "- aviron-transformers(tt-metal-e2 도입, A0 모델 뼈대, 관련 커널·binding) -> sungmin:aviron-transformers"
echo

if [ -f "$skill" ]; then
  # drop the YAML frontmatter (first --- ... --- block)
  awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$skill"
else
  echo "(work-principles SKILL.md를 찾지 못했다: $skill)"
fi
