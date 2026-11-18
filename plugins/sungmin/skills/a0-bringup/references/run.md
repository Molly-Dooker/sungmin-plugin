# run 실행: skills clone에서 직접 돌리기

**별도 지시가 없으면 A0 bring-up run은 이 방식으로 돌린다.** 실행 clone의 플러그인 `aviron-model-bringup`을 clone 모드로 쓴다. 러너 `scripts/run_bringup`을 user systemd unit으로 띄우고(stage 에이전트는 launch마다 `--runner deepagents|codex`로 고른다, 아래 "러너 선택"), Stage 0 → 8을 연속 run(`--serving-after benchmark-candidates`)으로 끝까지 돈다(skills 0.48.0 이후 stage 번호). 명령은 모두 실행 서버에서 돌리고, 서버별 값은 sungmin `aviron-skills/startingpoint.md` "서버" 표에 있다.

- **러너 동작의 원본:** 플러그인 `skills/model-bringup/references/operator.md`(시작, 재개, 러너가 스스로 하는 일, serving, 연속 run, 종료 기록). 이 문서는 운영 값, 작업 폴더 script, 장치 안전 절차를 더한다. 둘이 다르면 operator.md를 따르고 이 문서를 고친다.
- 공통 운영 규칙(실행 clone 고정, 장치 안전, `LAUNCH_NOTE`, 백업)은 [../SKILL.md](../SKILL.md), 감시·복구 판단은 [watcher.md](watcher.md)에 있다.

```text
prepare refs (GPU host) -> precheck + devcheck -> dry-run -> launch unit + watch units
        -> stage 0..6 -> candidate -> stage 7..8 -> serving-complete -> report, backup
   on stop: STOP file -> drain -> (device stop? verify once with user ok) -> resume-with.sh verified-resume (runner writes .ack)
   waiting interrupt (126 await_ack, 3 await_hold): resume-with.sh; other stops: resume.sh
```

## stage와 러너

| Stage | 이름 | 장치 | 비고 |
|---:|---|:-:|---|
| 0 | reference-selection | 없음 | HF 분석과 참조 선택(exact·similar·blocks), host에서 돈다 |
| 1 | functional-decoder | 씀 | |
| 2 | optimized-decoder | 씀 | |
| 3 | full-model | 씀 | 통합, O0 anchor를 얼린다 |
| 4 | full-model-candidates | 씀 | 후보·fidelity·handover. 그 전에 HF 참조 `ensure` |
| 5 | optimized-full-model | 씀 | serving entry(품질 없음) |
| 6 | benchmark-candidates | 씀 | MMLU·TTFT/TPS 보고, serving entry(품질). 그 전에 참조 `ensure` |
| 7 | vllm | 씀 | serving |
| 8 | optimized-vllm | 씀 | serving |

- report run은 0~6이고, Stage 6 뒤 사용자 선택을 기다린다(`await_selection` 인터럽트).
- 연속 run은 `--serving-after benchmark-candidates`면 Stage 6 보고 뒤 러너가 후보를 골라 7 → 8을 이어 간다. `--serving-after optimized-full-model`이면 Stage 6을 건너뛰고, 품질이 `not-measured`다. `--serving-after`는 이 두 이름만 받고 숫자는 거부한다(0.47의 `5`가 지금의 benchmark-candidates다).
- 러너 프로세스는 두 러너 모두 LangGraph run graph(`graph_controller.py`; stage subgraph만 러너마다 다르다)이고, checkpoint는 `<run>/graph/checkpoint.sqlite`다. 상태의 원천은 `<run>/manifest.txt`다.
- Stage 7·8(serving)은 greedy만 받는다(temperature 0의 `top_k`·`top_p`·`min_p`는 greedy로 받는다).
- batch는 capacity 1 또는 4다(`--max-batch 1|4`). decode는 capacity 행으로 돌고 비활성 행은 −1이다. 규칙은 플러그인 `skills/model-bringup/references/batch_contract.md`에 있다.
- 새 run은 플러그인 revision 하나만 쓴다. 이전 revision 산출물은 그 revision의 checker로 판정하고, 새 run이 읽거나 재개하지 않는다.

## 러너 선택

한 plugin tree가 두 러너를 모두 돌리고, launch마다 고른다: `run_bringup --runner deepagents|codex`나 `AVIRON_BRINGUP_RUNNER`. **기본값이 없다.** 빠지면 아무것도 시작하지 않고 exit 2다. 사용자가 러너를 말하지 않았으면 묻는다. 원본은 operator.md "Choose the runner"다.

| | `deepagents` | `codex` |
|---|---|---|
| stage 에이전트 | Deep Agents 에이전트가 OpenAI 모델 API를 직접 부른다. skill pin, todo, 읽기 전용 subagent(`investigator`·`comparer`·`general-purpose`) | Codex app-server goal(stage마다 thread 하나, remediation goal) |
| 실제 launch에 필요한 것 | 러너 환경의 `OPENAI_API_KEY`(dry-run은 필요 없음) | `CODEX_BIN`(`codex-cli 0.169.1`만), plugin이 설치되고 로그인된 Codex home(`AVIRON_BRINGUP_CODEX_HOME`) |
| manifest | `runner=deepagents`, `model_api=openai`, `deepagents_version` 등 package 버전, graph `a0-graph-3`. `<run>/usage.jsonl` | `runner=codex`, `codex_home`·`codex_bin`·`codex_version`·`approval_policy`·`sandbox`·`installed_skills`, graph `a0-graph-2` |
| critical check 실패 | 같은 대화로 되돌린다(`--check-retries`, 기본 1) | remediation goal |
| 러너가 스스로 하는 것 | 모델 API 오류를 backoff로 재시도. stage launch 하나에 모델 호출 3000회(subagent 포함)면 `turn-failed`. usage limit 대기·checker 수정 없음 | usage limit 대기(30분마다, stage당 96회), 일시적 turn 오류 대기, host 실패 뒤 1회 재개, checker 수정 |

