# run 실행: skills clone에서 직접 돌리기

**별도 지시가 없으면 A0 bring-up run은 이 방식으로 돌린다.** 실행 clone의 플러그인 `aviron-model-bringup`을 clone 모드로 쓴다. 러너 `scripts/run_bringup`을 user systemd unit으로 띄우고, Stage 0 → 7을 연속 run(`--serving-after 5`)으로 끝까지 돈다. 명령은 모두 실행 서버에서 돌리고, 서버별 값은 sungmin `aviron-skills/startingpoint.md` "서버" 표에 있다.

- **러너 동작의 원본:** 플러그인 `skills/model-bringup/references/operator.md`(시작, 재개, 러너가 스스로 하는 일, serving, 연속 run, 종료 기록). 이 문서는 운영 값, 작업 폴더 script, 장치 안전 절차를 더한다. 둘이 다르면 operator.md를 따르고 이 문서를 고친다.
- 공통 운영 규칙(실행 clone 고정, 장치 안전, `LAUNCH_NOTE`, 백업)은 [../SKILL.md](../SKILL.md), 감시·복구 판단은 [watcher.md](watcher.md)에 있다.

```text
prepare refs (GPU host) -> precheck + devcheck -> dry-run -> launch unit + watch units
        -> stage 0..5 -> candidate -> stage 6..7 -> serving-complete -> report, backup
   on stop: STOP file -> drain -> (device stop? verify once with user ok) -> .ack -> resume
```

## stage와 러너

| Stage | 이름 | 장치 | 비고 |
|---:|---|:-:|---|
| 0 | reference-selection | 없음 | HF 분석과 참조 선택(exact·similar·blocks), host에서 돈다 |
| 1 | functional-decoder | 씀 | |
| 2 | optimized-decoder | 씀 | |
| 3 | full-model | 씀 | HF 참조 `ensure`를 먼저 부른다 |
| 4 | optimized-full-model | 씀 | serving entry(품질 없음) |
| 5 | benchmark-candidates | 씀 | MMLU·TTFT/TPS 보고, serving entry(품질). 그 전에 참조 `ensure` |
| 6 | vllm | 씀 | serving |
| 7 | optimized-vllm | 씀 | serving |

- report run은 0~5이고, Stage 5 뒤 사용자 선택을 기다린다.
- 연속 run은 `--serving-after 5`면 Stage 5 보고 뒤 러너가 후보를 골라 6 → 7을 이어 간다. `--serving-after 4`면 Stage 5를 건너뛰고, 품질이 `not-measured`다. `--serving-after`는 4·5만 받는다.
- 러너 프로세스는 LangGraph `graph_controller.py`이고, checkpoint는 `<run>/graph/checkpoint.sqlite`다. 상태의 원천은 `<run>/manifest.txt`다.
- Stage 6·7(serving)은 greedy만 받는다(temperature 0의 `top_k`·`top_p`·`min_p`는 greedy로 받는다).
- batch는 capacity 1 또는 4다(`--max-batch 1|4`). decode는 capacity 행으로 돌고 비활성 행은 −1이다. 규칙은 플러그인 `skills/model-bringup/references/batch_contract.md`에 있다.
- 새 run은 플러그인 revision 하나만 쓴다. 이전 revision 산출물은 그 revision의 checker로 판정하고, 새 run이 읽거나 재개하지 않는다.

## 규칙

