# run 운영·감시(watcher)

watcher는 runner(`scripts/run_bringup`, LangGraph 러너 `graph_controller.py`, stage 0~7)가 Stage를 끝까지 돌게 만드는 운영자다. **장치 정지가 아니면 run을 멈추지 않는다.** 그 밖의 문제는 원인을 고치거나 우회해 같은 run을 이어 간다. 운영 결정은 사용자에게 묻지 않고 권장안을 실행한 뒤 기록하고 보고한다.

- 실행 명령(시작 전 확인, dry-run, 시작, 재개)은 [run.md](run.md), 공통 운영 규칙은 [../SKILL.md](../SKILL.md), 상태 보기·멈추기·인증도 [run.md](run.md)에 있다. 이 문서는 언제 무엇을 할지만 정한다.
- 실행 장비와 시험 장비는 그때 사용할 수 있는 것으로 정한다. 작업 프롬프트나 `aviron-skills/TODO.md`에 적힌 대로 따르고, 이 문서에서는 고정하지 않는다.
- Stage 작업 자체는 runner의 에이전트가 한다. watcher는 goal 안의 작업을 대신하지 않는다.

## 멈추는 경우

아래 장치 정지 신호가 있을 때만 멈춘다.

- wrapper exit 126(`stop-device-work`)
- mesh close 미확인(UMD open이 close보다 많음)
- wrapper deadline 종료. 단 장치를 한 번도 열지 않은 명령의 deadline은 exit 124 `host-deadline`(아래 표)이고 멈추지 않는다
- 명령 뒤 `/dev/bos/*` holder가 남음

이때는 아래를 지킨다.

- 장치를 다시 열지 않는다. verifier도 포함한다.
- log, 구조화 기록, PID, holder를 보존한다.
- 사용자에게 알린다.
- 사용자가 승인하면 verifier를 1회 돌린다. 통과하면 `.ack`를 쓰고 같은 run을 재개한다([run.md](run.md) "멈추기"·"재개").

사용자 확인이 필요한 일은 skills·plugin push와 데이터 삭제다. 확인을 기다리는 동안에도 run은 local commit으로 계속 돌린다.

그 밖의 문제는 멈출 이유가 아니다. checker 오류, runner 정지, 에이전트의 질문, Codex 과부하, 패키지·참조·인증 같은 환경 문제가 여기에 해당한다. "사용자 선택을 기다림" 같은 대기 분기도 만들지 않는다. 후보 승인을 묻지 않는 것이 그 예다(아래 "끝나면").

## 준비

[run.md](run.md)의 "시작 전 확인", "dry-run", "시작"을 그대로 거친다. watcher가 더 하는 일은 아래다.

1. 기준을 적는다. skills commit(origin과 같은지), tt-metal commit, serving stack manifest, 실행 설정(Codex home, 실행·리뷰 모델, 플러그인 모드, 자동 checker 수정 끔, HF offline·local only).
2. 사용자가 `LAUNCH_NOTE`를 쓰라고 할 때만 넣는다. 그때 담는 내용은 아래와 같다.
   - 기준
   - 이번 결정
   - 이미 반영된 것: 에이전트가 같은 질문을 다시 하지 않게
   - 운영 결정 규칙: 지침 범위 안의 판단은 권장안으로 진행하고, 사용자 결정을 기다리며 goal을 blocked로 닫지 않는다
   - 장치 안전
   - 금지 사항: commit·push, 원격 접속, 참조 재생성, reset·FLR·reboot·tt-triage·넓은 pkill, 다른 autoport 수정, skills·plugin·vLLM checkout 수정
   - 긴 장치 명령의 wrapper deadline 여유: MMLU 1,368문항은 모델 크기에 따라 30분 이상 걸린다

## 감시

- 감시 script를 건다([run.md](run.md) "감시 unit"). 아래를 한 줄씩 낸다.
  - manifest의 새 줄: Stage terminal·check·review·thread, `run_status`
  - wrapper registry의 상태 변화
  - 에이전트 메시지와 goal 상태
  - unit 상태