- **한 run은 한 러너다.** 매 launch가 manifest에 `runner=<이름>`을 적고, 재개(`resume.sh`, `resume-with.sh`)가 다른 러너면 거부한다. `history.sh`(`--graph-history`)는 러너 지정이 필요 없다.
- 모델 설정은 두 러너 모두 `AGENT_MODEL`·`AGENT_EFFORT`·`REVIEW_MODEL`·`REVIEW_EFFORT`다. codex 러너는 `CODEX_MODEL`·`CODEX_EFFORT`가 있으면 그것을 먼저 읽는다.
- run graph, stage check, 장치 wrapper, 리뷰 기록, skill, stage prompt는 두 러너가 함께 쓴다. 아래 절에서 러너 표시가 없는 것은 둘 다에 해당한다.
- 0.50.0 tree로는 어느 러너도 실제 run으로 확인되지 않았다(sungmin `aviron-skills/rounds/050/README.md`). 이 문서의 deepagents 쪽 절차는 operator.md와 러너 코드에서 옮긴 것이고 run으로 돌려 본 것이 아니다.

## 규칙

- **버전 경계:** 한 run은 한 version으로 시작하고 재개한다. 다른 minor로 시작한 run은 그 minor의 재개 tag clone으로만 재개한다(예: 0.48.x run → `v0.48.1`, 0.49.x run → `v0.49.4`, plugin `EARLIER_RELEASES`·README). patch는 같은 minor의 run을 재개한다(0.48.0 run → 0.48.1).
- **참조 설치:** `python_env`에는 참조 `tt_transformers`가 pin 하나만 설치된다. 러너는 설치 파일 hash를 실행 clone의 `PIN_SOURCE_HASH`와 대조해 다르면 launch 전에 멈춘다. 다른 version(재개 tag 포함)으로 돌리려면 그 version의 pin을 다시 설치한다(skills 루트 README "Build the run Python environment"). 예: 0.49.x는 `d92e67f`, 0.48.x는 `6054718`.
- **Codex 버전(codex 러너):** 러너가 Codex CLI 0.169.1만 받는다(`agent_backend.CODEX_VERSION`, dry-run도 확인). 0.49.3 이하로 시작한 run은 지금 환경(Python 3.12, 새 controller pin, Codex 0.169.1)에서 재개할 수 없다.
- **플러그인 모드:** clone 모드를 쓴다. 설치본 모드는 사용자가 지시할 때만 쓴다. clone + snapshot 모드(`AVIRON_BRINGUP_CHECKOUT_SNAPSHOT=1`)는 쓰지 않는다(040차 shared-code identity 실패).
- **환경 변수 이름:** 러너 변수는 `AVIRON_BRINGUP_*`다. 옛 `BOS_BRINGUP_*`가 하나라도 설정돼 있으면 러너가 시작을 거부한다(exit 2).
- **자동 checker 수정(codex 러너):** 끈다(`AVIRON_BRINGUP_AUTO_CHECKER_FIX=off`). checker 결함은 watcher가 run 밖에서 고친다. deepagents 러너에는 이 기능이 없다.
- **Codex home(codex 러너):** 실행 Codex home은 run 동안 러너만 쓴다. VS Code 확장·`codex mcp-server`·다른 app-server가 같은 home을 쓰면 한 프로세스의 토큰 갱신이 나머지에 401을 낸다. `CODEX_BIN`은 항상 실제 바이너리를 준다(PATH의 shim이면 `app-server --listen stdio://`를 못 띄운다).
- **호스트 메모리:** A0에 TT 모델이 올라가 있거나 장치 명령이 도는 중이면 HF 모델을 올리지 않는다.

## run 환경

tt-metal-e2 checkout 하나와 uv 가상환경 하나로 두 러너를 모두 돌린다. 구축 절차의 원본은 skills 루트 README "Build the run Python environment"이고, 여기에는 운영에서 걸리는 점만 적는다. 근거는 sungmin `aviron-skills/장기검토/구조개선검토/조사/DA_python환경통합_myA0_20261118.md` 10절이다.

```text
$REPO/tt-metal-e2        one checkout, built with python_env's Python 3.12
$REPO/python_env         uv venv --seed, Python 3.12 (runner packages of both runners, ttnn, serving stack)
$REPO/aviron-skills      execution clone: develop (runner chosen per launch: deepagents | codex)
```

- **tt-metal-e2 재빌드:** 반드시 환경을 PATH 앞에 두고 빌드한다. `build_metal.sh`는 PATH의 `python3`로 binding(`ttnn/ttnn/_ttnn.so`)을 만들어서, 그냥 돌리면 시스템 3.10 binding이 나와 `python_env`가 깨진다.
  ```bash
  cd $CHECKOUT && PATH=$REPO/python_env/bin:$PATH VIRTUAL_ENV=$REPO/python_env ./build_metal.sh --build-type Release
  $PY -c 'import ttnn; ttnn.bos_quantize_fused'   # then devcheck.sh (device smoke)
  ```
- **checkout 하나 = Python 하나:** `_ttnn.so` 이름에 Python 버전 표시가 없다. 한 checkout을 두 Python 버전 환경이 함께 쓸 수 없다. 다른 버전이 필요하면 별도 checkout에서 빌드한다.
- **`env_set.sh`:** venv 경로를 꼭 둘째 인자로 넘긴다(`source $CHECKOUT/env_set.sh bos $REPO/python_env`). 인자가 없으면 `$CHECKOUT/python_env`를 찾는데, 그 3.10 환경은 11-18에 지웠다(활성화 없이 지나간다).
- **uv:** `uv venv --seed`로 만든다(pip가 있어야 한다: `ensure_tools.py`, `prepare_references.py`가 `python -m pip`를 쓴다). Python은 `~/.local/share/uv/python/` 아래 uv 설치본이고, venv는 minor symlink(`cpython-3.12-…`)를 가리킨다. uv로 3.12 patch를 올리면 venv의 interpreter도 바뀌므로, 재현성을 따질 때는 `$PY -V`를 기록한다. `~/.local/share/uv/python/`을 지우면 환경이 깨진다.
- **pin:** `pyarrow==25.0.1`(26은 NumPy 2를 요구해 lm_eval import가 깨진다). 러너 package는 `requirements-da.txt` 하나다(Deep Agents, LangChain, LangGraph; launch 때 설치하지 않는다). 두 러너 모두 launch마다 설치된 버전을 pin과 대조해 다르면 시작을 거부한다(deepagents는 deepagents·langchain·langchain-openai·langgraph, codex는 LangGraph 쪽 package).
- **Codex:** `$CODEX_BIN`(`~/.local/bin/codex`)은 `codex update`로 올린다. 설치기가 `~/.bashrc` 끝에 PATH 줄을 더할 수 있다. 버전을 올리면 skills `agent_backend.CODEX_VERSION`과 맞아야 codex 러너가 시작한다.