- **버전 경계:** 한 run은 한 version으로 시작하고 재개한다. 다른 minor로 시작한 run은 그 minor의 재개 tag clone으로만 재개한다(0.46.x run → `v0.46.5`, plugin `EARLIER_RELEASES`·README). patch는 같은 minor의 run을 재개한다(0.46.0 run → 0.46.1).
- **플러그인 모드:** clone 모드를 쓴다. 설치본 모드는 사용자가 지시할 때만 쓴다. clone + snapshot 모드(`AVIRON_BRINGUP_CHECKOUT_SNAPSHOT=1`)는 쓰지 않는다(040차 shared-code identity 실패).
- **환경 변수 이름:** 러너 변수는 `AVIRON_BRINGUP_*`다. 옛 `BOS_BRINGUP_*`가 하나라도 설정돼 있으면 러너가 시작을 거부한다(exit 2).
- **자동 checker 수정:** 끈다(`AVIRON_BRINGUP_AUTO_CHECKER_FIX=off`). checker 결함은 watcher가 run 밖에서 고친다.
- **Codex home:** 실행 Codex home은 run 동안 러너만 쓴다. VS Code 확장·`codex mcp-server`·다른 app-server가 같은 home을 쓰면 한 프로세스의 토큰 갱신이 나머지에 401을 낸다. `CODEX_BIN`은 항상 실제 바이너리를 준다(PATH의 shim이면 `app-server --listen stdio://`를 못 띄운다).
- **호스트 메모리:** A0에 TT 모델이 올라가 있거나 장치 명령이 도는 중이면 HF 모델을 올리지 않는다.

## 준비 값

| 변수 | 값 |
|---|---|
| `CHECKOUT` | `$REPO/tt-metal-e2`. commit을 바꾸면 `./build_metal.sh --build-type Release`로 다시 빌드한다 |
| `SK` | `$REPO/aviron-skills/plugins/aviron-model-bringup` |
| `PY` | `$REPO/python_env_ttt/bin/python`. 러너 LangGraph 패키지, serving stack(vLLM + BOS plugin), 참조 `tt_transformers`(pin, non-editable)가 이 환경에 있다. 구축은 skills 루트 README "Build the run Python environment" |
| `STACK` | 이번 run용으로 새로 만든 serving stack manifest(`bringup/serving/stack-<date>-<tag>.json`) |
| `HF_MODEL`, `MODEL_DIR` | `MODEL_DIR=models/autoports/<model ID 소문자, 영숫자 밖은 _>` |

작업 폴더는 run마다 `$WORK_ROOT/r0NN_<model>_<batch>_<date>/`로 만든다. 직전 run의 작업 폴더에서 script(`launch.env`, `precheck.sh`, `devcheck.sh`, `start.sh`, `resume.sh`, `launch-unit.sh`, `watch_run0NN.py`, `waitev.sh`)를 복사해 모델·경로·batch·tag만 바꾼다. 실제 예는 sungmin `aviron-skills/rounds/046/2_run/README.md`(046 run 1)이다.

`launch.env`(`<…>` 자리는 [../SKILL.md](../SKILL.md) "환경 값"):

```bash
unset "${!BOS_BRINGUP_@}"   # old names: runner refuses to start (exit 2)
unset RUN_DIR RESUME_STAGE RUN_MULTIGOAL_LOG_DIR AVIRON_BRINGUP_CHECKOUT_SNAPSHOT AVIRON_BRINGUP_BATCH_SCOPE AVIRON_BRINGUP_MAX_BATCH LAUNCH_NOTE
export REPO=<REPO>
export CHECKOUT=$REPO/tt-metal-e2 SK=$REPO/aviron-skills/plugins/aviron-model-bringup
export PY=$REPO/python_env_ttt/bin/python STACK=<stack manifest>
export CODEX_HOME=<CODEX_HOME>
export AVIRON_BRINGUP_CODEX_HOME=$CODEX_HOME
export CODEX_BIN=<CODEX_BIN> PYTHON_BIN=$PY
export AVIRON_BRINGUP_AUTO_CHECKER_FIX=off
export AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
export CODEX_MODEL=gpt-6.1-sol CODEX_EFFORT=medium REVIEW_MODEL=gpt-6-astra REVIEW_EFFORT=medium
export HF_MODEL=<org/model> MODEL_DIR=models/autoports/<model_dir>
```

