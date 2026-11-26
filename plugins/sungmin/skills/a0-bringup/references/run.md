# run 실행

**별도 지시가 없으면 A0 bring-up run은 이 방식으로 돌린다.** 실행 clone의 `aviron-model-bringup`을 clone 모드로 쓰고, 작업 폴더 script로 러너(`scripts/run_bringup`)를 user systemd unit으로 띄워 Stage 0 → 8을 연속 run(`--serving-after benchmark-candidates`)으로 끝까지 돈다. run은 실행 서버(myA0)에서 돌고 host가 ssh로 감시한다. myA0 장치가 hang되면 host가 묻지 않고 [power.md](power.md) 절차로 복구해 같은 run을 재개한다. 서버별 값은 sungmin `aviron-skills/startingpoint.md` "서버" 표에 있다.

- **원본:** 명령과 러너 동작은 plugin `skills/model-bringup/references/operator.md`다(skills 0.55.0). 이 문서는 운영 값, 작업 폴더 script, 장치 안전 절차를 더한다. 둘이 다르면 plugin을 따르고 이 문서를 고친다.
- 공통 운영 규칙(실행 clone 고정, 장치 안전, `LAUNCH_NOTE`, 백업)은 [../SKILL.md](../SKILL.md), 감시·복구 판단은 [watcher.md](watcher.md), myA0 hang 복구(보드 전원·재부팅)는 [power.md](power.md)에 있다.

```text
prepare refs (GPU host) -> precheck + devcheck -> start.sh --dry-run -> launch-unit.sh start.sh + watch units
        -> stage 0..6 -> candidate -> stage 7..8 -> serving-complete -> report, backup
   host watches over ssh; device hang on myA0: power cycle + reboot (power.md, no asking) -> resume-with.sh verified-resume
   waiting interrupt (126 await_ack, 3 await_hold): resume-with.sh; other stops: resume.sh
```

## 시작 script(작업 폴더)

러너는 실행 서버의 작업 폴더 script로 띄운다. 옛 작업 폴더 script는 11-25에 지워졌으니 아래 모양으로 새로 만든다. `launch.env`는 아래 "운영 값"을 export하고 `unset "${!BOS_BRINGUP_@}"`, `unset RUN_DIR RESUME_STAGE LAUNCH_NOTE CODEX_MODEL CODEX_EFFORT`로 시작한다. key는 파일·명령줄에 쓰지 않는다. host에서는 `ssh <서버> <work>/launch-unit.sh …`로 부른다.

```bash
# start.sh [runner options]: new continuous run
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after benchmark-candidates --max-batch <1|4> "$@"
# resume.sh <run> <stage> [note|-]: same as start.sh plus `export RUN_DIR=$1 RESUME_STAGE=$2` (and LAUNCH_NOTE=$3 unless it is -)
# resume-with.sh <run> '<JSON>': same as start.sh plus `--run-dir "$1" --resume-with "$2"`, with RUN_DIR and RESUME_STAGE unset

# launch-unit.sh <unit> <script> [args]: user systemd unit
cd $CHECKOUT && mkdir -p bringup/runner-logs
if [ "$AVIRON_BRINGUP_RUNNER" = deepagents ]; then systemctl --user import-environment OPENAI_API_KEY; fi
systemd-run --user --unit="$1" -p KillMode=mixed -p TimeoutStopSec=1d -p OOMPolicy=continue \
  --working-directory=$CHECKOUT \
  -p StandardOutput=append:$CHECKOUT/bringup/runner-logs/$1.log \
  -p StandardError=append:$CHECKOUT/bringup/runner-logs/$1.log "${@:2}"
if [ "$AVIRON_BRINGUP_RUNNER" = deepagents ]; then systemctl --user unset-environment OPENAI_API_KEY; fi
```

- systemd 249는 값 없는 `--setenv=KEY`를 받지 않아 key를 user manager로 넘기고 바로 지운다. 띄운 뒤 `systemctl --user show-environment | grep -c OPENAI_API_KEY`가 0인지 본다. key가 `~/.bashrc` interactive 구간에만 있으면(AI001) 그 줄을 셸로 가져와 쓰되 값은 출력하지 않는다.
- user unit(`loginctl enable-linger`). `KillMode=mixed`면 SIGTERM이 러너에만 가 진행 중 wrapper를 drain한다. `TimeoutStopSec`는 가장 긴 wrapper 기한 + 75 s보다 커야 한다. `OOMPolicy=continue`.
- 모든 launch script의 mode option(`--serving-after`, `--max-batch`, `--skip-stage`)은 manifest와 같아야 한다.
- dry-run을 손으로 돌릴 때는 앞뒤 run 폴더 목록을 비교해 rc 0이고 새로 생긴 폴더가 정확히 하나일 때 그것만 지운다. "가장 새 폴더"를 지우지 않는다(051 run 1에서 돌던 run 폴더가 지워졌다).
- 예: `./launch-unit.sh bringup-<model>-<tag>-$(date +%Y%m%dT%H%M) <work>/start.sh`. unit 이름은 `unit.txt`, run 폴더는 `run.txt`에 적는다.