## 준비 값

| 변수 | 값 |
|---|---|
| `CHECKOUT` | `$REPO/tt-metal-e2`(Python 3.12 빌드). commit을 바꾸면 아래 "run 환경"의 명령으로 다시 빌드한다 |
| `SK` | `$REPO/aviron-skills/plugins/aviron-model-bringup` |
| `PY` | `$REPO/python_env/bin/python`(Python 3.12, uv). 러너 package(`requirements-da.txt`), ttnn, serving stack(vLLM + BOS plugin), lm_eval, 참조 `tt_transformers`(pin, non-editable)가 모두 이 환경에 있다. 구축은 skills 루트 README "Build the run Python environment" |
| `STACK` | 이번 run용으로 새로 만든 serving stack manifest(`bringup/serving/stack-<date>-<tag>.json`) |
| `HF_MODEL`, `MODEL_DIR` | `MODEL_DIR=models/autoports/<model ID 소문자, 영숫자 밖은 _>` |

작업 폴더는 run마다 `$WORK_ROOT/r0NN_<model>_<batch>_<date>/`로 만든다. 직전 run의 작업 폴더에서 script(`launch.env`, `precheck.sh`, `devcheck.sh`, `start.sh`, `resume.sh`, `resume-with.sh`, `history.sh`, `launch-unit.sh`, `status.sh`, `diskguard.sh`, `watch_run0NN.py`, `waitev.sh`)를 복사해 모델·경로·batch·tag만 바꾼다. 실제 예는 myA0 `/home/bos/bt_work/r048_gemma4_e4b_w8a8_b4_0481_20261115/`(048 run 5, sungmin `aviron-skills/rounds/048/2_run/5_Gemma4_E4B_W8A8_b4_0481.md`)이다. 거기 `precheck.sh`·`devcheck.sh`의 `pgrep -af` 줄은 아래 "시작 전 확인"의 `ps … | grep` 줄로 바꾼다.

`launch.env`(`<…>` 자리는 [../SKILL.md](../SKILL.md) "환경 값"):

```bash
unset "${!BOS_BRINGUP_@}"   # old names: runner refuses to start (exit 2)
unset RUN_DIR RESUME_STAGE RUN_MULTIGOAL_LOG_DIR AVIRON_BRINGUP_CHECKOUT_SNAPSHOT AVIRON_BRINGUP_BATCH_SCOPE AVIRON_BRINGUP_MAX_BATCH LAUNCH_NOTE
export REPO=<REPO>
export CHECKOUT=$REPO/tt-metal-e2 SK=$REPO/aviron-skills/plugins/aviron-model-bringup
export PY=$REPO/python_env/bin/python STACK=<stack manifest>
export PYTHON_BIN=$PY
export AVIRON_BRINGUP_RUNNER=<deepagents|codex>   # no default: a launch without it exits 2; a resume must name the run's runner
export AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
unset CODEX_MODEL CODEX_EFFORT                    # the codex runner would read these before AGENT_*
export AGENT_MODEL=gpt-6.2-sol AGENT_EFFORT=medium REVIEW_MODEL=gpt-6.2-astra REVIEW_EFFORT=medium   # defaults
# codex runner only:
export CODEX_HOME=<CODEX_HOME>
export AVIRON_BRINGUP_CODEX_HOME=$CODEX_HOME
export CODEX_BIN=<CODEX_BIN>
export AVIRON_BRINGUP_AUTO_CHECKER_FIX=off
# deepagents runner only: OPENAI_API_KEY comes from the calling shell (never written into this file, a command line or a log)
export HF_MODEL=<org/model> MODEL_DIR=models/autoports/<model_dir>
export DEV=/dev/bos/0                             # devcheck.sh, diskguard.sh, costguard.sh read it
# server with several devices (AI001): the run uses one; wrappers and checks inherit it
# export TT_VISIBLE_DEVICES=0
```

offline·local only이므로 HF checkpoint, HF 참조, MMLU dataset cache는 run 전에 있어야 한다. 직전 run의 작업 폴더에서 복사한 `launch.env`는 0.49.x 것이라 러너 줄이 없고 `CODEX_MODEL`을 쓴다. 위 모양으로 고친다.

## HF 참조(GT)

- 위치는 `$CHECKOUT/bringup/references/<org>/<model>/<revision>/`이다. 만드는 방법은 `$SK/scripts/prepare_references.py` 하나다(`check`·`ensure`). 상세는 플러그인 `skills/full-model-candidates/references/reference_generation.md`에 있다.
- **참조는 run 전에 GPU host에서 만든다.** `AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY`를 빼고 checkout 루트에서 돌린다. run 안에서는 local only로 둔다. 그래야 run이 GPU host 상태에 묶이지 않는다.
  ```bash
  cd $CHECKOUT && env -u AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY PYTHON_BIN=$PY python3 $SK/scripts/prepare_references.py ensure --hf-model $HF_MODEL
  ```