offline·local only이므로 HF checkpoint, HF 참조, MMLU dataset cache는 run 전에 있어야 한다.

## HF 참조(GT)

- 위치는 `$CHECKOUT/bringup/references/<org>/<model>/<revision>/`이다. 만드는 방법은 `$SK/scripts/prepare_references.py` 하나다(`check`·`ensure`). 상세는 플러그인 `skills/full-model/references/reference_generation.md`에 있다.
- **참조는 run 전에 GPU host에서 만든다.** `AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY`를 빼고 checkout 루트에서 돌린다. run 안에서는 local only로 둔다. 그래야 run이 GPU host 상태에 묶이지 않는다.
  ```bash
  cd $CHECKOUT && env -u AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY PYTHON_BIN=$PY python3 $SK/scripts/prepare_references.py ensure --hf-model $HF_MODEL
  ```
- 장소는 GPU host → 로컬 GPU → CPU 순서다. GPU host는 git 추적 밖의 `bringup/reference_hosts.local.md`에 ` ```json ` block(`{"hosts": [{"name", "ssh", "workdir", "python", "min_free_gb", "max_gpu_util"}]}`)으로 적는다. 원격 venv는 `$PY`의 패키지 버전으로 만들고(`python3.10`이 없으면 `python3`) 끝나면 지운다.
- 러너는 launch마다 Stage 3·5 가운데 처음 도는 stage 앞에서 `ensure`를 부르고 끝날 때까지 기다린다(`<run>/references.log`). 준비되지 않으면 그 stage 전에 멈춘다(exit 8).
- 세트는 `references.json`의 revision·protocol·dtype·파일 hash가 맞으면 다시 쓴다. 맞지 않으면 옛 폴더를 `<revision>.superseded-<시각>`으로 옮기고 새로 만든다.
- `references environment: match|differs: …|unrecorded`는 기록만 하는 정보다. 패키지 버전 같은 생산 환경이 달라도 세트를 그대로 쓰고, 러너는 manifest에 `references_environment`(차이가 있으면 `references_environment_diff`)를 남긴다. 보고서에는 참조 생산 환경과 run 환경을 나란히 적는다.
- HF cache에 `refs/main`이 없으면(revision을 지정해 받은 모델) run 전에 pin한 revision으로 쓴다. CPU 참조 경로가 `refs/main == revision`을 요구한다(046-14).

## 시작 전 확인

작업 폴더의 `precheck.sh`로 한 번에 본다.

```bash
source launch.env
env | grep '^BOS_BRINGUP_'                                     # 없어야 한다
git -C $REPO/aviron-skills status --porcelain -- plugins/aviron-model-bringup   # 비어 있어야 한다
git -C $REPO/aviron-skills rev-parse HEAD origin/develop <tag>^{commit}      # 같아야 한다
$PY -c 'import tt_transformers; print(tt_transformers.__file__)'   # python_env_ttt site-packages 아래여야 한다
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

- 참조 `check`는 `--python`의 환경과 비교한다. 빼면 다른 환경과 비교해 차이가 크게 나온다. revision·protocol·파일 hash가 다르거나 세트가 없으면 not ready이고, run 전에 만든다.
- **장치 확인:** `devcheck.sh <작업 폴더>`로 wrapper 300 s 1회 `verify_device.py`를 돌려 pass·`mesh-close-confirmed`·holder 없음을 본다.
- **autoport:** 이전 run의 autoport가 남아 있으면, 접거나 취소한 run이면 지운다. 결과가 있는 run이면 아래 "산출물 백업"대로 압축·대조한 뒤 지운다.

## dry-run

장치와 Codex turn 없이 prompt, manifest, tooling을 확인한다. 새 run 폴더가 생기고, 확인 뒤 지운다.

