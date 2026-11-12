---
name: a0-clone-run
description: A0 bring-up run을 skills 실행 clone에서 직접 돌리는 기본 실행 방식(bos-model-bringup 0.4x, stage 0~7, LangGraph 러너). 별도 지시가 없으면 이 방식으로 Stage 0→7 연속 run을 돌린다
---

# skills clone에서 직접 돌리기(기본 실행 방식)

아래 `aviron-skills/…` 경로는 문서 저장소 sungmin(myA0 `/home/bos/repo/sungmin`) 기준이다.

**별도 지시가 없으면 A0 bring-up run은 이 방식으로 돌린다.** 실행 clone의 플러그인 `bos-model-bringup`을 clone 모드로 쓴다. 러너 `scripts/run_bringup`을 user systemd unit으로 띄우고, Stage 0 → 7을 연속 run(`--serving-after 5`)으로 끝까지 돈다.

- **러너 동작의 원본:** 플러그인 `skills/model-bringup/references/operator.md`(시작, 재개, 러너가 스스로 하는 일, serving, 연속 run, 종료 기록). 이 문서는 운영 값과 작업 폴더 script만 더한다. 둘이 다르면 operator.md를 따르고 이 문서를 고친다.
- **다른 문서:** 감시·복구는 [bringup-watcher](../bringup-watcher/SKILL.md), 상태 보기·멈추기·인증·참조·백업은 `aviron-skills/startingpoint.md`, 지금 기준 commit은 `aviron-skills/TODO.md`에 있다.
- **고쳐 쓴 때:** 2026-11-10(046차, 0.46.1)에 0.4x 기준으로 고쳐 썼다(`aviron-skills/rounds/046/3_문제정리.md` 문제 4). 3.0.0(`tt-model-bringup-a0`, `run_a0_bringup`, stage 01~10, `A0_*` 변수) 때 내용은 sungmin 저장소 `aviron-skills/.agents/skills/a0-clone-run/SKILL.md`의 git history(2026-11-12 플러그인으로 옮기기 전 위치)에 있다.

## stage

| Stage | 이름 | 장치 | 비고 |
|---:|---|:-:|---|
| 0 | reference-selection | 없음 | HF 분석과 참조 선택(exact·similar·blocks) |
| 1 | functional-decoder | 씀 | |
| 2 | optimized-decoder | 씀 | |
| 3 | full-model | 씀 | HF 참조 `ensure`를 먼저 부른다 |
| 4 | optimized-full-model | 씀 | serving entry(품질 없음) |
| 5 | benchmark-candidates | 씀 | MMLU·TTFT/TPS 보고, serving entry(품질). 그 전에 참조 `ensure` |
| 6 | vllm | 씀 | serving |
| 7 | optimized-vllm | 씀 | serving |

- report run은 0~5이고, Stage 5 뒤 사용자 선택을 기다린다.
- 연속 run은 `--serving-after 5`면 Stage 5 보고 뒤 러너가 후보를 골라 6 → 7을 이어 간다. `--serving-after 4`면 Stage 5를 건너뛰고, 품질이 `not-measured`다.
- `run_bringup`의 `--serving-after`는 4·5만 받는다.

## 규칙