- 장소는 GPU host → 로컬 GPU → CPU 순서다. GPU host는 git 추적 밖의 `bringup/reference_hosts.local.md`에 ` ```json ` block(`{"hosts": [{"name", "ssh", "workdir", "python", "min_free_gb", "max_gpu_util"}]}`)으로 적는다. 원격 venv는 `$PY`의 Python(3.12)·패키지 버전으로 만들고(원격에 3.12가 없으면 uv로 받는다) 끝나면 지운다.
- 러너는 launch마다 Stage 4·6 가운데 처음 도는 stage 앞에서 `ensure`를 부르고 끝날 때까지 기다린다(`<run>/references.log`). 준비되지 않으면 그 stage 전에 멈춘다(exit 8).
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
$PY -V                                                         # Python 3.12.x
$PY -c 'import tt_transformers; print(tt_transformers.__file__)'   # python_env site-packages 아래여야 한다
$PY -c 'import ttnn; print(ttnn.__file__)'                     # $CHECKOUT/ttnn/ttnn 아래여야 한다
$PY $SK/scripts/reference_source.py                            # 오류 없이 실행 clone의 pin commit이 나와야 한다
cd $CHECKOUT && git status --short | head -3 && git log --oneline -1
$PY -I $SK/runtime/readiness_check/e2_checkout.py --tt-metal-home $CHECKOUT | grep -E '"skips"|"commit"'
$PY -c 'import ttnn; ttnn.bos_quantize_fused'                  # W8A8: 오류 없어야 한다(참조가 부름, e2 f3348a2aac 이상)
ls -d $CHECKOUT/$MODEL_DIR                                     # 없어야 한다
ps -eo pid,etime,cmd | grep -E "[r]un_bringup|[r]un_device_command|[g]raph_controller|[v]llm serve|[E]ngineCore"   # 없어야 한다
fuser -v /dev/bos/0; lsmod | grep '^bos '                      # holder 없음, 셋째 칸 0
cat /sys/module/bos/refcnt                                     # 0. 공용 장치 서버는 fuser가 다른 사용자의 holder를 못 본다
df -h $CHECKOUT
$PY $SK/scripts/prepare_references.py check --python $PY --hf-model $HF_MODEL --model-dir $MODEL_DIR   # references ready
$PY $SK/scripts/serving_stack.py --manifest $STACK --installed
echo "$AVIRON_BRINGUP_RUNNER"                                  # deepagents 또는 codex
# codex 러너
$CODEX_BIN --version                                           # codex-cli 0.169.1
CODEX_HOME=$CODEX_HOME $CODEX_BIN login status
# deepagents 러너
test -n "$OPENAI_API_KEY" && echo key set                      # 값은 출력하지 않는다
```

- **W8A8 e2 op:** skills 0.49.1부터 참조(pin `d92e67f`)는 W8A8 activation을 `ttnn.bos_quantize_fused`로 양자화한다. 이 op이 없는 e2(`f3348a2aac` 앞, 예: `629307f1bc`)에서는 Stage 1에서 멈출 것이므로, 오류가 나면 run 전에 e2를 `develop` 최신으로 올려 Release로 다시 빌드한다. 러너는 이것을 보지 않는다(049 D3 사용자 결정, sungmin `aviron-skills/rounds/049/1_개선안.md`).
- **프로세스 확인:** `pgrep -f`는 쓰지 않는다. `ssh <server> '…'`로 돌리면 패턴이 원격 셸의 명령줄에도 들어가 pgrep이 그 셸을 찾는다. `ps … | grep "[r]un_…"`는 셸과 grep의 명령줄에 적힌 `[r]un_…`가 패턴과 맞지 않아 겹치지 않는다. 같은 ssh 명령 안에 괄호 없는 이름(예: `run_bringup`)을 함께 적으면 ps 줄도 그 셸을 찾으니 따로 돌린다(049 myA0 확인).
- **참조 pin:** `reference_source.py`가 "differs from the pinned source hash"로 실패하면 `python_env`에 다른 pin이 설치돼 있는 것이다. 위 "규칙"의 참조 설치를 따른다.
- 참조 `check`는 `--python`의 환경과 비교한다. 빼면 다른 환경과 비교해 차이가 크게 나온다. revision·protocol·파일 hash가 다르거나 세트가 없으면 not ready이고, run 전에 만든다.
- **장치 확인:** `devcheck.sh <작업 폴더>`로 wrapper 300 s 1회 `verify_device.py`를 돌려 pass·`mesh-close-confirmed`·holder 없음을 본다.
- **공용 장치(AI001):** 장치를 다른 사용자(docker 안 root 작업)와 함께 쓴다.
  - `fuser`는 다른 사용자의 holder를 보지 못하므로 `/sys/module/bos/refcnt`(`lsmod` 셋째 칸)가 0인지도 본다.
  - `devcheck.sh`·`start_unit.sh`는 refcnt가 0이 아니면 시작하지 않는다(050 run 2 작업 폴더).
  - 장치가 둘 이상인 서버는 `launch.env`에 `TT_VISIBLE_DEVICES`를 두어 run이 쓸 장치 하나만 보이게 한다. AI001은 `/dev/bos/0`(`01:00.0`, Gen4 x4)만 쓴다. `/dev/bos/1`은 x1 링크이고 다른 사용자가 쓴다.
- **autoport:** 이전 run의 autoport가 남아 있으면, 접거나 취소한 run이면 지운다. 결과가 있는 run이면 아래 "산출물 백업"대로 압축·대조한 뒤 지운다.

## dry-run

장치, 모델 API 호출, Codex turn 없이 prompt, manifest, tooling을 확인한다(deepagents는 key 없이 돈다. codex는 `CODEX_BIN` 버전을 확인한다). 새 run 폴더가 생기고, 확인 뒤 지운다. 러너를 둘 다 쓸 서버면 러너마다 한 번씩 돌린다.

```bash
./start.sh --dry-run
R=$(ls -td $CHECKOUT/bringup/artifacts/multigoal-runs/*/ | head -1)
grep -E "^(runner|model_api|deepagents_version|codex_home|codex_bin|codex_version|graph_schema_version|plugin_mode|plugin_version|plugin_revision|reference_commit|reference_source_hash|batch_scope_operator|serving_after|stop_after_stage|device_stop_verifier|launch_note|tooling_status|serving_candidate_preview|stage_[0-8]_dry_run)" $R/manifest.txt
```

볼 값은 다음과 같다.