## stage

| Stage | 이름 | 장치 | 비고 |
|---:|---|:-:|---|
| 0 | reference-selection | 없음 | HF 분석과 참조 선택, host에서 돈다 |
| 1 | functional-decoder | 씀 | |
| 2 | optimized-decoder | 씀 | |
| 3 | full-model | 씀 | 통합, O0 anchor를 얼린다 |
| 4 | full-model-candidates | 씀 | 후보·fidelity·handover. 그 전에 HF 참조 `ensure` |
| 5 | optimized-full-model | 씀 | serving entry(품질 없음) |
| 6 | benchmark-candidates | 씀 | MMLU·TTFT/TPS 보고, serving entry(품질). 그 전에 참조 `ensure` |
| 7 | vllm | 씀 | serving(greedy만) |
| 8 | optimized-vllm | 씀 | serving(greedy만) |

- report run은 0~6이고 Stage 6 뒤 `await_selection`에서 기다린다. 연속 run은 Stage 6 보고 뒤 러너가 후보를 골라 7 → 8을 잇는다. `--serving-after`는 `benchmark-candidates`·`optimized-full-model` 두 이름만 받는다.
- batch는 `--max-batch 1|4`(4면 capacity 1·4). 규칙은 plugin `skills/model-bringup/references/batch_contract.md`.
- 상태의 원천은 `<run>/manifest.txt`, checkpoint는 `<run>/graph/checkpoint.sqlite`다.

## 러너

`--runner deepagents|codex|claude`. **기본값이 없다**(빠지면 exit 2). 사용자가 말하지 않았으면 묻는다. 한 run은 한 러너이고 다른 러너로 재개하면 거부된다. 원본은 operator.md "Choose the runner".

| | `deepagents` | `codex` | `claude` |
|---|---|---|---|
| stage 에이전트 | Deep Agents가 모델 API 직접 호출(모델 이름이 `claude-`면 Anthropic, 아니면 OpenAI) | Codex app-server goal | Claude Code CLI |
| 실제 launch에 필요한 것 | `OPENAI_API_KEY`(Claude 모델이면 `ANTHROPIC_API_KEY`), `launch-unit.sh`를 부르는 셸에 | `CODEX_BIN`(실제 바이너리, shim 아님), plugin 설치·로그인된 `AVIRON_BRINGUP_CODEX_HOME` | `CLAUDE_BIN=$HOME/.local/bin/claude`(비대화 ssh PATH에 없음), `~/.claude` 로그인 |
| 러너가 스스로 하는 것 | API 오류 backoff. launch당 모델 호출 3000회면 `turn-failed`. 한도 대기·비용 상한 없음 | usage limit 대기, 일시적 turn 오류 대기, host 실패 뒤 1회 재개, checker 수정 | codex와 같음 |

- 모델 설정은 `AGENT_MODEL`·`AGENT_EFFORT`·`REVIEW_MODEL`·`REVIEW_EFFORT`다(codex는 `CODEX_MODEL`·`CODEX_EFFORT`를 먼저 읽으니 unset). deepagents 기본은 `gpt-6.2-sol`/`gpt-6.2-astra` medium, `AGENT_MODEL=claude-sonnet-5-5`면 나머지 기본이 `medium`·`claude-opus-5-5`·`medium`이다. claude 러너 기본은 `claude-sonnet-5-5`·리뷰 `claude-opus-5-5`, medium.
- Codex·Claude Code 버전은 pin이 없다. launch마다 `codex_version`·`claude_version`이 manifest에 남는다. 업데이트 뒤 첫 run은 그 버전에서 검증되지 않은 것으로 본다. Claude Code는 `autoUpdates: false`여도 run 도중 바뀔 수 있으니, 버전이 바뀌면 run 기록에 시각을 적는다.
- **Codex home:** run 동안 러너만 쓴다. VS Code 확장·다른 app-server가 같은 home을 쓰면 토큰 갱신이 401을 낸다. myA0 Codex home 셋은 11-25에 plugin을 지웠으니 codex 러너 run 전에 다시 설치한다.

## 규칙

