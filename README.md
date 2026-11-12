# sungmin-plugin

sungmin 저장소(문서 저장소)에 있던 개인 작업 지침을 모두 옮긴 Claude Code·Codex 공용 플러그인 marketplace다. sungmin에는 문서 트리와 작성 규칙(`AGENTS.md`)만 남긴다.

```text
sungmin-plugin/
+-- .claude-plugin/marketplace.json   (Claude Code marketplace)
+-- .agents/plugins/marketplace.json  (Codex marketplace)
+-- plugins/sungmin/
    +-- .claude-plugin/plugin.json
    +-- .codex-plugin/plugin.json
    +-- skills/<name>/SKILL.md
```

## skills

| skill | 내용 | 원본 |
|---|---|---|
| `work-principles` | 모든 작업의 공통 원칙과 작업별 skill 안내 | `AGENTS.md`의 기본 원칙·작업별 지침 |
| `documentation` | 기록·문서 작성 공통 지침 | `.agents/skills/documentation` |
| `compiler` | 컴파일러 수정·빌드·검증 | `.agents/skills/compiler` |
| `jira-access` | Jira 읽기 전용 조회 | `.agents/skills/jira-access` |
| `subagent` | subagent 위임 원칙 | `.agents/skills/subagent` |
| `claude-debate` | Codex 기준 Claude CLI와 토론·합의 | `.agents/skills/claude-debate` |
| `skills-change-gate` | aviron-skills 변경 관문 | `.agents/skills/skills-change-gate` |
| `a0-bringup` | A0 브링업 입구: 시작 순서, 정본 위치, 역할별 skill | 루트 `AGENTS.md` A0 항목, `aviron-skills/AGENTS.md` 역할별 지침·정본 위치 |
| `a0-clone-run` | A0 run 실행 방식 | `aviron-skills/.agents/skills/a0-clone-run` |
| `bringup-watcher` | A0 run 운영·감시 판단 규칙 | `aviron-skills/.agents/skills/bringup-watcher` |
| `aviron-transformers` | aviron-transformers 작업 입구 | 루트 `AGENTS.md` 항목, `aviron-transformers/AGENTS.md` 정본 위치·장치·commit 규칙 |

옮기면서 바꾼 점:

- 원본의 sungmin 문서 상대 링크는 플러그인 안에서 깨지므로 "sungmin 저장소 기준 경로"(`aviron-skills/…`, `_docs/compiler/…`) 표기로 바꿨다. skill 사이 링크(`../<skill>/SKILL.md`)는 그대로 쓴다.
- skill이 자동으로 선택되도록 `description`에 적용 시점을 덧붙였다.
- 문서 지도, 차수·단계 폴더 규칙, 기록 규칙, 옛 이름 대조처럼 문서 자체에 대한 규칙은 sungmin 각 폴더의 `AGENTS.md`에 남겼다. `aviron-skills/startingpoint.md`(상태 보기·멈추기·인증·참조·백업 명령)도 운영 문서로 sungmin에 둔다.

## 설치

Claude Code:

```bash
claude plugin marketplace add <이 저장소의 GitHub 경로 또는 local 경로>
claude plugin install sungmin@sungmin-plugin
```

Codex:

```bash
codex plugin marketplace add <이 저장소의 GitHub 경로 또는 local 경로>
codex plugin add sungmin@sungmin-plugin
```

설치 뒤 Claude Code에서는 `sungmin:<skill>`(예: `/sungmin:work-principles`)로 직접 부를 수 있다.

## 버전

두 `plugin.json`의 `version`을 함께 올린다.