- `runner=`가 고른 러너다. deepagents면 `model_api=openai`와 `deepagents_version`, graph `a0-graph-3`, codex면 `codex_home`·`codex_bin`·`codex_version=codex-cli 0.169.1`, graph `a0-graph-2`가 있다.
- `plugin_mode=clone`, `plugin_version`·`plugin_revision`이 실행 clone(tag), `reference_commit`이 skills pin과 같고 `reference_source_hash`가 있다.
- `serving_after=benchmark-candidates`, `stop_after_stage=8`, `batch_scope_operator`가 지시한 batch, `device_stop_verifier=all`.
- `launch_note` 줄이 없다.
- `tooling_status`에서 device_profiler·perf_report가 available이다.
- `stage_0_dry_run`~`stage_8_dry_run=true`.
- `serving_candidate_preview`는 새 run이면 Stage 5 기록이 없어 `unavailable:<경로>`다(정상).

## 시작

작업 폴더 script:

```bash
# start.sh [runner options]: new continuous run
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after benchmark-candidates --max-batch <1|4> "$@"

# resume.sh <run_dir> <stage> [note|-] [runner options]: same run, same thread (stop without an interrupt; a run waiting in an interrupt takes resume-with.sh)
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
export RUN_DIR=$1 RESUME_STAGE=$2
if [ -n "${3:-}" ] && [ "$3" != "-" ]; then export LAUNCH_NOTE=$3; fi
shift 3 2>/dev/null || shift $#
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after benchmark-candidates --max-batch <1|4> "$@"

# resume-with.sh <run_dir> '<JSON>' [runner options]: answer the interrupt the run waits in (device stop await_ack, hold await_hold)
source <work>/launch.env
unset AVIRON_BRINGUP_SERVING_HANDOFF AVIRON_BRINGUP_SERVING_CANDIDATE AUTOPORT_PRECISION_CONFIG LAUNCH_NOTE RUN_DIR RESUME_STAGE
export AVIRON_BRINGUP_SERVING_STACK_MANIFEST=$STACK
run=$1 answer=$2; shift 2
cd $CHECKOUT && exec $SK/scripts/run_bringup --serving-after benchmark-candidates --max-batch <1|4> --run-dir "$run" --resume-with "$answer" "$@"

# history.sh <run_dir>: read-only checkpoints and the interrupt the run waits in (no other option, starts nothing)
source <work>/launch.env
cd $CHECKOUT && exec $SK/scripts/run_bringup --graph-history "$1"

# launch-unit.sh <unit> <script> [args]: user systemd unit
cd $CHECKOUT && mkdir -p bringup/runner-logs
if [ "$AVIRON_BRINGUP_RUNNER" = deepagents ]; then systemctl --user import-environment OPENAI_API_KEY; fi   # deepagents: key to the user manager
systemd-run --user --unit="$1" -p KillMode=mixed -p TimeoutStopSec=1d -p OOMPolicy=continue \
  --working-directory=$CHECKOUT \
  -p StandardOutput=append:$CHECKOUT/bringup/runner-logs/$1.log \
  -p StandardError=append:$CHECKOUT/bringup/runner-logs/$1.log "${@:2}"
if [ "$AVIRON_BRINGUP_RUNNER" = deepagents ]; then systemctl --user unset-environment OPENAI_API_KEY; fi    # take it back once the unit runs
```

예: `./launch-unit.sh bringup-<model>-<tag>-$(date +%Y%m%dT%H%M) <work>/start.sh`. unit 이름은 `unit.txt`, run 폴더는 `run.txt`에 적는다(감시 script가 읽는다).

- **deepagents의 key:** unit은 셸 환경을 물려받지 않는다. `launch-unit.sh`를 부르는 셸에 `launch.env`를 source하고 `OPENAI_API_KEY`가 있어야 한다. systemd 249(Ubuntu 22.04)는 `systemd-run --setenv=OPENAI_API_KEY`(값 없는 형식)를 받지 않아 위처럼 user manager로 넘기고 바로 지운다(operator.md "Start a run"). key를 명령줄·log·파일에 쓰지 않는다. 러너는 key를 에이전트 shell·장치 wrapper·check에 넘기지 않는다.
  - key가 `~/.bashrc`의 interactive 구간에만 있으면(AI001), ssh 명령이나 unit 셸에는 없다. 작업 폴더에 `key.sh`(chmod 600)를 두고, `launch-unit.sh`가 deepagents일 때 `import-environment` 전에 source한다. 값은 출력하지 않는다.
    ```bash
    # key.sh (source it): OPENAI_API_KEY from ~/.bashrc into this shell, never printed
    if [ -z "${OPENAI_API_KEY:-}" ]; then eval "$(grep -E '^[[:space:]]*export[[:space:]]+OPENAI_API_KEY=' ~/.bashrc | tail -1)"; fi
    [ -n "${OPENAI_API_KEY:-}" ] || { echo "OPENAI_API_KEY missing" >&2; return 1 2>/dev/null || exit 1; }
    ```
  - 띄운 뒤 `systemctl --user show-environment | grep -c OPENAI_API_KEY`가 0인지 본다(050 run 2: 0).
- **codex:** 위 두 `systemctl` 줄은 돌지 않는다. `CODEX_BIN`·`AVIRON_BRINGUP_CODEX_HOME`은 `launch.env`가 준다.
- user unit으로 띄운다(`loginctl enable-linger`). 터미널에 묶이면 세션과 함께 죽는다.
- `KillMode=mixed`: unit을 멈추면 SIGTERM이 러너에만 간다. 러너는 새 장치 명령을 막고, 진행 중인 wrapper를 기한 안에 drain한 뒤 끝난다.
- `TimeoutStopSec`는 가장 긴 wrapper 기한 + 75 s보다 커야 한다.
- `OOMPolicy=continue`: OOM kill이 난 명령만 실패하고 unit은 남는다.
- 시작 뒤 확인: `systemctl --user is-active <unit>`, manifest `runner`·`plugin_version`·`reference_commit`·`graph_launch=fresh`·`stage_0_thread_id`.
- 모든 launch script의 mode option(`--serving-after`, `--max-batch`, `--skip-stage`)은 manifest와 같아야 한다. report run이면 `--serving-after`를 뺀다.
- **batch:** `--max-batch 1|4`. 4면 capacity 1·4, 1이면 capacity 1만이다. 재개는 기록값을 이어받는다.
- **끝난 stage부터 새 세션:** `--skip-stage <N>`을 준다(operator.md "Start a run").