- **skills 저장소:** branch `develop` 하나와 version tag(`vX.Y.Z`)만 있다(대조표는 `aviron-skills/AGENTS.md` "정본 위치"). 실행 clone은 myA0 `/home/bos/repo/aviron-skills`다(11-12 전 `/home/bos/repo/aviron_skills`).
- **고치는 곳:** 11-10부터(사용자) skills 수정·시험·commit도 실행 clone에서 직접 한다. 그래서 run이 도는 동안에는 실행 clone을 고치지 않는다. 러너가 stage check마다 plugin tree를 시작 때와 비교해, 다르면 check 없이 멈춘다(`plugin-modified`). origin에서 `git pull`하는 것도 run 중에는 하지 않는다.
- **버전 경계:** 한 run은 한 version으로 시작하고 재개한다. 다른 minor로 시작한 run은 그 tag의 clone으로만 재개한다(`v0.45.1` 등, plugin README). patch는 같은 minor의 run을 재개한다(0.46.0 run → 0.46.1).
- **플러그인 모드:** clone 모드를 쓴다. 설치본 모드는 사용자가 지시할 때만 쓴다. clone + snapshot 모드(`BOS_BRINGUP_CHECKOUT_SNAPSHOT=1`)는 쓰지 않는다(040차 shared-code identity 실패).
- **자동 checker 수정:** 끈다(`BOS_BRINGUP_AUTO_CHECKER_FIX=off`). checker 결함은 watcher가 run 밖에서 고친다.
- **Codex home:** 실행 Codex home은 run 동안 러너만 쓴다. 같은 home을 다른 app-server·확장이 쓰면 토큰 갱신이 서로 401을 낸다. `CODEX_BIN`은 항상 실제 바이너리를 준다(shim이면 `app-server --listen stdio://`를 못 띄운다).
- **운영자 메모:** `LAUNCH_NOTE`는 사용자가 지시할 때만 쓴다(300차 사용자 지시). 한 번 넣으면 그 뒤 모든 stage와 재개 objective에 붙고, 뗄 방법이 없다.

## 준비 값

| 변수 | 값(myA0) |
|---|---|
| `CHECKOUT` | `/home/bos/repo/tt-metal-e2`. run 산출물은 `bringup/`, autoport는 `models/autoports/`에 생긴다(git 추적 밖). commit을 바꾸면 `./build_metal.sh --build-type Release`로 다시 빌드한다 |
| `SK` | `/home/bos/repo/aviron-skills/plugins/bos-model-bringup`(submodule `references/aviron-transformers` 초기화 필요; 0.46.4까지는 `references/bos-transformers`) |
| `PY` | `/home/bos/repo/python_env_ttt/bin/python`. 러너 LangGraph 패키지와 serving stack(vLLM + BOS plugin)도 이 환경에 있다 |
| `STACK` | 이번 run용으로 새로 만든 serving stack manifest(`bringup/serving/stack-<date>-<tag>.json`) |
| `HF_MODEL`, `MODEL_DIR` | `MODEL_DIR=models/autoports/<model ID 소문자, 영숫자 밖은 _>` |

작업 폴더는 run마다 `/home/bos/bt_work/r0NN_<model>_<batch>_<date>/`로 만든다. 직전 run의 작업 폴더에서 script를 복사해 모델·경로·batch·tag만 바꾼다. 실제 예는 `aviron-skills/rounds/046/2_run/README.md`(046 run 1)이다.

`launch.env`:

```bash
unset RUN_DIR RESUME_STAGE RUN_MULTIGOAL_LOG_DIR BOS_BRINGUP_CHECKOUT_SNAPSHOT BOS_BRINGUP_BATCH_SCOPE BOS_BRINGUP_MAX_BATCH LAUNCH_NOTE
export CHECKOUT=/home/bos/repo/tt-metal-e2 SK=/home/bos/repo/aviron-skills/plugins/bos-model-bringup
export PY=/home/bos/repo/python_env_ttt/bin/python STACK=<stack manifest>
export BOS_BRINGUP_CODEX_HOME=/home/bos/.codex2 CODEX_HOME=/home/bos/.codex2
export CODEX_BIN=/home/bos/.local/bin/codex PYTHON_BIN=$PY
export BOS_BRINGUP_AUTO_CHECKER_FIX=off
export BOS_BRINGUP_REFERENCE_LOCAL_ONLY=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
export CODEX_MODEL=gpt-6.1-sol CODEX_EFFORT=medium REVIEW_MODEL=gpt-6-astra REVIEW_EFFORT=medium
export HF_MODEL=<org/model> MODEL_DIR=models/autoports/<model_dir>
```