- 정상 wrapper와 "아직 실행 중" 같은 진행 알림은 걸러 낸다. 감시는 만료되면(30분) 다시 건다.
- 사용자에게는 의미 있는 사건만 짧게 보고한다. Stage complete(핵심 수치), 장치 정지, blocked, 결함 발견, run 종료가 여기에 해당한다.

wrapper 기록 판독:

| 기록 | 뜻 | watcher |
|---|---|---|
| exit 0, `mesh-close-confirmed` | 정상 | 없음 |
| exit ≠ 0, `host-failure-clean-close` | 명령 실패, 장치는 정상 | 에이전트가 고친다. 지켜본다 |
| `teardown=unconfirmed`, recovery 기록 UMD 0/0, holder 없음 | 장치를 열지 않은 host 명령 | 정상 |
| `disposition=profile-failed` | profile 산출물 누락(막지 않음) | 에이전트가 고친다 |
| exit 124, `classification=host-deadline`, `continue-stage` | deadline까지 끝나지 않았지만 장치를 연 적이 없다(deadline 시점 holder 없음, mesh 증거 없음, log에 UMD open 줄 없음) | 명령 실패로 본다. 에이전트가 고친다 |
| exit 126, `stop-device-work`, UMD open > close, holder 남음 | 장치 정지 | 멈춘다(위 "멈추는 경우"). 러너는 그 goal이 끝나면 terminal status를 남기고 `run_status=stop-device-work`, exit 126으로 끝난다 |

새 장치 명령을 막는 disposition은 `stop-device-work`·`incomplete`·`not-started`뿐이다.

## 복구(장치 정지가 아닐 때)

```text
event --> device stop? --yes--> stop: no reopen, preserve, notify user
             | no
             v
   +---------+-----------+--------------------+-------------------+
   |                     |                    |                   |
 Codex overload /     agent blocked:       agent blocked:      runner / env
 usage limit          question/decision    skills defect       problem
   |                     |                    |                   |
 runner auto-resume   fix cause ->         note if user allows, fix cause,
 (check it resumed)   resume with runner   fix after run; or    resume same run
                      note (no wait; note  stop -> commit ->    (runner note)
                      only if user allows) new session from stage
```

- **Codex `server_overloaded`·usage limit**: runner가 같은 thread를 자동 재개한다. 재개됐는지만 확인한다.
- **에이전트가 질문·결정 요청으로 blocked**: 권장안을 정하고, 사용자 답을 기다리지 않는다. 기본은 원인(지침·환경)을 고쳐 같은 run·Stage·thread를 메모 없이 재개하는 것이다(러너가 정지 이유를 싣는다). 고칠 수 없으면 그 Stage부터 새 세션을 시작한다. 메모는 사용자가 이미 허락했을 때만 쓴다. 그때는 active wrapper 0과 holder 0을 확인하고, unit이 살아 있으면 멈춘 뒤, 같은 run·Stage·thread를 메모와 함께 재개한다.
- **에이전트가 skills(checker·지침·runner) 결함으로 blocked**: 실행 clone은 run 중 고정이다([../SKILL.md](../SKILL.md) "공통 운영 규칙").
  - 메모로 우회할 수 있고 사용자가 메모를 허락하면 우회하고, 고치는 것은 run 뒤에 한다.
  - 꼭 고쳐야 진행되면 장치 명령이 없을 때 runner를 멈춘다. 실행 clone에 commit하고, 그 Stage부터 새 세션을 시작한다(끝난 Stage는 `--skip-stage`).