## 감시 unit

run마다 세 개를 띄운다(run 감시, 디스크 보호, 그리고 codex는 리셋권 감시, deepagents는 비용 감시). 판단 규칙은 [watcher.md](watcher.md)다.

- **run 감시:** 직전 작업 폴더의 `watch_run0NN.py`를 복사한다(최신: 050 `watch_run050.py`). manifest 주요 줄, 비정상 wrapper 기록, 리뷰 verdict, unit 상태, unit 뒤 holder, 디스크를 30 s마다 `events.log`에 적는다. deepagents run에서는 `--usage-py <plugin>/skills/a0-bringup/scripts/usage.py`를 주면 `usage.jsonl` 합계를 60분마다 낸다. `waitev.sh [분]`은 중요한 줄이 생기거나 unit이 끝날 때까지 기다린다. 패턴에 `cost`·`turn_error`를 넣는다.
  ```bash
  systemd-run --user --unit=watch-r0NN-<model> -p StandardOutput=append:<work>/watch.out -p StandardError=append:<work>/watch.out \
    $PY <work>/watch_run0NN.py --name <name> --run-dir <run> --unit-file <work>/unit.txt --events <work>/events.log --disk-path $CHECKOUT
  ```
- **디스크 보호:** 직전 작업 폴더의 `diskguard.sh`(048 run 5)를 복사한다. 디스크 여유가 하한(인자, 048 run 5는 6 GB) 밑이면 아래 "멈추기" 1·2·4를 한다: `wrappers/STOP`, drained·holder 없음·wrapper 없음 확인, unit 정지. 장치가 바쁘면 unit을 멈추지 않고 그렇게 적는다. 아무것도 지우지 않는다. 러너는 디스크를 보지 않는다(049 D2 사용자 결정). 감시 script도 여유 15 GB 밑이면 `disk low`를 낸다. 048 run 5는 autoport가 98 GB까지 컸고(대부분 Tracy 원본), 0.49.1부터 stage가 profile 원본을 쓴 뒤 지운다.
  ```bash
  systemd-run --user --unit=diskguard-r0NN-<model> -p StandardOutput=append:<work>/diskguard.out -p StandardError=append:<work>/diskguard.out \
    bash <work>/diskguard.sh 6
  ```
- **비용 감시(deepagents 러너만):** 이 plugin의 `scripts/costguard.sh`가 60 s마다 `scripts/usage.py`로 `<run>/usage.jsonl`의 USD 추정을 계산한다.
  - 알림 단계(기본 25·50·100·200)마다 한 번 `events.log`에 `cost alert` 줄을 쓴다.
  - 상한에 닿으면 아래 "멈추기" 1·2·4를 한다. 아무것도 지우지 않는다.
  - 상한은 run 전에 사용자에게 묻는다(050 run 2: 300 USD, 실제 약 66.47 USD).
  - 단가는 `usage.py`의 `PRICE`이고, 모델이나 가격표가 바뀌면 고친다.
  - `watch_run050.py`의 `--cost-alerts`와 알림이 겹치므로, 둘 중 하나만 켠다. 감시 script 쪽을 끄려면 `--cost-alerts ""`로 띄운다.
  ```bash
  systemd-run --user --unit=costguard-r0NN-<model> -p StandardOutput=append:<work>/costguard.out -p StandardError=append:<work>/costguard.out \
    bash <plugin>/skills/a0-bringup/scripts/costguard.sh <work> <limit USD> 25,50,100,200
  ```
  `<plugin>`은 설치된 sungmin-plugin 경로다. 실행 서버에 없으면 두 파일을 작업 폴더로 복사해 쓴다.
- **리셋권 감시(codex 러너만):** deepagents run에는 띄우지 않는다(ChatGPT 계정 한도가 아니라 모델 API를 쓴다). 043 `codex_limit_watch.py`를 `$LIMITWATCH`로 복사한다. 띄우기 전에 `--read-now`로 사용량·reset 시각·남은 리셋권을 기록한다. 99% 이상, 한도 도달, usage-limit 대기 중 하나가 생기면 리셋권을 한 번 쓴다. 같은 계정 감시는 한 서버에만 둔다(041차, 서버 표). 리셋권이 0이면 99%에서 사용자에게 알린다.
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

- stage 진행은 `<run>/<NN>-<stage>.jsonl`(재개면 `.resume-N.jsonl`)과 autoport `doc/<stage>/work_log.md`에서 본다. 러너 event는 `<run>/graph/events.jsonl`이다.
- deepagents: 모델 호출마다 token 사용량이 `<run>/usage.jsonl`에 role(`stage`, `subagent:<name>`, `review`)과 함께 쌓인다. Deep Agents 자체 파일은 `<run>/agent/`다.
- wrapper 기록은 `<run>/wrappers/*.json`이다. 판독표는 [watcher.md](watcher.md) "감시"에 있다.

## 재개

| 방식 | 언제 | 방법 |
|---|---|---|
| 같은 세션 | 실행 clone이 그대로일 때, 인터럽트 없는 정지 | `resume.sh <run_dir> <stage> -`(새 메모 없이). `RESUME_STAGE`는 연속 run에서 0~8. manifest와 같은 `--skip-stage`·`--serving-after`·stack 내용 |
| 인터럽트 대기 | 장치 정지(exit 126, `await_ack`), hold(exit 3, `stop_reason=graph-reconcile:<node>`, `await_hold`), report run 끝(`await_selection`) | `resume-with.sh <run_dir> '<JSON>'`. 장치 정지는 `{"decision":"verified-resume","note":"<누구, 언제, verifier 통과 또는 재부팅>"}`, hold는 `{"decision":"resume"}`, report 끝은 `{"decision":"resume","stage":<N>}`. 그만두려면 `{"decision":"stop"}`. `resume.sh`(RUN_DIR+RESUME_STAGE)는 거부된다(exit 1, payload와 답 형식 출력) |
| 새 세션 | plugin을 바꿔 goal이 처음부터 읽어야 할 때, (codex 러너) Codex 계정을 바꿀 때 | `start.sh --skip-stage …`(새 run 폴더, 끝난 stage는 건너뜀) |