- offline·local only이므로 HF checkpoint와 HF 참조는 run 전에 있어야 한다.
- **참조는 run 전에 GPU host에서 만든다.** `BOS_BRINGUP_REFERENCE_LOCAL_ONLY`를 빼고 `prepare_references.py ensure`를 run 밖에서 돌리면 GPU host(`bringup/reference_hosts.local.md`) → 로컬 GPU → CPU 순으로 쓴다(startingpoint "벤치마크 참조"). run 안에서는 local only로 둔다. 그래야 run이 GPU host 상태에 묶이지 않는다.
- 옛 이름 `A0_REFERENCE_LOCAL_ONLY`·`A0_AUTO_CHECKER_FIX`·`BRINGUP_CODEX_HOME`은 0.40.0부터 읽지 않는다.
- HF cache에 `refs/main`이 없으면(revision을 지정해 받은 모델) run 전에 pin한 revision으로 쓴다. CPU 참조 경로가 `refs/main == revision`을 요구한다(`aviron-skills/rounds/046/1_개선안.md` 046-14).

## 시작 전 확인

작업 폴더의 `precheck.sh`로 한 번에 본다.

```bash
source launch.env
git -C /home/bos/repo/aviron-skills status --porcelain -- plugins/bos-model-bringup   # 비어 있어야 한다
git -C /home/bos/repo/aviron-skills rev-parse HEAD origin/develop <tag>^{commit}      # 같아야 한다
git -C /home/bos/repo/aviron-skills submodule status
cd $CHECKOUT && git status --short | head -3 && git log --oneline -1
$PY -I $SK/runtime/readiness_check/e2_checkout.py --tt-metal-home $CHECKOUT | grep -E '"skips"|"commit"'
ls -d $CHECKOUT/$MODEL_DIR                                     # 없어야 한다
pgrep -af "run_bringup|run_device_command|graph_controller"    # 없어야 한다
fuser -v /dev/bos/0; lsmod | grep '^bos '                      # holder 없음, 셋째 칸 0
df -h $CHECKOUT
$PY $SK/scripts/prepare_references.py check --python $PY --hf-model $HF_MODEL --model-dir $MODEL_DIR   # references ready
$PY $SK/scripts/serving_stack.py --manifest $STACK --installed
CODEX_HOME=$CODEX_HOME $CODEX_BIN login status
```

- 참조 `check`는 `--python`의 환경과 비교한다. 빼면 다른 환경과 비교해 차이가 크게 나온다.
- `references environment: differs: …`는 기록만 하는 정보다. revision·protocol·파일 hash가 다르거나 세트가 없으면 not ready이고, run 전에 만든다.
- **장치 확인:** `devcheck.sh <작업 폴더>`로 wrapper 300 s 1회 `verify_device.py`를 돌려 pass·`mesh-close-confirmed`·holder 없음을 본다.
- **autoport:** 이전 run의 autoport가 남아 있으면, 접거나 취소한 run이면 지운다. 결과가 있는 run이면 백업한 뒤 지운다(startingpoint "산출물 백업").

## dry-run

장치와 Codex turn 없이 prompt, manifest, tooling을 확인한다. 새 run 폴더가 생긴다.

```bash
./start.sh --dry-run
R=$(ls -td $CHECKOUT/bringup/artifacts/multigoal-runs/*/ | head -1)
grep -E "^(plugin_mode|plugin_version|plugin_revision|reference_commit|batch_scope_operator|serving_after|stop_after_stage|device_stop_verifier|launch_note|tooling_status|serving_candidate_preview|stage_[0-7]_dry_run)" $R/manifest.txt
```

볼 값은 다음과 같다.

- `plugin_mode=clone`, `plugin_version`·`plugin_revision`이 실행 clone(tag), `reference_commit`이 submodule pin과 같다.
- `serving_after=5`, `stop_after_stage=7`, `batch_scope_operator`가 지시한 batch, `device_stop_verifier=all`.
- `launch_note` 줄이 없다.
- `tooling_status`에서 device_profiler·perf_report가 available이다.
- `stage_0_dry_run`~`stage_7_dry_run=true`.

## 시작

작업 폴더 script:

```bash
# start.sh [runner options]: new continuous run
source <work>/launch.env
unset BOS_BRINGUP_SERVING_HANDOFF BOS_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export BOS_BRINGUP_SERVING_STACK_MANIFEST=$STACK
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after 5 --max-batch <1|4> "$@"

# resume.sh <run_dir> <stage> [note|-] [runner options]: same run, same thread
source <work>/launch.env
unset BOS_BRINGUP_SERVING_HANDOFF BOS_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export BOS_BRINGUP_SERVING_STACK_MANIFEST=$STACK
export RUN_DIR=$1 RESUME_STAGE=$2
if [ -n "${3:-}" ] && [ "$3" != "-" ]; then export LAUNCH_NOTE=$3; fi
shift 3 2>/dev/null || shift $#
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after 5 --max-batch <1|4> "$@"

# launch-unit.sh <unit> <script> [args]: user systemd unit
cd $CHECKOUT && mkdir -p bringup/runner-logs
systemd-run --user --unit="$1" -p KillMode=mixed -p TimeoutStopSec=1d -p OOMPolicy=continue \
  --working-directory=$CHECKOUT \
  -p StandardOutput=append:$CHECKOUT/bringup/runner-logs/$1.log \
  -p StandardError=append:$CHECKOUT/bringup/runner-logs/$1.log "${@:2}"
```

예: `./launch-unit.sh bringup-<model>-<tag>-$(date +%Y%m%dT%H%M) <work>/start.sh`. unit 이름은 `unit.txt`, run 폴더는 `run.txt`에 적는다(감시 script가 읽는다).

- user unit으로 띄운다(`loginctl enable-linger`). 터미널에 묶이면 세션과 함께 죽는다.
- `KillMode=mixed`: unit을 멈추면 SIGTERM이 러너에만 간다. 러너는 새 장치 명령을 막고, 진행 중인 wrapper를 기한 안에 drain한 뒤 끝난다.
- `TimeoutStopSec`는 가장 긴 wrapper 기한 + 75 s보다 커야 한다.
- `OOMPolicy=continue`: OOM kill이 난 명령만 실패하고 unit은 남는다.
- 시작 뒤 확인: `systemctl --user is-active <unit>`, manifest `plugin_version`·`reference_commit`·`graph_launch=fresh`·`stage_0_thread_id`.
- **batch:** `--max-batch 1|4`(0.44.0부터). 4면 capacity 1·4, 1이면 capacity 1만이다. 재개는 기록값을 이어받는다.
- **끝난 stage부터 새 세션:** `--skip-stage <N>`을 준다(operator.md "Start a run").

## 감시 unit

run마다 두 개를 띄운다. 판단 규칙은 bringup-watcher다.

- **run 감시:** 직전 작업 폴더의 `watch_run0NN.py`를 복사한다. manifest 주요 줄, 비정상 wrapper 기록, 리뷰 verdict, unit 상태, unit 뒤 holder, 디스크를 30 s마다 `events.log`에 적는다. `waitev.sh [분]`은 중요한 줄이 생기거나 unit이 끝날 때까지 기다린다.
  ```bash
  systemd-run --user --unit=watch-r0NN-<model> -p StandardOutput=append:<work>/watch.out -p StandardError=append:<work>/watch.out \
    $PY <work>/watch_run0NN.py --name <name> --run-dir <run> --unit-file <work>/unit.txt --events <work>/events.log --disk-path $CHECKOUT
  ```
- **리셋권 감시:** 043 `codex_limit_watch.py`를 `/home/bos/a0_limitwatch_r0NN/`로 복사한다. 띄우기 전에 `--read-now`로 사용량·reset 시각·남은 리셋권을 기록한다. 99% 이상, 한도 도달, usage-limit 대기 중 하나가 생기면 리셋권을 한 번 쓴다. 같은 계정 감시는 한 곳에만 둔다(041차). 리셋권이 0이면 99%에서 사용자에게 알린다.
  ```bash
  systemd-run --user --unit=codex2-reset-watch-r0NN-<model> ... $PY codex_limit_watch.py --codex-home /home/bos/.codex2 \
    --state-dir /home/bos/a0_limitwatch_r0NN/codex2 --threshold 99 --interval 300 --manifest <run>/manifest.txt --unit <run unit>
  ```

## 재개

