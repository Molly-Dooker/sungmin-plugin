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
    +-- skills/<name>/references/*.md   (필요할 때만 읽는 세부 문서)
    +-- hooks/hooks.json, hooks/session-start.sh   (Claude Code SessionStart hook)
```

## skills

| skill | 내용 |
|---|---|
| `work-principles` | 모든 작업의 공통 원칙, 문서·기록 작성, subagent 위임 |
| `a0-bringup` | A0 브링업 입구(시작 순서, 정본 위치, 공통 운영 규칙). `references/run.md` run 실행, `references/watcher.md` 운영·감시, `references/change-gate.md` aviron-skills 변경 관문 |
| `aviron-transformers` | aviron-transformers 작업 입구 |

`work-principles`는 Claude Code에서 SessionStart hook(`hooks/session-start.sh`)이 세션 시작 때마다 본문과 작업별 skill 안내를 context에 넣는다. 그래서 따로 부르지 않아도 항상 적용된다. `a0-bringup`·`aviron-transformers`는 길어서 skill로 두고, 해당 작업을 지시하면 description으로 자동 선택된다. `/sungmin:<skill>`로 부르면 그 skill의 절차(예: "시작할 때")를 바로 실행한다.

작성 규칙:

- sungmin 문서는 상대 링크 대신 "sungmin 저장소 기준 경로"(`aviron-skills/…`)로 적는다. 플러그인 안 링크는 `references/<file>.md`, `../SKILL.md`처럼 상대 경로로 쓴다.
- `description`에 적용 시점을 적어 skill이 자동으로 선택되게 한다.
- 서버 이름과 절대 경로는 skill 본문에 적지 않는다. A0 경로는 `a0-bringup/SKILL.md` "환경 값" 표에만 기본값으로 두고, 본문 명령은 변수(`$REPO` 등)로 쓴다.
- 같은 규칙은 한 곳에만 둔다. 공통 원칙은 `work-principles`, A0 공통 운영 규칙은 `a0-bringup/SKILL.md`다.
- 버전 이력("0.NN부터", 옛 이름·경로)은 skill에 적지 않고 sungmin `aviron-skills/history.md`·`rounds/`에 둔다.
- 문서 지도, 차수·단계 폴더 규칙, 기록 규칙, 옛 이름 대조처럼 문서 자체에 대한 규칙은 sungmin 각 폴더의 `AGENTS.md`에 둔다. 서버별 접속·경로·환경처럼 서버마다 바뀌는 사실은 sungmin `aviron-skills/startingpoint.md` "서버" 표에 둔다. 운영 명령(상태 보기·멈추기·인증·참조·백업)은 `a0-bringup/references/run.md`에 둔다.

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