- **버전 경계:** 한 run은 한 minor로 시작하고 재개한다. 다른 minor로 시작한 run은 그 minor의 재개 tag clone으로만 재개한다(plugin `EARLIER_RELEASES`·README). patch는 같은 minor를 재개한다.
- **참조 설치:** `python_env`에는 참조 `tt_transformers`가 pin 하나만 설치된다. 러너가 설치 hash를 `PIN_SOURCE_HASH`와 대조해 다르면 멈춘다. 다른 version으로 돌리려면 그 pin을 다시 설치한다(skills 루트 README "Build the run Python environment").
- **run 중 시험:** run이 도는 서버에서 skills `tests/` 전체를 돌리지 않는다. `tests/test_device_command.py`가 run과 같은 host 잠금을 잡아 run의 장치 명령이 exit 125로 거절된다. 장치 wrapper를 쓰지 않는 시험만 돌리거나 run 뒤에 돌린다. subagent에 맡길 때도 이렇게 적는다.
- **플러그인 모드:** clone 모드. 설치본 모드는 사용자가 지시할 때만, clone + snapshot(`AVIRON_BRINGUP_CHECKOUT_SNAPSHOT=1`)은 쓰지 않는다.
- **환경 변수:** 옛 `BOS_BRINGUP_*`가 하나라도 있으면 러너가 거부한다(exit 2).
- **성능 잡음:** tt-metal-e2를 DRAM 정렬 없이 빌드하면 decode가 weight 시작 주소에 따라 3~4% 오간다(sungmin `aviron-skills/rounds/054/조사/dram_배치_랜덤성_검토_20261124.md`). 정렬 없는 빌드의 측정과 비교해 skills 변경 효과로 판단하지 않는다.
- **호스트 메모리:** A0에 TT 모델이 올라가 있거나 장치 명령이 도는 중이면 HF 모델을 올리지 않는다.

## run 환경

tt-metal-e2 checkout 하나와 uv 가상환경 하나로 모든 러너를 돌린다. 구축 원본은 skills 루트 README "Build the run Python environment"이고, 여기에는 운영에서 걸리는 점만 적는다.

```text
$REPO/tt-metal-e2        one checkout, built with python_env's Python 3.12, DRAM alignment ON
$REPO/python_env         uv venv --seed, Python 3.12 (runner packages, ttnn, serving stack, lm_eval, tt_transformers pin)
$REPO/aviron-skills      execution clone: develop
```

- **tt-metal-e2 재빌드:** 환경을 PATH 앞에 두고 DRAM 정렬을 켠다. `build_metal.sh`는 PATH의 `python3`로 `_ttnn.so`를 만들어서, 그냥 돌리면 시스템 3.10 binding이 나와 `python_env`가 깨진다. 켜졌는지는 장치 log `DRAM large buffer alignment: 256 B`로 본다.
  ```bash
  cd $CHECKOUT && PATH=$REPO/python_env/bin:$PATH VIRTUAL_ENV=$REPO/python_env ./build_metal.sh --build-type Release --enable-dram-large-buffer-alignment
  $PY -c 'import ttnn; ttnn.bos_quantize_fused'   # then devcheck (device smoke)
  ```
- **checkout 하나 = Python 하나:** `_ttnn.so` 이름에 Python 버전이 없다. 다른 버전이 필요하면 별도 checkout에서 빌드한다.
- **`env_set.sh`:** venv 경로를 둘째 인자로 넘긴다(`source $CHECKOUT/env_set.sh bos $REPO/python_env`).
- **uv:** `uv venv --seed`로 만든다(pip 필요). venv는 `~/.local/share/uv/python/`의 3.12를 가리키므로 그 폴더를 지우면 깨지고, uv로 patch를 올리면 interpreter도 바뀐다(재현성을 따질 때 `$PY -V` 기록).
- **pin:** `pyarrow==25.0.1`(26은 lm_eval import를 깬다). 러너 package는 `requirements-da.txt`이고, launch마다 설치 버전을 pin과 대조해 다르면 거부한다.

## 운영 값

| 변수 | 값 |
|---|---|
| `CHECKOUT` | `$REPO/tt-metal-e2` |
| `SK` | `$REPO/aviron-skills/plugins/aviron-model-bringup` |
| `PY` | `$REPO/python_env/bin/python` |
| `STACK` | 이번 run용으로 새로 만든 serving stack manifest(`bringup/serving/stack-<date>-<tag>.json`) |
| `HF_MODEL`, `MODEL_DIR` | `MODEL_DIR=models/autoports/<model ID 소문자, 영숫자 밖은 _>` |

`launch.env`에 export할 것:

- 늘: `AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1`, `MODEL_DIR=...`, 모델 설정(`AGENT_MODEL` 등, 기본이면 생략)
- codex: `CODEX_BIN=<CODEX_BIN>`, `AVIRON_BRINGUP_CODEX_HOME=<CODEX_HOME>`
- claude: `CLAUDE_BIN=$HOME/.local/bin/claude`
- 장치가 여럿인 서버(AI001): `TT_VISIBLE_DEVICES=0`