- **같은 러너로만 재개한다.** `launch.env`의 `AVIRON_BRINGUP_RUNNER`가 manifest `runner=`와 같아야 하고, 다르면 거부된다. 러너를 바꾸려면 새 세션(`start.sh --skip-stage …`)이다. 0.49.x로 시작한 run은 0.50.0이 거부하고 tag `v0.49.4` clone으로만 재개한다.
- 운영자 재개 launch는 그 stage 마지막 turn 뒤의 manifest 기록(terminal·check·review·`device_verify`·`run_status`·`stop_reason`)과 장치 정지 뒤 받아들인 `.ack`를 resume turn에 사실로 싣는다. 그 밖의 결정을 전해야 하면 사용자 허락을 받아 `LAUNCH_NOTE`로 준다.
- codex 러너: thread는 시작한 Codex home에서만 이어진다. deepagents 러너: stage thread는 run의 checkpoint 파일 안에 있다. deepagents 재개에도 `OPENAI_API_KEY`가 필요하다("시작"의 `launch-unit.sh`).
- 기다리는 인터럽트와 받는 답은 멈춘 launch의 log 끝이나 `history.sh <run>`(읽기 전용)으로 본다. 답 launch는 manifest에 `graph_launch=interrupted`와 `graph_resume_with=<답>`을 남긴다. 인터럽트 없는 정지(러너가 기록 없이 죽어 checkpoint가 pending, 기록된 정지로 graph가 끝남, launch drain이 막힘)는 `resume.sh`로 재개한다.
- 연속 run은 handoff가 기록된 뒤에는 Stage 7·8만 재개한다. handoff 전에 멈췄으면 `RESUME_STAGE=7`로 재개해 후보를 고른다.
- **장치 정지(126):** 러너 자동 검증(`--device-stop-verifier all`)이 통과하면 같은 launch에서 같은 stage를 횟수 한도 없이 이어 간다(`device_verify_<n>=passed`). 러너 검증이 실패했거나 holder가 남으면(`stop_reason=device-verifier-failed`) 아래 "멈추기"를 따른 뒤 `resume-with.sh`로 답한다(run은 `await_ack`에서 기다린다).
- 러너가 스스로 하는 재개와 종료 기록(`run_status`·exit)은 operator.md "What the runner does on its own"·"Continuous run"에 있다. codex 러너는 usage limit 대기, 일시적 turn 오류 대기, host 실패 뒤 1회 재개를 스스로 한다. deepagents 러너는 모델 API 오류를 backoff로 재시도할 뿐이고, 오류가 이어지거나 모델 호출 3000회에 닿으면 `stop_reason=turn-failed`(exit 5, `stage_N_turn_error`)로, 에이전트가 blocked로 닫으면 `goal-blocked`(exit 3, `stage_N_blocked_error`)로 끝난다. 둘 다 운영자가 `resume.sh`로 같은 thread를 잇는다. controller crash 뒤 checkpoint 재개는 두 러너가 같다.

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

러너별:

- 위 1~5는 두 러너가 같다. 장치 명령은 어느 러너든 러너가 `device_command` tool로 공용 wrapper를 띄우고, 정지 신호(unit stop의 SIGTERM)를 받으면 진행 중인 wrapper를 drain한다.
- **codex 러너:** 에이전트만 멈춰 새 명령이 나오지 않게 하려면 run의 app-server를 얼릴 수 있다(`kill -STOP <app-server-pid>`, operator.md "Stop"). PID는 `ps`로 그 run의 것임을 확인한다.
- **deepagents 러너:** 에이전트는 러너 프로세스 안에서 돈다. 에이전트만 얼리는 절차는 operator.md에 없다(정해지지 않음). codex의 `kill -STOP`을 러너 프로세스에 옮겨 쓰지 않는다. 위 1~5 그대로 멈춘다. 운영자 정지는 돌고 있는 subagent도 다음 모델 호출 전에 끝낸다. deepagents run에서 이 절차를 실제로 해 본 기록은 아직 없다.

하지 않는 것:

- 넓은 `pkill -f`를 쓰지 않는다.
- 장치를 연 프로세스를 강제로 죽이지 않는다. FLR, PCI remove/rescan, `tt-smi` reset을 하지 않는다. FW init이 실패하면 장치 작업을 멈추고 재부팅한다(사용자 확인).

wrapper가 `stop-device-work`(exit 126, 기한 종료 포함)로 끝났거나 wrapper 기록에 exit가 없으면(러너가 먼저 죽음):

- 장치를 다시 열지 않는다(`verify_device.py` 포함). hang 장치를 다시 열면 PCIe 이탈이 난다(026차 조사).
- 명령 log 끝에 mesh close가 있고 holder가 없을 때만, 사용자 승인 뒤 wrapper로 verifier를 1회 돌린다. 그 밖에는 재부팅한다.
- verifier가 통과했거나 재부팅한 뒤에는 `resume-with.sh <run> '{"decision":"verified-resume","note":"<누구, 언제, verifier 통과 또는 재부팅>"}'`로 같은 run을 재개한다. 러너가 blocking 기록마다 `wrappers/<registration>.ack`에 note를 적고 drain한 뒤 같은 stage thread를 잇는다. `.ack`를 손으로 쓰고 `resume.sh`로 띄우면 거부된다.
- 인터럽트 없이 launch drain에서 막힌 경우(러너가 장치 명령 중에 죽음, `stop_reason=wrapper-drain-at-launch`)만 `.ack`(이유·누구·언제 한 줄)를 손으로 두고 `resume.sh`로 재개한다. drain은 ack된 기록을 해결로 치고 원래 기록은 그대로 둔다. registry를 옮기거나 새 run을 띄우지 않는다.
- `continue-stage`로 끝난 명령 실패는 drain을 막지 않는다.

## 인증이 풀렸을 때

**codex 러너:** goal이 `blocked`로 끝나도 `codex login status`는 정상으로 보일 수 있다. thread의 세션 기록에서 확인한다.