```bash
./start.sh --dry-run
R=$(ls -td $CHECKOUT/bringup/artifacts/multigoal-runs/*/ | head -1)
grep -E "^(plugin_mode|plugin_version|plugin_revision|reference_commit|reference_source_hash|batch_scope_operator|serving_after|stop_after_stage|device_stop_verifier|launch_note|tooling_status|serving_candidate_preview|stage_[0-7]_dry_run)" $R/manifest.txt
```

볼 값은 다음과 같다.

- `plugin_mode=clone`, `plugin_version`·`plugin_revision`이 실행 clone(tag), `reference_commit`이 skills pin과 같고 `reference_source_hash`가 있다.
- `serving_after=5`, `stop_after_stage=7`, `batch_scope_operator`가 지시한 batch, `device_stop_verifier=all`.
- `launch_note` 줄이 없다.
- `tooling_status`에서 device_profiler·perf_report가 available이다.
- `stage_0_dry_run`~`stage_7_dry_run=true`.

## 시작

작업 폴더 script:

```bash
# start.sh [runner options]: new continuous run
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after 5 --max-batch <1|4> "$@"

# resume.sh <run_dir> <stage> [note|-] [runner options]: same run, same thread
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
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
- **batch:** `--max-batch 1|4`. 4면 capacity 1·4, 1이면 capacity 1만이다. 재개는 기록값을 이어받는다.
- **끝난 stage부터 새 세션:** `--skip-stage <N>`을 준다(operator.md "Start a run").

## 감시 unit

run마다 두 개를 띄운다. 판단 규칙은 [watcher.md](watcher.md)다.

- **run 감시:** 직전 작업 폴더의 `watch_run0NN.py`를 복사한다. manifest 주요 줄, 비정상 wrapper 기록, 리뷰 verdict, unit 상태, unit 뒤 holder, 디스크를 30 s마다 `events.log`에 적는다. `waitev.sh [분]`은 중요한 줄이 생기거나 unit이 끝날 때까지 기다린다.
  ```bash
  systemd-run --user --unit=watch-r0NN-<model> -p StandardOutput=append:<work>/watch.out -p StandardError=append:<work>/watch.out \
    $PY <work>/watch_run0NN.py --name <name> --run-dir <run> --unit-file <work>/unit.txt --events <work>/events.log --disk-path $CHECKOUT
  ```
- **리셋권 감시:** 043 `codex_limit_watch.py`를 `$LIMITWATCH`로 복사한다. 띄우기 전에 `--read-now`로 사용량·reset 시각·남은 리셋권을 기록한다. 99% 이상, 한도 도달, usage-limit 대기 중 하나가 생기면 리셋권을 한 번 쓴다. 같은 계정 감시는 한 서버에만 둔다(041차, 서버 표). 리셋권이 0이면 99%에서 사용자에게 알린다.
  ```bash
  systemd-run --user --unit=codex2-reset-watch-r0NN-<model> ... $PY codex_limit_watch.py --codex-home $CODEX_HOME \
    --state-dir $LIMITWATCH/codex2 --threshold 99 --interval 300 --manifest <run>/manifest.txt --unit <run unit>
  ```

## 상태 보기

```bash
systemctl --user list-units --no-legend 'bringup-*' 'watch-*' 'codex2-*'
tail -3 $CHECKOUT/bringup/runner-logs/<unit>.log
tail -5 <run>/manifest.txt
cat <run>/wrappers/status.json                  # drained, blocking
fuser -v /dev/bos/0
ps -eo etime,cmd | grep "[r]un_device_command.py"
```

- stage 진행은 `<run>/<NN>-<stage>.jsonl`(재개면 `.resume-N.jsonl`)과 autoport `doc/<stage>/work_log.md`에서 본다.
- wrapper 기록은 `<run>/wrappers/*.json`이다. 판독표는 [watcher.md](watcher.md) "감시"에 있다.

## 재개

| 방식 | 언제 | 방법 |
|---|---|---|
| 같은 세션 | 실행 clone이 그대로일 때 | `resume.sh <run_dir> <stage> -`(새 메모 없이). `RESUME_STAGE`는 연속 run에서 0~7. manifest와 같은 `--skip-stage`·`--serving-after`·stack 내용 |
| 새 세션 | plugin을 바꿔 goal이 처음부터 읽어야 할 때, Codex 계정을 바꿀 때 | `start.sh --skip-stage …`(새 run 폴더, 끝난 stage는 건너뜀) |

- 운영자 재개 launch는 그 stage 마지막 turn 뒤의 manifest 기록(terminal·check·review·`device_verify`·`run_status`·`stop_reason`)과 장치 정지 뒤 받아들인 `.ack`를 resume turn에 사실로 싣는다. 그 밖의 결정을 전해야 하면 사용자 허락을 받아 `LAUNCH_NOTE`로 준다.
- thread는 시작한 Codex home에서만 이어진다.
- 연속 run은 handoff가 기록된 뒤에는 Stage 6·7만 재개한다. handoff 전에 멈췄으면 `RESUME_STAGE=6`으로 재개해 후보를 다시 고른다.
- **장치 정지(126):** 러너 자동 검증(`--device-stop-verifier all`)이 통과하면 같은 stage를 횟수 한도 없이 재개한다. 러너 검증이 실패했거나 holder가 남으면 아래 "멈추기"를 따른다.
- 러너가 스스로 하는 재개(usage limit 대기, turn 오류 뒤 1회, controller crash 뒤 checkpoint)와 종료 기록(`run_status`·exit)은 operator.md "What the runner does on its own"·"Continuous run"에 있다.

## 멈추기(장치 안전)

1. 새 장치 명령 시작을 막는다: `touch <run>/wrappers/STOP`. 새 wrapper는 시작을 거부하고, 진행 중인 명령은 그대로 끝난다.
2. `<run>/wrappers/status.json`이 `drained: true`, `blocking: []`가 될 때까지 기다린다.
3. 신호가 꼭 필요하면 확인한 wrapper PID에만 한 번 보낸다. wrapper는 지연 중단으로 기록하고 child에는 신호를 넘기지 않는다. 반복 신호로 강제 종료하지 않는다.
   ```bash
   ps -p <wrapper-pid> -o pid,ppid,etime,args
   kill -INT <wrapper-pid>
   ```
4. wrapper가 끝나고 holder가 없을 때만 unit을 멈춘다.
   ```bash
   fuser -v /dev/bos/0                                    # 비어 있어야 한다
   ps -eo pid,etime,cmd | grep "[r]un_device_command"     # 없어야 한다
   systemctl --user stop <unit>.service
   ```
5. 멈춘 시각과 이유를 autoport `doc/INTERVENTIONS.md`에 적는다.

하지 않는 것:

- 넓은 `pkill -f`를 쓰지 않는다.
- 장치를 연 프로세스를 강제로 죽이지 않는다. FLR, PCI remove/rescan, `tt-smi` reset을 하지 않는다. FW init이 실패하면 장치 작업을 멈추고 재부팅한다(사용자 확인).

wrapper가 `stop-device-work`(exit 126, 기한 종료 포함)로 끝났거나 wrapper 기록에 exit가 없으면(러너가 먼저 죽음):

- 장치를 다시 열지 않는다(`verify_device.py` 포함). hang 장치를 다시 열면 PCIe 이탈이 난다(026차 조사).
- 명령 log 끝에 mesh close가 있고 holder가 없을 때만, 사용자 승인 뒤 wrapper로 verifier를 1회 돌린다. 그 밖에는 재부팅한다.
- verifier가 통과했거나 재부팅한 뒤에는 그 registration 옆에 `wrappers/<registration>.ack`(이유·누구·언제 한 줄)를 두고 같은 run으로 재개한다. drain은 ack된 기록을 해결로 치고 원래 기록은 그대로 둔다. registry를 옮기거나 새 run을 띄우지 않는다.
- `continue-stage`로 끝난 명령 실패는 drain을 막지 않는다.

## 인증이 풀렸을 때

goal이 `blocked`로 끝나도 `codex login status`는 정상으로 보일 수 있다. thread의 세션 기록에서 확인한다.

```bash
T=$(grep -E "^stage_[0-9]+(_resume_[0-9]+)?_thread_id=" <run>/manifest.txt | tail -1 | cut -d= -f2)
grep -a -o '"codex_error_info": *"[^"]*"' $(ls -t $CODEX_HOME/sessions/*/*/*/rollout-*${T}.jsonl | head -1) | tail -1
```

`unauthorized`면 `CODEX_HOME=$CODEX_HOME $CODEX_BIN login`으로 다시 로그인하고 같은 세션을 이어 간다.

## 연속 run 후보와 serving stack

- **후보:** 러너가 Stage 5 뒤 operator.md "Continuous run" 규칙으로 고르고 사용자 승인을 묻지 않는다. 고정하려면 `AVIRON_BRINGUP_SERVING_CANDIDATE`를 준다.
- **stack manifest는 run마다 새로 만든다.** 띄우기 직전의 checkout으로 만들고, 옛 manifest는 다시 쓰지 않는다. `--create` 전에 vLLM·plugin checkout이 깨끗한지 확인한다. 남은 변경은 그대로 baseline이 된다(045차 044-15).
  ```bash
  $PY $SK/scripts/serving_stack.py --create $CHECKOUT/bringup/serving/stack-<date>-<tag>.json \
    --vllm $REPO/vllm --plugin $REPO/vllm-aviron-plugin --installed
  ```
- **run 뒤 plugin checkout:** `serving-complete` 뒤 plugin checkout이 baseline과 다르면, autoport를 지우기 전에 `third_party_patches/plugin.diff`와 대조하고 사용자에게 알린다.
- **vLLM core:** commit 그대로여야 한다. core를 고쳐야 하면 commit을 고정해 새 manifest를 만든다.

## 산출물 백업

기존 산출물은 지우지 않고 `$BACKUP`에 압축해 둔다. `bringup/`과 `models/autoports/`는 사용자가 정한 경우에만, 압축을 대조한 뒤 지운다. `bringup/references/`는 다음 run이 읽으므로 남긴다.

```bash
cd $CHECKOUT
B=$BACKUP/autoport_<model>_r0NN_$(date +%Y%m%dT%H%M)_nopt_notracy.tgz   # 텐서·Tracy 원자료·profile CSV 제외
tar -czf "$B" -C models --exclude='*.pt' --exclude='*.tensorbin' --exclude='*.tracy' --exclude=profile_log_device.csv \
  --exclude=tracy_ops_times.csv --exclude=__pycache__ autoports/<model_dir> && tar -dzf "$B" -C models && echo identical
```

- 전체 사본이 필요하면 `--exclude`를 빼고 같은 방식으로 만든다.
- 다른 서버의 산출물은 그 서버에서 압축·대조한 뒤 백업 위치로 옮긴다. 백업 경로와 크기는 차수 run 기록에 적는다.

## 다른 모드(지시가 있을 때만)

- **report run:** `--serving-after`를 뺀다. Stage 5 뒤 `run_status=awaiting-user-selection`으로 끝난다.
- **Stage 4에서 serving으로:** `--serving-after 4`. MMLU가 없어 final default를 쓸 품질 근거가 없다.
- **Stage 0만:** `--selection-only`.
- **별도 serving run:** `--serving-only`, `AVIRON_BRINGUP_SERVING_HANDOFF=<handoff>`(`serving_handoff.py create`로 만든 것). 재개는 `RESUME_STAGE=6|7`.
- **대화형:** operator.md "Interactive run".
- report run, serving run, 연속 run은 서로 재개할 수 없다.