offline·local only이므로 HF checkpoint, HF 참조, MMLU dataset cache는 run 전에 있어야 한다. 작업 폴더(감시 script, log, `unit.txt`·`run.txt`)는 run마다 `$WORK_ROOT/r0NN_<model>_<batch>_<date>/`로 만든다. myA0 `$WORK_ROOT`의 옛 작업 폴더는 11-25에 모두 지웠다(script 원본 없음).

## HF 참조(GT)

- 위치는 `$CHECKOUT/bringup/references/<org>/<model>/<revision>/`, 도구는 `$SK/scripts/prepare_references.py`(`check`·`ensure`) 하나다. 상세는 plugin `skills/full-model-candidates/references/reference_generation.md`.
- **run 전에 GPU host에서 만든다.** run 안에서는 local only로 둬 GPU host 상태에 묶이지 않게 한다.
  ```bash
  cd $CHECKOUT && env -u AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY PYTHON_BIN=$PY python3 $SK/scripts/prepare_references.py ensure --hf-model $HF_MODEL
  ```
- 장소는 GPU host → 로컬 GPU → CPU 순서다. GPU host는 git 추적 밖 `bringup/reference_hosts.local.md`의 ` ```json ` block(`{"hosts": [{"name", "ssh", "workdir", "python", "min_free_gb", "max_gpu_util"}]}`)에 적는다. 원격 venv는 `$PY`와 같은 Python·패키지 버전으로 만들고 끝나면 지운다.
- 러너는 Stage 4·6 가운데 처음 도는 stage 앞에서 `ensure`를 부르고, 준비되지 않으면 그 stage 전에 멈춘다(exit 8, `<run>/references.log`).
- `references environment: differs`는 기록만 한다. 보고서에 참조 생산 환경과 run 환경을 나란히 적는다.
- HF cache에 `refs/main`이 없으면(revision 지정 다운로드) run 전에 pin한 revision으로 쓴다. CPU 참조 경로가 `refs/main == revision`을 요구한다.

## 시작 전 확인

```bash
env | grep '^BOS_BRINGUP_'                                     # 없어야 한다
git -C $REPO/aviron-skills status --porcelain -- plugins/aviron-model-bringup   # 비어 있어야 한다
git -C $REPO/aviron-skills rev-parse HEAD origin/develop <tag>^{commit}      # 같아야 한다
$PY -V                                                         # Python 3.12.x
$PY -c 'import tt_transformers, ttnn; print(tt_transformers.__file__, ttnn.__file__)'   # python_env site-packages, $CHECKOUT/ttnn/ttnn
$PY $SK/scripts/reference_source.py                            # 오류 없이 pin commit
cd $CHECKOUT && git status --short | head -3 && git log --oneline -1
$PY -I $SK/runtime/readiness_check/e2_checkout.py --tt-metal-home $CHECKOUT | grep -E '"skips"|"commit"'
$PY -c 'import ttnn; ttnn.bos_quantize_fused'                  # W8A8: 없으면 e2를 develop 최신으로 올려 다시 빌드
ls -d $CHECKOUT/$MODEL_DIR                                     # 없어야 한다
ps -eo pid,etime,cmd | grep -E "[r]un_bringup|[r]un_device_command|[g]raph_controller|[v]llm serve|[E]ngineCore"   # 없어야 한다
fuser -v /dev/bos/0; cat /sys/module/bos/refcnt                # holder 없음, 0
df -h $CHECKOUT
$PY $SK/scripts/prepare_references.py check --python $PY --hf-model $HF_MODEL --model-dir $MODEL_DIR   # references ready
$PY $SK/scripts/serving_stack.py --manifest $STACK --installed
CODEX_HOME=$CODEX_HOME $CODEX_BIN login status                 # codex 러너
```

- **프로세스 확인:** `pgrep -f`는 쓰지 않는다. ssh 명령줄에 패턴이 들어가 원격 셸을 찾는다. `grep "[r]un_…"`처럼 괄호를 넣고, 같은 ssh 명령에 괄호 없는 이름을 함께 적지 않는다.
- 참조 `check`는 `--python`의 환경과 비교한다. not ready면 run 전에 만든다.
- **장치 확인(devcheck):** wrapper 300 s로 `verify_device.py`를 1회 돌려 pass·`mesh-close-confirmed`·holder 없음을 본다.
- **공용 장치(AI001):** `fuser`는 다른 사용자(docker 안 root)의 holder를 못 보니 `/sys/module/bos/refcnt`가 0인지 본다. 0이 아니면 시작하지 않는다. `/dev/bos/0`(Gen4 x4)만 쓰고 `/dev/bos/1`은 다른 사용자 것이다.
- **autoport:** 이전 run의 autoport가 남아 있으면, 접거나 취소한 run이면 지우고, 결과가 있으면 "산출물 백업"대로 한다.

## dry-run과 시작

- dry-run(`./start.sh --dry-run`)은 장치·모델 호출 없이 prompt·manifest·tooling을 확인하고 새 run 폴더를 만든다. 러너를 여럿 쓸 서버면 러너마다 돌린다.
- 확인 뒤 지울 폴더는 앞뒤 run 폴더 목록을 비교해 rc 0이고 새로 생긴 폴더가 정확히 하나이며 그 manifest에 `stage_0_dry_run=true`가 있을 때 그것뿐이다. "가장 새 폴더"를 지우지 않는다(051 run 1에서 돌던 run 폴더가 지워졌다).
  ```bash
  RUNS=$CHECKOUT/bringup/artifacts/multigoal-runs; ls $RUNS > runs_before.txt
  ./start.sh --dry-run; echo rc=$?
  NEW=$(comm -13 runs_before.txt <(ls $RUNS)); echo "new=$NEW"   # rc 0이고 정확히 한 줄일 때만
  ```
- 볼 값:
  - `runner=`, 러너별 줄(deepagents `model_api`·`deepagents_version`, codex `codex_home`·`codex_bin`·`codex_version`, claude `claude_bin`·`claude_version`·`claude_auth`)
  - `plugin_mode=clone`, `plugin_version`·`plugin_revision`이 실행 clone, `reference_commit`이 pin, `reference_source_hash` 있음
  - `serving_after=benchmark-candidates`, `stop_after_stage=8`, `batch_scope_operator`, `device_stop_verifier=all`, `launch_note` 없음
  - `tooling_status`의 device_profiler·perf_report available, `stage_0_dry_run`~`stage_8_dry_run=true`
- 시작은 `launch-unit.sh <unit> <work>/start.sh`다. unit 이름과 새 run 폴더를 작업 폴더 `unit.txt`·`run.txt`에 적는다. 시작 뒤 `systemctl --user is-active <unit>`과 manifest `graph_launch=fresh`·`stage_0_thread_id`를 본다.
- 끝난 stage부터 새 세션은 `start.sh --skip-stage <N>`(새 run 폴더).

## 감시 unit

run 감시와 hang 판정은 host의 watcher가 ssh로 "상태 보기"를 읽어서 한다(판단 규칙 [watcher.md](watcher.md), hang 기준 [power.md](power.md) "언제"). 아래는 러너에 없어 운영자가 실행 서버에 따로 띄우는 것이다. 재부팅하면 모두 없어지니 복구 뒤 다시 띄운다. 모두 읽기만 하거나 "멈추기" 1·2·4만 하고, 아무것도 지우지 않는다.

- **디스크 보호:** 러너는 디스크를 보지 않는다. 여유가 하한(예: 6 GB) 밑이면 아래 "멈추기" 1·2·4를 하는 unit을 둔다. 장치가 바쁘면 unit을 멈추지 않고 그렇게 적는다. 옛 `diskguard.sh`는 11-25에 지워졌으니 쓸 때 새로 만든다.
- **비용 감시(deepagents만):** 이 plugin `scripts/costguard.sh`가 60 s마다 `scripts/usage.py`로 `<run>/usage.jsonl`의 USD 추정을 계산해, 알림 단계(기본 25·50·100·200)마다 `events.log`에 `cost alert`를 쓰고 상한에서 "멈추기" 1·2·4를 한다. 상한은 run 전에 사용자에게 묻는다. 단가는 `usage.py`의 `PRICE`이고 모델·가격표가 바뀌면 고친다.
  ```bash
  systemd-run --user --unit=costguard-r0NN-<model> -p StandardOutput=append:<work>/costguard.out -p StandardError=append:<work>/costguard.out \
    bash <plugin>/skills/a0-bringup/scripts/costguard.sh <work> <limit USD> 25,50,100,200
  ```
  `<plugin>`은 설치된 sungmin-plugin 경로다. 실행 서버에 없으면 두 파일을 작업 폴더로 복사한다.
- **사용량(claude만):** 러너에 계정 사용량 감시가 없다. stage log(`<run>/*.jsonl`)의 `rate_limit_event`(`five_hour`·`seven_day` utilization·status)를 보면 된다. 한도 대기는 러너가 한다. 옛 `claude_usage_watch.py`는 11-25에 지워졌다.
- **리셋권(codex만):** myA0 `/home/bos/a0_limitwatch_r053r4_llama3b/codex_limit_watch.py`를 `$LIMITWATCH`로 복사한다. 띄우기 전에 `--read-now`로 사용량·reset 시각·리셋권을 기록한다. 99% 이상·한도 도달·usage-limit 대기면 리셋권을 한 번 쓴다. 같은 계정 감시는 한 서버에만 둔다. 리셋권이 0이면 99%에서 사용자에게 알린다.
  ```bash
  systemd-run --user --unit=codex2-reset-watch-r0NN-<model> ... $PY codex_limit_watch.py --codex-home $CODEX_HOME \
    --state-dir $LIMITWATCH/codex2 --threshold 99 --interval 300 --manifest <run>/manifest.txt --unit <run unit>
  ```

## 상태 보기

host에서 `ssh <서버> '…'`로 본다. 촘촘히 반복하지 않는다(몇 분 간격).

```bash
systemctl --user list-units --no-legend 'bringup-*' 'costguard-*' 'codex2-*'
tail -3 $CHECKOUT/bringup/runner-logs/<unit>.log
tail -5 <run>/manifest.txt                      # run_status, stop_stage, stop_reason
cat <run>/wrappers/status.json                  # drained, blocking
fuser -v /dev/bos/0; ls -l /dev/bos/0
ps -eo etime,cmd | grep "[r]un_device_command.py"
```

- 한 run에 launch가 여럿이면 마지막 `graph_launch=` 줄 뒤의 기록만 지금 상태다. 앞 launch의 `stop-device-work`를 지금 hang으로 읽지 않는다.

- stage 진행: `<run>/<NN>-<stage>.jsonl`(재개면 `.resume-N.jsonl`), autoport `doc/<stage>/work_log.md`, 러너 event `<run>/graph/events.jsonl`, unit log `$CHECKOUT/bringup/runner-logs/<unit>.log`.
- deepagents: `<run>/usage.jsonl`(role `stage`·`subagent:<name>`·`review`), Deep Agents 파일 `<run>/agent/`.
- wrapper 기록 `<run>/wrappers/*.json`, `status.json`(drained, blocking). 판독표는 [watcher.md](watcher.md) "감시".

## 재개

| 방식 | 언제 | 명령 |
|---|---|---|
| 같은 세션 | 인터럽트 없는 정지(실행 clone 그대로) | `resume.sh <run> <N> -` |
| 인터럽트 답 | 장치 정지(exit 126, `await_ack`), hold(exit 3, `graph-reconcile:<node>`, `await_hold`), report 끝(`await_selection`) | `resume-with.sh <run> '<JSON>'`. 장치 정지 `{"decision":"verified-resume","note":"<누구, 언제, verifier 통과 또는 재부팅>"}`, hold `{"decision":"resume"}`, report 끝 `{"decision":"resume","stage":<N>}`, 그만두기 `{"decision":"stop"}` |
| 새 세션 | plugin을 바꿨을 때, 러너나 Codex 계정을 바꿀 때 | `start.sh --skip-stage …` |

- 기다리는 인터럽트는 멈춘 launch의 log 끝이나 `run_bringup --graph-history <run>`(읽기 전용)으로 본다. 인터럽트에서 기다리는 run을 `resume.sh`로 재개하면 거부된다. 재개도 `launch-unit.sh`로 unit으로 띄운다.
- 운영자 재개는 그 stage 마지막 manifest 기록과 받아들인 `.ack`를 resume turn에 사실로 싣는다. 그 밖의 결정은 사용자 허락을 받아 `LAUNCH_NOTE`로 준다.
- 연속 run은 handoff가 기록된 뒤에는 Stage 7·8만 재개한다. handoff 전에 멈췄으면 Stage 7로 재개해 후보를 고른다.
- **장치 정지(126):** 러너 자동 검증이 통과하면 같은 launch에서 이어 간다(`device_verify_<n>=passed`). 실패했거나 holder가 남으면(`device-verifier-failed`) 아래 "멈추기"를 따른 뒤 `resume-with.sh`로 답한다.
- deepagents가 `turn-failed`(exit 5)·`goal-blocked`(exit 3)로 끝나면 운영자가 `resume.sh`로 같은 thread를 잇는다.

## 멈추기(장치 안전)

1. `touch <run>/wrappers/STOP`: 새 wrapper는 거부되고 진행 중인 명령은 끝까지 돈다.
2. `<run>/wrappers/status.json`이 `drained: true`, `blocking: []`가 될 때까지 기다린다.
3. 신호가 꼭 필요하면 확인한 wrapper PID에만 한 번 `kill -INT <wrapper-pid>`(`ps -p`로 먼저 확인). 반복 신호로 강제 종료하지 않는다.
4. wrapper가 끝나고 holder가 없을 때만 unit을 멈춘다(`systemctl --user stop <unit>.service`).
5. 멈춘 시각과 이유를 autoport `doc/INTERVENTIONS.md`에 적는다.

- codex 러너는 에이전트만 얼리려면 그 run의 app-server에 `kill -STOP`(operator.md "Stop")을 쓸 수 있다. deepagents·claude에는 옮겨 쓰지 않는다. 이미 시작한 리뷰는 unit stop 뒤에도 판정까지 돌 수 있다(장치 위험은 없으니 기다린다).
- 넓은 `pkill -f`, 장치를 연 프로세스 강제 종료, FLR, PCI remove/rescan, `tt-smi` reset을 하지 않는다.

wrapper가 `stop-device-work`(exit 126, 기한 종료 포함)로 끝났거나 wrapper 기록에 exit가 없으면(러너가 먼저 죽음):

- 장치를 다시 열지 않는다(`verify_device.py` 포함). hang 장치를 다시 열면 PCIe 이탈이 난다.
- **myA0:** 묻지 않고 [power.md](power.md) 절차(보드 off → 5초 → on → 5초 → 재부팅)로 복구한다. 횟수 제한은 없다.
- **다른 서버:** 명령 log 끝에 mesh close가 있고 holder가 없을 때만, 사용자 승인 뒤 verifier를 1회 돌린다. 그 밖에는 멈추고 사용자에게 재부팅을 요청한다.
- verifier가 통과했거나 재부팅한 뒤에는 `resume-with.sh <run> '{"decision":"verified-resume",...}'`로 같은 run을 잇는다. 러너가 `.ack`를 쓴다.
- 인터럽트 없이 launch drain에서 막힌 경우(`stop_reason=wrapper-drain-at-launch`)만 `.ack`(이유·누구·언제 한 줄)를 손으로 두고 `resume.sh`로 재개한다.

## 인증이 풀렸을 때

- **codex:** goal이 `blocked`여도 `codex login status`는 정상일 수 있다. thread 세션 기록에서 본다. `unauthorized`면 `CODEX_HOME=$CODEX_HOME $CODEX_BIN login` 뒤 같은 세션을 잇는다.
  ```bash
  T=$(grep -E "^stage_[0-9]+(_resume_[0-9]+)?_thread_id=" <run>/manifest.txt | tail -1 | cut -d= -f2)
  grep -a -o '"codex_error_info": *"[^"]*"' $(ls -t $CODEX_HOME/sessions/*/*/*/rollout-*${T}.jsonl | head -1) | tail -1
  ```
- **deepagents:** 인증은 API key 하나다. 오류가 이어지면 `turn-failed`로 끝나고 문장이 manifest `stage_N_turn_error`에 남는다. key·계정 문제면 key를 바로잡고 `resume.sh`로 잇는다. 한도·잔액 부족 때의 대응은 정해지지 않았다.

## 연속 run 후보와 serving stack

- **후보:** 러너가 entry stage 뒤 operator.md "Continuous run" 규칙으로 고르고 사용자 승인을 묻지 않는다. 고정하려면 `AVIRON_BRINGUP_SERVING_CANDIDATE`.
- **stack manifest는 run마다 새로 만든다.** 띄우기 직전 checkout으로, plugin checkout이 깨끗한지 확인한 뒤 만든다(남은 변경은 baseline이 된다). vLLM은 `python_env` 패키지로 기록된다.
  ```bash
  $PY $SK/scripts/serving_stack.py --create $CHECKOUT/bringup/serving/stack-<date>-<tag>.json \
    --plugin $REPO/vllm-aviron-plugin --installed
  ```
- `serving-complete` 뒤 plugin checkout이 baseline과 다르면, autoport를 지우기 전에 `third_party_patches/plugin.diff`와 대조하고 사용자에게 알린다. vLLM core를 고쳐야 하면 고친 것을 설치하고 새 manifest를 만든다.

## 산출물 백업

기존 산출물은 `$BACKUP`에 압축한다. `bringup/references/`는 다음 run이 읽으므로 남긴다.

**autoport:** run이 끝나면(`serving-complete`나 사용자가 정한 종료) 아래를 원본 삭제까지 한다(11-20 사용자 지시). 장치 명령이 돌거나 다른 run이 쓰는 동안에는 하지 않는다.

1. 측정 원자료는 버린다: `*.tracy`, `profile_log_device.csv`, `tracy_ops_times.csv`와 그 gzip 사본, 텐서(`*.pt`, `*.tensorbin`), `__pycache__`.
2. 나머지를 불투명 이름 `a0bk_<YYYYMMDDTHHMM>_<순번>.tgz`로 압축하고 `tar -d`로 대조한다.
3. `identical`이고 holder·refcnt가 0이면 원본을 지운다(`models/autoports/`는 빈 폴더로 둔다).
4. sungmin 백업 이름 대조표(예: `aviron-skills/rounds/051/조사/백업이름변경_myA0_20261120.md`)에 한 줄 더하고, run 기록에 경로·크기·삭제 시각을 적는다.

```bash
cd $CHECKOUT
SEQ=$(ls $BACKUP | sed -n 's/^a0bk_[0-9T]*_\([0-9]*\)\.tgz$/\1/p' | sort -n | tail -1); SEQ=$(printf %02d $((10#${SEQ:-0}+1)))
B=$BACKUP/a0bk_$(date +%Y%m%dT%H%M)_$SEQ.tgz; [ -e "$B" ] && exit 1
tar -czf "$B" -C models --exclude='*.pt' --exclude='*.tensorbin' --exclude='*.tracy' --exclude=profile_log_device.csv \
  --exclude=tracy_ops_times.csv --exclude='*.tracy.gz' --exclude='*_ops_times.csv.gz' --exclude=profile_log_device.csv.gz \
  --exclude=__pycache__ autoports/<model_dir> && tar -dzf "$B" -C models && echo identical
fuser /dev/bos/0; cat /sys/module/bos/refcnt          # 둘 다 비거나 0일 때만
rm -rf models/autoports/<model_dir> && ls -la models/autoports
```

- **이름에 모델·run 이름을 넣지 않는다.** stage 에이전트가 같은 사용자로 돌아 `find -iname "*<model>*"`로 이전 run 백업을 찾아 쓴 일이 있다(051 문제 9). 이름 대조는 sungmin 문서에만 둔다.
- 측정 원자료까지 필요하다고 사용자가 정하면, 버릴 파일만 따로 같은 방식으로 압축한다.
- run 폴더(`bringup/artifacts/multigoal-runs/<run>/`)는 사용자가 정한 경우에만 같은 방식으로 압축·대조한 뒤 지운다. 다른 서버의 산출물은 그 서버에서 압축·대조한 뒤 옮긴다.

## 사람 포팅 비교 측정(지시가 있을 때)

사람 포팅은 tt-metal-e2 `models/tt_transformers`(`DecodersPrecision.performance`)다. autoport와 같은 장치·같은 plugin 도구로 TTFT/TPS(batch 1, 6길이 × 3회, 출력 100 token)와 MMLU(1,368)를 재서 autoport Stage 6(`doc/benchmark/<후보>.json` `rows[].runs[2]`)과 비교한다.

- **시작점:** 최신 작업 폴더 백업을 풀고 `setup.sh`처럼 sed로 경로·모델·revision·run-id·`AP_CAND`를 바꾼다. myA0 `$BACKUP`: Llama 3.1 8B W8A8(051) `a0bk_20261120T1449_37.tgz`, Qwen3 4B W8A8(050) `a0bk_20261119T0850_22.tgz`, Llama 3B·8B(046~048, Python 3.10) `a0bk_20261115T1936_14.tgz`. 내용은 sungmin 백업 이름 대조표에 있다. 다 쓴 작업 폴더도 `tt_cache/`를 빼고 같은 방식으로 압축·대조한 뒤 지운다.
  - adapter `humanport_throughput.py`(`run_throughput --backend file:`)와 `mmlu_model/tt/generator.py`(`run_mmlu --backend generator`)는 그대로 쓰고, `mmlu_model/doc/model_contract.json`의 stop set만 모델 `generation_config.json` eos로 맞춘다.
- **환경:** `python_env`에 overlay(transformers 4.53.0, tokenizers 0.21.4, huggingface_hub 0.35.3)를 `PYTHONPATH` 맨 앞에 둔다(e2 in-tree `tt_transformers`가 4.53 기준). overlay는 `$PY -m pip install --no-deps --target <E>/py_overlay_tf453 …`로 만들고, `host_check.py` 결과 `packages`로 실제 import를 본다.
- **순서:** host 확인(wrapper) → devcheck → 128 1회를 손으로(log에서 W8A8 감지 "quant_method=compressed-tensors", INT8 weight cache, 입력 token sha가 autoport와 같음) → `all_rest.sh`를 user unit으로(처리량 17회 → MMLU smoke → MMLU 전체 → 끝 devcheck → 요약). Qwen3 4B는 약 45분, TT weight cache 약 4.6 GB.
- **다른 서버 autoport를 이 장치에서:** autoport backend는 checkout 안 `models.autoports.<slug>`로만 import한다. 이 서버 autoport의 sha256 목록을 쓰고 같은 파일시스템 안에서 옮긴 뒤, 다른 서버 autoport를 복사(`__pycache__`·Tracy 제외)해 그 Stage 6 명령 그대로 재고, 되돌린 뒤 목록과 대조한다. 바꾸기 전에 이 서버 autoport를 같은 수동 환경으로 한 번 재서 Stage 6 값과 맞는지 본다.

## 다른 모드(지시가 있을 때만)

- **report run:** script에서 `--serving-after`를 뺀다. Stage 6 뒤 `awaiting-user-selection`. 고른 후보는 별도 serving run으로 띄운다.
- **Stage 5에서 serving으로:** `--serving-after optimized-full-model`. MMLU가 없어 final default 품질 근거가 없다.
- **Stage 0만:** `--selection-only`. **별도 serving run:** `--serving-only`, `AVIRON_BRINGUP_SERVING_HANDOFF=<handoff>`(`serving_handoff.py create`), 재개는 Stage 7·8. **대화형:** operator.md "Interactive run".
- report run, serving run, 연속 run은 서로 재개할 수 없다.
