---
name: work-principles
description: 모든 작업(코드 수정, 조사, 빌드·검증, 문서, 서버 작업)을 시작할 때 먼저 적용하는 공통 원칙과 작업별 skill 안내. 저장소 확인, 변경 범위, commit·push 규칙, 샌드박스 미사용, 검증·보고 방식을 정한다.
---

# 작업 공통 원칙

모든 작업에 적용한다. 작업 종류에 맞는 skill이 아래 목록에 있으면 시작 전에 함께 읽는다. 저장소에 `AGENTS.md`·`CLAUDE.md`가 있으면 그 저장소 지침을 함께 따르고, 둘이 다르면 저장소 지침을 우선한다.

## 기본 원칙

- 사용자 요청과 현재 저장소 상태를 먼저 확인하고, 추측하지 않는다.
- 관련 구현·호출부·테스트를 읽고 기존 방식에 맞춰 필요한 범위만 변경한다.
- 다른 작업자의 변경을 덮어쓰지 않는다. 브랜치, commit, PR은 요청 없이 만들지 않는다.
- 작업 경로는 PC·계정에 따라 달라질 수 있으므로 특정 절대 경로로 제한하지 않는다. 사용자가 지정한 현재 checkout을 사용하고, `git rev-parse --show-toplevel`과 remote로 대상 저장소를 확인한다.
- commit·push가 요청되거나 작업별 지침으로 허용된 경우, 현재 checkout이 `main`인지 확인하고 그곳에서 직접 수행한다. worktree(`EnterWorktree`)나 별도 브랜치를 만들지 않는다. 현재 checkout의 실제 권한·편집 제한이 작업을 막으면 우회하지 말고 사용자에게 알린다. 다른 PC의 경로에 접근할 수 없다는 이유만으로 작업을 중단하지 않는다.
- 모든 작업은 기본적으로 샌드박스를 사용하지 않고 디바이스에서 직접 실행한다. 필요하면 `ssh`·`docker exec` 등으로 대상 디바이스에서 실행한다.
- 변경 후 관련 검증을 실행하고, 실행하지 못한 항목과 실패를 명확히 보고한다.
- 설명과 문서는 별도 지정이 없으면 한글로 작성한다.

## 작업별 skill

해당 작업을 시작하기 전에 관련 skill을 읽는다.

| 작업 | skill |
|---|---|
| 모든 작업의 기록과 문서 | `documentation` |
| Jira 조회 | `jira-access` |
| subagent 사용 | `subagent` |
| aviron-skills 플러그인의 지침·checker·runtime·러너 변경(검토사항·개선안·구현) | `skills-change-gate` |
| A0 모델 브링업(aviron-skills, AISW-1580) 작업 시작 | `a0-bringup` |
| A0 run 실행(시작 전 확인, dry-run, 시작, 재개, serving) | `a0-clone-run` |
| A0 run 운영·감시(watcher) | `bringup-watcher` |
| aviron-transformers(e2 도입·A0 모델 뼈대) 작업 시작 | `aviron-transformers` |

문서 저장소 sungmin(myA0 `/home/bos/repo/sungmin`)의 `AGENTS.md`들은 문서 트리와 작성 규칙만 정한다. 그 저장소 문서를 읽거나 쓸 때 함께 따른다.