- **runner·환경 문제**(패키지, 참조, 디스크, 인증): 원인을 고치고 같은 run을 재개한다.
- **controller crash·재개 거부**: unit이 기록 없이 죽었으면 같은 `RUN_DIR`로 재개한다(checkpoint 단계부터 이어 감). `stop_reason=graph-reconcile:<node>`(exit 3)는 remediation·checker fix 중에 죽은 것이니 stage 기록을 보고 같은 stage로 재개한다. exit 1 재개 거부(schema·manifest·다른 minor version으로 시작한 run·`RESUME_STAGE`)는 메시지를 읽고 원인을 고친 뒤 띄운다. 자동으로 반복하지 않는다. 인증은 [run.md](run.md) "인증이 풀렸을 때"를 따른다.
- 같은 실패를 설정 변경 없이 되풀이시키지 않는다.
- 사용자 승인을 대신 적지 않는다(`approved_by: user` 같은 파일). 승인 없이 되는 다른 길을 찾는다.

## 기록

- 해당 차수 `2_run/<n>_<model>.md`에 날짜·시각·이유를 짧게 적는다. 진행 중 상태는 적지 않는다.
  - run 시작·정지·재개
  - skills commit
  - Stage complete(핵심 수치)
  - 운영 개입
- `aviron-skills/TODO.md`를 사건마다 갱신한다.
- run에서 나온 skills 결함과 개선점은 그 차수 `3_문제정리.md`에 쓴다(설명, 권장안과 이유, 고칠 곳). 다음 차수 `1_개선안.md`가 이것을 입력으로 받는다.

## 끝나면

1. 종료 상태를 확인한다. 마지막 `run_status`(`serving-complete` 또는 `awaiting-user-selection`), unit 결과, holder 0을 본다. 중간에 멈춘 run도 `run_status`(`stopped`+`stop_stage`+`stop_reason`, `stop-device-work`, `scope-concluded`)를 남긴다(판독은 플러그인 operator.md "Continuous run"·"What the runner does on its own").
2. run 동안 보류했던 skills 반영을 한다. 실행 clone에서 고치고 시험한 뒤 commit한다(push는 사용자 확인).
3. 보고한다.
   - Stage별 시간
   - Stage 5 6길이 TTFT/TPS
   - MMLU 대 HF(drop, paired SE)
   - serving TTFT·TPOT·ITL p50/p99·t/s/u
   - batch 4(`--max-batch 4`): Stage 5 batch 표(capacity별 TTFT·throughput), batch 4 MMLU와 batch 1 대비, Stage 6 server C(batch 검사 `batch_checks.json`·c=4 benchmark, `readiness_vllm_batch/`). server 1은 c=1(`readiness_vllm/`)이다
   - Stage 7 판정
   - 결함과 개입
4. final default를 확인한다. 후보 승인은 묻지 않는다.
   - 연속 run은 러너가 자기가 고른 후보로 직접 쓴다. manifest `final_default`를 본다(마지막 값이 `pending`이면 작성 중 멈춘 것이니 파일 상태를 보고 script로 다시 쓴다).
     - `written`: `final_approval`과 `final_default_drop_points`를 보고에 넣는다.
     - `skipped:<이유>`: 이유를 보고한다. entry Stage 4 run(`--serving-after 4`)은 MMLU가 없어 `skipped:no-quality`다.
   - report run 뒤에는 같은 script로 쓴다: `$PY $SK/scripts/final_default.py --model-dir <autoport> --handoff <handoff> --selected-by runner:<rule>`
   - script가 쓰는 것: `selected_precision_config.json`, `quality_confirmation.json`(Stage 5 MMLU 재사용, handoff validate), ledger C
   - script는 유효성(1,368문항, config·source identity, handoff)만 확인한다. MMLU drop은 정보다.

## 운영 습관

- skills를 고친 뒤에는 루트 `tests/`, plugin `tests/`, plugin `runtime/` 테스트와 `check_plugin_versions.py origin/develop`, `reference_source.py`(pin을 바꿨을 때), `claude plugin validate`(CLI가 있는 곳)를 돌린다. 장치가 필요한 검증은 그때 쓸 수 있는 시험 장비에서 bounded wrapper로 한다. 못 돌린 시험은 미실행으로 보고한다.
