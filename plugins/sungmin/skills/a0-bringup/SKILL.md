---
name: a0-bringup
description: BOS N1 A0 모델 브링업(aviron-skills, aviron-model-bringup 플러그인) 작업 지침. 작업 시작(현재 기준 요약), A0 run 실행(시작 전 확인·dry-run·시작·재개·serving), run 운영·감시(watcher), aviron-skills 플러그인의 지침·checker·runtime·러너 변경(검토사항·개선안·구현), 차수 문서 작업, 스마트 플러그(plugon·plugoff·plugstatus)로 myA0 보드 전원 확인·조작, myA0 장치 hang 복구(보드 전원 껐다 켜기·재부팅) 전에 적용한다.
---

# A0 모델 브링업

BOS N1 A0 단일 장치에서 HF 모델을 에이전트(LangGraph 러너; stage 에이전트는 launch마다 `deepagents`·`codex`·`claude` 가운데 고른다)로 bring-up하는 작업의 입구다.

운영 문서와 기록은 문서 저장소 sungmin의 `aviron-skills/`에 있다. 그 폴더의 `AGENTS.md`가 문서 지도, 차수 폴더 규칙, 기록 규칙, 옛 이름·branch → tag 대조를 정한다. 이 skill과 `references/`의 `aviron-skills/…` 경로는 sungmin 저장소 기준이다.

## 시작할 때

`aviron-skills/AGENTS.md`, `aviron-skills/TODO.md`, 지금 차수 `aviron-skills/rounds/0NN/README.md`를 읽는다. 현재 기준(skills develop commit, tt-metal commit, 서버·run 상태)과 남은 할 일을 먼저 요약한다.

**lean 파이프라인은 보류 중이다(11-25 사용자 지시).** 코드는 `bos-semi/aviron-skills` branch `lean-experimental`(`bos-semi/skills` `develop` `fcea958`의 사본), 문서와 기록은 sungmin `lean-skills/`에 있다. 사용자가 다시 꺼내기 전까지는 읽지도, 고치지도, run하지도 않고 다른 작업의 판단에도 넣지 않는다(aviron-skills 작업에서 "lean과 비교" 같은 제안도 하지 않는다). 다시 시작하면 `lean-skills/AGENTS.md`(재개 순서, lean 변경 기준)부터 읽는다.

## 작업별 문서

| 작업 | 읽을 문서 |
|---|---|
| run 실행(HF 참조, 시작 전 확인, dry-run, 시작, 상태 보기, 재개, 멈추기, 인증, serving, 백업). 별도 지시가 없으면 이 방식으로 돌린다 | [references/run.md](references/run.md) |
| run 운영·감시(watcher), 자동 hang 복구(`run_control.py watch`) | [references/watcher.md](references/watcher.md) |
| skills 플러그인의 지침·checker·runtime·러너 변경(검토사항·개선안·구현). 운영 문서만 고치는 일은 제외 | [references/change-gate.md](references/change-gate.md) |
| 보드 전원: 스마트 플러그 명령(`plugstatus`·`plugon`·`plugoff`), myA0 장치 hang 때 전원 껐다 켜기·재부팅, sudo 설정 | [references/power.md](references/power.md) |
| 서버별 접속·경로·환경 | sungmin `aviron-skills/startingpoint.md` "서버" |

## 환경 값

이 skill과 `references/`의 명령은 아래 변수로 경로를 적는다. 값은 실행 서버 기준이다. 서버별 값은 sungmin `aviron-skills/startingpoint.md` "서버" 표에서 확인한다.

| 변수 | 뜻 | 기본값 |
|---|---|---|
| `REPO` | aviron-skills, aviron-transformers, tt-metal-e2, vllm, vllm-aviron-plugin, python_env가 있는 폴더 | `/home/bos/repo` |
| `CODEX_HOME` | run 전용 Codex home(`codex` 러너만) | `/home/bos/.codex2` |
| `CODEX_BIN` | 실제 codex 바이너리(`codex` 러너만) | `/home/bos/.local/bin/codex` |
| `WORK_ROOT` | run 작업 폴더의 상위 폴더 | `/home/bos/bt_work` |
| `LIMITWATCH` | 리셋권 감시 상태 폴더(`codex` 러너만) | `/home/bos/a0_limitwatch_r0NN` |
| `BACKUP` | 산출물 백업 폴더 | `/home/bos/_backup` |

## 정본 위치