| 방식 | 언제 | 방법 |
|---|---|---|
| 같은 세션 | 실행 clone이 그대로일 때 | `resume.sh <run_dir> <stage> -`(새 메모 없이). `RESUME_STAGE`는 연속 run에서 0~7. manifest와 같은 `--skip-stage`·`--serving-after`·stack 내용 |
| 새 세션 | plugin을 바꿔 goal이 처음부터 읽어야 할 때, Codex 계정을 바꿀 때 | `start.sh --skip-stage …`(새 run 폴더, 끝난 stage는 건너뜀) |

- 러너는 실행 중인 세션에 메시지를 보낼 수 없다. 운영자 재개 launch는 그 stage 마지막 turn 뒤의 manifest 기록(terminal·check·review·`device_verify`·`run_status`·`stop_reason`)과, 장치 정지 뒤 받아들인 `.ack`를 resume turn에 사실로 싣는다(0.43.0부터). 그 밖의 결정을 전해야 하면 사용자에게 먼저 묻고, 허락하면 메모를 `LAUNCH_NOTE`로 주고 재개한다.
- thread는 시작한 Codex home에서만 이어진다.
- 연속 run은 handoff가 기록된 뒤에는 Stage 6·7만 재개한다. handoff 전에 멈췄으면 `RESUME_STAGE=6`으로 재개해 후보를 다시 고른다.
- **장치 정지(126):** 러너 자동 검증(`--device-stop-verifier all`)이 통과하면 같은 stage를 횟수 한도 없이 재개한다(0.45.0부터). 운영자 몫으로 남는 것은 러너 검증 실패나 holder가 남은 경우다. 장치 이상일 가능성이 높으므로 startingpoint "멈추기"를 따른다.
- 러너가 스스로 하는 재개(usage limit 대기, turn 오류 뒤 1회, controller crash 뒤 checkpoint)와 종료 기록(`run_status`·exit)은 operator.md "What the runner does on its own"·"Continuous run"에 있다.

## 연속 run 후보와 serving stack

- **후보:** 러너가 entry stage(5) 뒤 operator.md "Continuous run"의 규칙으로 후보를 고른다. 유효한 `BOS_BRINGUP_SERVING_CANDIDATE`가 먼저이고, 그다음은 후보 1개면 그것, 3개면 `middle`, 2개면 `best_quality`다. 사용자 승인을 묻지 않는다. `serving-complete`면 같은 후보로 final default를 쓴다.
- **stack manifest는 run마다 새로 만든다.** 띄우기 직전의 checkout으로 만들고, 옛 manifest는 다시 쓰지 않는다. `--create` 전에 vLLM·plugin checkout이 깨끗한지 확인한다. 남은 변경은 그대로 baseline이 된다(045차 044-15).
  ```bash
  $PY $SK/scripts/serving_stack.py --create $CHECKOUT/bringup/serving/stack-<date>-<tag>.json \
    --vllm /home/bos/repo/vllm --plugin /home/bos/repo/vllm-aviron-plugin --installed
  ```
- **run 뒤 plugin checkout:** `serving-complete` 뒤 plugin checkout이 baseline과 다르면, autoport를 지우기 전에 `third_party_patches/plugin.diff`와 대조하고 사용자에게 알린다.
- **vLLM core:** commit 그대로여야 한다. core를 고쳐야 하면 commit을 고정해 새 manifest를 만든다.

## 다른 모드(지시가 있을 때만)

- **report run:** `--serving-after`를 뺀다. Stage 5 뒤 `run_status=awaiting-user-selection`으로 끝난다.
- **Stage 4에서 serving으로:** `--serving-after 4`. MMLU가 없어 final default를 쓸 품질 근거가 없다.
- **Stage 0만:** `--selection-only`.
- **별도 serving run:** `--serving-only`, `BOS_BRINGUP_SERVING_HANDOFF=<handoff>`(`serving_handoff.py create`로 만든 것). 재개는 `RESUME_STAGE=6|7`.
- **대화형:** operator.md "Interactive run".
- report run, serving run, 연속 run은 서로 재개할 수 없다.