```bash
T=$(grep -E "^stage_[0-9]+(_resume_[0-9]+)?_thread_id=" <run>/manifest.txt | tail -1 | cut -d= -f2)
grep -a -o '"codex_error_info": *"[^"]*"' $(ls -t $CODEX_HOME/sessions/*/*/*/rollout-*${T}.jsonl | head -1) | tail -1
```

`unauthorized`면 `CODEX_HOME=$CODEX_HOME $CODEX_BIN login`으로 다시 로그인하고 같은 세션을 이어 간다.

**deepagents 러너:** 인증은 `OPENAI_API_KEY` 하나다. 로그인 상태나 Codex home이 없다. key가 없으면 실제 launch가 시작 전에 거부된다. run 중 API 오류는 러너가 backoff로 재시도하고, 이어지면 `turn-failed`(exit 5)로 끝나며 오류 문장이 manifest `stage_N_turn_error`와 unit log에 남는다. 그것을 읽고 key·계정 문제면 셸의 key를 바로잡은 뒤 `resume.sh`로 같은 thread를 잇는다. key가 틀렸거나 계정 한도·잔액이 모자랄 때 어떤 오류로 나타나는지, 한도에 걸렸을 때 기다릴지 멈출지는 아직 정해지지 않았다(run 기록 없음, 러너에 한도 대기가 없음).

## 연속 run 후보와 serving stack

- **후보:** 러너가 entry stage(Stage 6, `--serving-after optimized-full-model`이면 Stage 5) 뒤 operator.md "Continuous run" 규칙으로 고르고 사용자 승인을 묻지 않는다. 고정하려면 `AVIRON_BRINGUP_SERVING_CANDIDATE`를 준다.
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

## 사람 포팅 비교 측정(지시가 있을 때)

사람 포팅은 tt-metal-e2 `models/tt_transformers`(`DecodersPrecision.performance`)다. autoport와 같은 장치·같은 plugin 도구로 TTFT/TPS(batch 1, 6길이 × 3회, 출력 100 token)와 MMLU(1,368)를 재서 autoport Stage 6(`doc/benchmark/<후보>.json` `rows[].runs[2]`)과 비교한다.

- **시작점:** 최신 작업 폴더 백업을 풀고 `setup.sh`처럼 sed로 경로·모델·revision·run-id·`AP_CAND`를 바꾼다.
  - Qwen3 4B W8A8: `/home/bos/_backup/humanport_measurements_r050_qwen3_4b_w8a8_20261119_nocache.tgz`
  - Llama 3B·8B: `humanport_measurements_r046_r048_20261115T1936_nocache.tgz`
  - adapter `humanport_throughput.py`(`run_throughput --backend file:`)와 `mmlu_model/tt/generator.py`(`run_mmlu --backend generator`)는 046부터 그대로다. `mmlu_model/doc/model_contract.json`의 stop set만 모델 `generation_config.json` eos로 맞춘다.
- **환경:**
  - `python_env`(3.12)에 overlay(transformers 4.53.0, tokenizers 0.21.4, huggingface_hub 0.35.3)를 `PYTHONPATH` 맨 앞에 둔다. e2 in-tree `tt_transformers`가 transformers 4.53 기준이다.
  - overlay는 백업에 없으니 `$PY -m pip install --no-deps --target <E>/py_overlay_tf453 …`로 만든다.
  - 옛 `python_env_ttt`(3.10)는 없어졌고 e2 `_ttnn.so`는 3.12로 빌드돼 있다(050).
  - host 확인(`host_check.py`) 결과 json의 `packages`로 overlay가 실제로 import되는지 본다.
- **순서:**
  1. host 확인(wrapper)
  2. devcheck
  3. 128 1회를 손으로 돌린다. log에서 W8A8 감지("quant_method=compressed-tensors"), INT8 weight cache(`*_ds_6bank_dtype_INT8`), 입력 token sha가 autoport와 같음을 확인한다.
  4. `all_rest.sh`를 user unit으로 띄운다: 처리량 17회 → MMLU smoke → MMLU 전체 → 끝 devcheck → 요약.
  - Qwen3 4B는 약 45분이다(처리량 6분, MMLU 35분). TT weight cache가 작업 폴더에 약 4.6 GB 생긴다.
- **preflight:** 패턴은 `[r]un_bringup|[g]raph_controller|[r]un_device_command.py|[v]llm`처럼 괄호를 넣어, ssh 명령줄 자신을 잡지 않게 한다(049).
- **다른 서버 autoport를 이 장치에서:** autoport backend는 checkout 안 `models.autoports.<slug>`로만 import한다. 그래서 순서대로 한다.
  1. 이 서버 autoport의 sha256 목록을 쓰고 같은 파일시스템 안에서 옮긴다.
  2. 다른 서버 autoport를 복사한다(`__pycache__`·Tracy 원자료 제외).
  3. 그 Stage 6 명령 그대로 잰다.
  4. 되돌린 뒤 목록과 대조한다.
  - 자리를 바꾸기 전에 이 서버 autoport를 같은 수동 환경으로 한 번 재서 Stage 6 값과 맞는지 본다(050, sungmin `aviron-skills/rounds/050/조사/AI001_autoport_myA0_재측정_20261119.md`).

## 다른 모드(지시가 있을 때만)

- **report run:** `--serving-after`를 뺀다. Stage 6 뒤 `run_status=awaiting-user-selection`으로 끝나고 `await_selection`에서 기다린다. 같은 run의 stage를 다시 돌리려면 `{"decision":"resume","stage":<payload stages 중 하나>}`로 답한다. 고른 후보는 별도 serving run으로 띄운다.
- **Stage 5에서 serving으로:** `--serving-after optimized-full-model`. MMLU가 없어 final default를 쓸 품질 근거가 없다.
- **Stage 0만:** `--selection-only`.
- **별도 serving run:** `--serving-only`, `AVIRON_BRINGUP_SERVING_HANDOFF=<handoff>`(`serving_handoff.py create`로 만든 것). 재개는 `RESUME_STAGE=7|8`.
- **대화형:** operator.md "Interactive run".
- report run, serving run, 연속 run은 서로 재개할 수 없다.