- 문서와 기록은 host sungmin에 쓴다. 코드 작업과 commit·push는 별도 지시가 없으면 실행 서버 `$REPO` 안의 저장소에서 직접 한다(11-04 사용자 지시). skills는 `$REPO/aviron-skills`, 참조 aviron-transformers clone은 `$REPO/aviron-transformers`, tt-metal-e2는 `$REPO/tt-metal-e2`다.
- skills 플러그인은 `aviron-model-bringup`(`bos-semi/aviron-skills`, plugin ID `aviron-model-bringup@aviron-skills`)이다. version `0.NN.x` = 차수 `0NN`이다. 저장소의 작업 branch는 `develop` 하나이고(보류 중인 lean의 `lean-experimental`은 무시한다) 버전은 tag `vX.Y.Z`로 구분한다. 지금 `develop`·tag·차수는 `aviron-skills/TODO.md`에, 옛 플러그인(`tt-model-bringup-a0`)과 branch 이력은 `aviron-skills/history.md`와 `aviron-skills/rounds/_legacy/`에 있다.
- skills 수정·시험·commit은 별도 clone이 아니라 실행 clone `$REPO/aviron-skills`에서 직접 한다(11-10 사용자). run 지침 변경은 `aviron-model-bringup` 플러그인에서만 한다.
- **러너는 launch마다 고른다:** 한 tree(`develop`)가 모든 러너를 돌린다. `run_bringup --runner deepagents|codex|claude`(`claude`는 0.54.0부터)나 `AVIRON_BRINGUP_RUNNER`로 고르고, 기본값이 없어 빠지면 시작하지 않는다(exit 2). `deepagents`는 Deep Agents stage 에이전트가 모델 API를 직접 부르고(모델 이름이 `claude-…`면 Anthropic API와 `ANTHROPIC_API_KEY`, 아니면 OpenAI와 `OPENAI_API_KEY`), `codex`는 Codex app-server goal이다(`CODEX_BIN`, Codex home). 사용자가 러너를 말하지 않았으면 묻는다. 러너를 바꾸려고 branch를 바꾸지 않는다. 러너별 입력·확인·멈추기·인증은 [references/run.md](references/run.md) "러너 선택"에 있다.
- **run 환경:** tt-metal-e2 checkout 하나(`$REPO/tt-metal-e2`, Python 3.12, DRAM 정렬 ON으로 빌드)와 uv 가상환경 하나(`$REPO/python_env`, Python 3.12)를 두 러너가 함께 쓴다. 구축·재빌드 주의점은 [references/run.md](references/run.md) "run 환경"과 skills 루트 README "Build the run Python environment"에 있다.
- 참조 aviron-transformers는 skills submodule이 아니라 run 환경 `python_env`에 설치한 package `tt_transformers`다. skills의 pin commit에 checkout한 clone에서 non-editable `--no-deps`로 설치하고, 러너가 설치된 파일 hash를 pin과 대조한다(다르면 launch 전에 error). 구축 절차는 skills 루트 README "Build the run Python environment"에 있다. 참조 코드를 고치면 clone에서 commit하고 skills의 `PIN`·`PIN_SOURCE_HASH`와 설치를 새 commit에 맞춘다.
- tt-metal-e2의 run 산출물은 `bringup/`, autoport는 `models/autoports/`이고 둘 다 git 추적 밖이다. autoport 안 운영자 개입 기록은 autoport `doc/INTERVENTIONS.md`가 원본이다. tt-metal-e2 B2B 브랜치는 갱신하지 않는다.

## 공통 운영 규칙

run 실행·감시·skills 변경에 모두 적용한다.

- **run 중 실행 clone 고정:** run이 도는 동안에는 실행 clone을 고치거나 origin에서 `git pull`하지 않는다. 러너가 stage check마다 plugin tree를 시작 때와 비교해, 다르면 check 없이 멈춘다(`plugin-modified`). 재현은 실행 clone 밖의 임시 사본에서 한다.
- **장치 안전:** 장치 명령이 도는 중에는 러너를 멈추지 않는다. 장치 정지 절차는 [references/run.md](references/run.md) "멈추기"에 있다. 장치가 hang돼 더 쓸 수 없으면 myA0는 사용자 확인 뒤 [references/power.md](references/power.md) 절차(plugoff → 5초 → plugon → 5초 → `sudo reboot`)로 복구하고(사용자가 켠 `run_control.py watch`와 aviron-kernel-bringup 러너는 확인 없이 run당 3회까지 스스로 한다, 11-25 사용자 결정), 다른 서버는 사용자에게 재부팅을 요청한다.
- **운영자 메모:** `LAUNCH_NOTE`는 사용자가 지시하거나 허락할 때만 쓴다(300차 사용자 지시). 한 번 넣으면 그 뒤 모든 stage와 재개 objective에 붙고, 뗄 방법이 없다.
- **산출물:** 기존 산출물은 `$BACKUP`에 불투명 이름(`a0bk_<시각>_<순번>.tgz`)으로 압축해 둔다. 끝난 run의 autoport는 측정 원자료(Tracy·profile CSV·텐서)를 빼고 압축·대조한 뒤 원본을 지운다([references/run.md](references/run.md) "산출물 백업"). 그 밖의 데이터 삭제와 skills·plugin push는 사용자 확인을 받는다.
- **commit 메시지:** skills commit은 영어로 `aviron-model-bringup <version>: …` 형식을 쓴다.
