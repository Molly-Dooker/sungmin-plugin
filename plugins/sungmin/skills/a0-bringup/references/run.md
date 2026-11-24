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
- 러너 프로세스는 두 러너 모두 LangGraph run graph(`graph_controller.py`; stage subgraph만 러너마다 다르다. 0.51.0부터 러너별 코드는 `scripts/runners/codex/`·`scripts/runners/deepagents/`)이고, checkpoint는 `<run>/graph/checkpoint.sqlite`다. 상태의 원천은 `<run>/manifest.txt`다.
  - deepagents checkpoint는 0.51.0부터 stage thread만 저장한다(리뷰어·subagent는 저장하지 않는다). 0.50.0 run 2는 이 파일이 1.7 GB였고 88%가 리뷰어·subagent 몫이었다(sungmin `aviron-skills/rounds/051/조사/checkpoint_크기_분석_20261119.md`).
- Stage 7·8(serving)은 greedy만 받는다(temperature 0의 `top_k`·`top_p`·`min_p`는 greedy로 받는다).
- batch는 capacity 1 또는 4다(`--max-batch 1|4`). decode는 capacity 행으로 돌고 비활성 행은 −1이다. 규칙은 플러그인 `skills/model-bringup/references/batch_contract.md`에 있다.
- 새 run은 플러그인 revision 하나만 쓴다. 이전 revision 산출물은 그 revision의 checker로 판정하고, 새 run이 읽거나 재개하지 않는다.

## 러너 선택

한 plugin tree가 여러 러너를 돌리고, launch마다 고른다: `run_bringup --runner deepagents|codex|claude`(`claude`는 0.54.0부터)나 `AVIRON_BRINGUP_RUNNER`. **기본값이 없다.** 빠지면 아무것도 시작하지 않고 exit 2다. 사용자가 러너를 말하지 않았으면 묻는다. 원본은 operator.md "Choose the runner"다.

| | `deepagents` | `codex` |
|---|---|---|
| stage 에이전트 | Deep Agents 에이전트가 모델 API(OpenAI, 또는 `claude-…` 모델이면 Anthropic)를 직접 부른다. skill pin, todo, 읽기 전용 subagent(`investigator`·`comparer`·`general-purpose`) | Codex app-server goal(stage마다 thread 하나, remediation goal) |
| 실제 launch에 필요한 것 | 러너 환경의 모델 API key: `OPENAI_API_KEY`, Claude 모델이면 `ANTHROPIC_API_KEY`(dry-run은 필요 없음) | `CODEX_BIN`(0.53.x는 `codex-cli 0.169.1`만, 0.54.0부터 설치된 버전), plugin이 설치되고 로그인된 Codex home(`AVIRON_BRINGUP_CODEX_HOME`) |
| manifest | `runner=deepagents`, `model_api=openai`(Claude 모델이면 `anthropic`과 `langchain_anthropic_version`), `deepagents_version` 등 package 버전, graph `a0-graph-3`. `<run>/usage.jsonl` | `runner=codex`, `codex_home`·`codex_bin`·`codex_version`·`approval_policy`·`sandbox`·`installed_skills`, graph `a0-graph-2` |
| critical check 실패 | 같은 대화로 되돌린다(`--check-retries`, 기본 1) | remediation goal |
| 러너가 스스로 하는 것 | 모델 API 오류를 backoff로 재시도. stage launch 하나에 모델 호출 3000회(subagent 포함)면 `turn-failed`. usage limit 대기·checker 수정 없음 | usage limit 대기(30분마다, stage당 96회), 일시적 turn 오류 대기, host 실패 뒤 1회 재개, checker 수정 |

- **한 run은 한 러너다.** 매 launch가 manifest에 `runner=<이름>`을 적고, 재개(`resume.sh`, `resume-with.sh`)가 다른 러너면 거부한다. `history.sh`(`--graph-history`)는 러너 지정이 필요 없다.
- 모델 설정은 모든 러너가 `AGENT_MODEL`·`AGENT_EFFORT`·`REVIEW_MODEL`·`REVIEW_EFFORT`다. codex 러너는 `CODEX_MODEL`·`CODEX_EFFORT`가 있으면 그것을 먼저 읽는다.
- **`claude` 러너(0.54.0, sungmin `aviron-skills/rounds/054/`):** stage 에이전트는 Claude Code CLI(`CLAUDE_BIN`; 비대화 ssh에는 `~/.local/bin`이 PATH에 없으니 `CLAUDE_BIN=$HOME/.local/bin/claude`를 준다)이고 `~/.claude`의 claude.ai 로그인을 쓴다(API key는 넘기지 않는다). 기본 `claude-sonnet-5-5`·리뷰 `claude-opus-5-5`, effort `medium`, 요약 모델 없음(Claude Code 자체 compaction). 리뷰어도 Claude Code(`Read`·`Grep`·`Glob`만), stage 에이전트는 `RemoteTrigger`·`CronCreate`·`EnterWorktree` 금지. graph·도구·check·usage limit 대기는 codex 러너와 같다(`a0-graph-2`). manifest `runner=claude`, `claude_bin`·`claude_bin_target`·`claude_version`·`claude_auth`·`permission_mode`. 실제 run: 054 run 1(0.54.0)·run 2(0.54.1), myA0 Llama 3.2 3B W8A8 b4, 둘 다 `serving-complete`(9시간 3분·8시간 11분). `autoUpdates: false`여도 Claude Code가 run 도중 바뀔 수 있다(054 run 2, 11-24 06:35 `2.1.330` → `2.1.331`, 원인 미확인). run 감시가 "codex version changed … (Claude Code)" 줄을 내면 run 기록에 시각을 적는다.
- **deepagents의 모델 API는 모델 이름이 고른다(skills `v0.51.0` `b9546c7`부터):** `claude-`로 시작하면 Anthropic API, 아니면 OpenAI다. 따로 고르는 option은 없다. Claude stage 모델이면 대화 요약만 `claude-haiku-5-5`가 쓴다(skills 051-12; `usage.jsonl`의 `model`로 보이고 `usage.py`에 단가가 있다). OpenAI는 stage 모델이 요약한다.
  - Anthropic으로 돌리려면 `launch.env`에 `AGENT_MODEL=claude-sonnet-5-5`를 준다. 그러면 주지 않은 설정의 기본값이 `AGENT_EFFORT=medium`, `REVIEW_MODEL=claude-opus-5-5`, `REVIEW_EFFORT=medium`이 된다(skills `124fc73`부터, 051-15 사용자 결정; 그 앞 0.51.0 tree는 `high`). effort 값은 `low|medium|high|xhigh|max`다. subagent는 stage 모델·effort를 쓰고, 요약은 Claude stage 모델이면 `claude-haiku-5-5`가 stage effort로 쓴다. 재개는 run에 기록된 effort를 이어받는다.
  - key는 `ANTHROPIC_API_KEY`다(두 모델이 서로 다른 API면 key 둘 다). workspace에 묶이지 않은 key면 `ANTHROPIC_WORKSPACE_ID`도 준다(러너가 header로 보낸다; 실제 API로 확인한 적 없음).
  - 아래 절의 `OPENAI_API_KEY`(시작 전 확인, `launch-unit.sh`의 `import-environment`·`unset-environment`, `key.sh`, 재개)는 Anthropic run에서 `ANTHROPIC_API_KEY`로 바꿔 읽는다.
  - 11-19 myA0에서 장치 없이 실제 호출로만 확인했다(Deep Agents + Sonnet 5.5·Opus 5.5, 러너 리뷰어 경로). Anthropic 모델로 돈 stage run은 아직 없다(sungmin `aviron-skills/rounds/051/조사/anthropic_deepagents_20261119.md`).
- run graph, stage check, 장치 wrapper, 리뷰 기록, skill, stage prompt는 두 러너가 함께 쓴다. 아래 절에서 러너 표시가 없는 것은 둘 다에 해당한다.
- 0.50.0은 050차 두 run(myA0 codex, AI001 deepagents, Qwen3 4B W8A8 b4)이 `serving-complete`로 확인했다(sungmin `aviron-skills/rounds/050/README.md`). 0.51.0(러너 코드 분리, deepagents checkpoint, 요약 뒤 skill pin, skills 세부의 `references/` 이동)은 051 run 4(myA0 Llama 3.1 8B W8A8 b1, deepagents + Claude)가 `serving-complete`로 확인했다(sungmin `aviron-skills/rounds/051/README.md`; codex 러너로는 돌지 않음). 0.52.0(`v0.52.0` = `40e8809`, 11-20)은 host 시험과 dry-run만 거쳤고 실제 run이 없다(sungmin `aviron-skills/rounds/052/README.md`). 운영자에게 보이는 0.52.0 변경: Claude stage 요약 trigger 110,000(OpenAI 170,000), Claude Stage 3·4·7·8 stage 에이전트 cache TTL 1시간(`usage.py`가 2배로 계산), 운영자 정지가 진행 중인 리뷰도 다음 모델 호출 전에 끝냄, 두 러너 규칙 text에 stage별 계약 reference 목록, codex compaction 경고(runner log `WARNING: Codex compacted the conversation`), Stage 7 checker의 version-1 adapter `reload_inputs` 검사.

## 규칙

- **버전 경계:** 한 run은 한 version으로 시작하고 재개한다. 다른 minor로 시작한 run은 그 minor의 재개 tag clone으로만 재개한다(예: 0.48.x run → `v0.48.1`, 0.49.x run → `v0.49.4`, 0.50.x run → `v0.50.0`, 0.51.x run → `v0.51.0`, plugin `EARLIER_RELEASES`·README). patch는 같은 minor의 run을 재개한다(0.48.0 run → 0.48.1).
- **참조 설치:** `python_env`에는 참조 `tt_transformers`가 pin 하나만 설치된다. 러너는 설치 파일 hash를 실행 clone의 `PIN_SOURCE_HASH`와 대조해 다르면 launch 전에 멈춘다. 다른 version(재개 tag 포함)으로 돌리려면 그 version의 pin을 다시 설치한다(skills 루트 README "Build the run Python environment"). 예: 0.49.x는 `d92e67f`, 0.48.x는 `6054718`.
- **Codex 버전(codex 러너):** 0.53.x까지는 러너가 Codex CLI 0.169.1만 받는다(0.51.0부터 `scripts/runners/codex/agent_backend.py`의 `CODEX_VERSION`, 0.50.0은 `scripts/agent_backend.py`; dry-run도 확인). 0.54.0부터는 pin이 없다(11-23 사용자 결정, Claude Code도 같음): 설치된 버전으로 돌고, launch·재개마다 `codex_version`(claude는 `claude_version`)을 manifest에 남긴다. 업데이트 뒤 첫 run은 그 버전에서 검증되지 않은 것으로 본다. 0.49.3 이하로 시작한 run은 지금 환경(Python 3.12, 새 controller pin, Codex 0.169.1)에서 재개할 수 없다.
- **run 중 시험:** run이 도는 서버에서 skills plugin `tests/` 전체를 돌리지 않는다. `tests/test_device_command.py`의 wrapper가 run과 같은 host 잠금(`host_exclusion`)을 잡아, run의 장치 명령이 exit 125(`external-host-work`)로 거절되거나 시험이 실패한다(051 run 3 중 사본 시험에서 35 failed). 사본에서도 같다. 장치 wrapper를 쓰지 않는 시험 파일만 돌리거나 run이 끝난 뒤 돌린다. subagent에 시험을 맡길 때도 이렇게 적는다.
- **플러그인 모드:** clone 모드를 쓴다. 설치본 모드는 사용자가 지시할 때만 쓴다. clone + snapshot 모드(`AVIRON_BRINGUP_CHECKOUT_SNAPSHOT=1`)는 쓰지 않는다(040차 shared-code identity 실패).
- **환경 변수 이름:** 러너 변수는 `AVIRON_BRINGUP_*`다. 옛 `BOS_BRINGUP_*`가 하나라도 설정돼 있으면 러너가 시작을 거부한다(exit 2).
- **Codex home(codex 러너):** 실행 Codex home은 run 동안 러너만 쓴다. VS Code 확장·`codex mcp-server`·다른 app-server가 같은 home을 쓰면 한 프로세스의 토큰 갱신이 나머지에 401을 낸다. `CODEX_BIN`은 항상 실제 바이너리를 준다(PATH의 shim이면 `app-server --listen stdio://`를 못 띄운다).
- **성능 잡음:** 같은 모델·같은 코드 경로라도 run 사이 decode 시간이 약 2~4% 오간다(tt-metal-e2 DRAM 배치 효과, sungmin `aviron-skills/rounds/053/조사/serving_성능_분석.md`, 053 run 3 native −4%). 이 범위의 차이를 skills 변경의 효과로 판단하지 않는다.
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
- **Codex:** `$CODEX_BIN`(`~/.local/bin/codex`)은 `codex update`로 올린다. 설치기가 `~/.bashrc` 끝에 PATH 줄을 더할 수 있다. 0.53.x 러너는 skills `scripts/runners/codex/agent_backend.py`의 `CODEX_VERSION`과 맞아야 시작한다. 0.54.0 러너는 버전을 확인하지 않는다.

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
export AVIRON_BRINGUP_RUNNER=<deepagents|codex|claude>   # no default: a launch without it exits 2; a resume must name the run's runner
export AVIRON_BRINGUP_REFERENCE_LOCAL_ONLY=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
unset CODEX_MODEL CODEX_EFFORT                    # the codex runner would read these before AGENT_*
export AGENT_MODEL=gpt-6.2-sol AGENT_EFFORT=medium REVIEW_MODEL=gpt-6.2-astra REVIEW_EFFORT=medium   # defaults
# deepagents on Anthropic models instead (the three others are then the defaults):
# export AGENT_MODEL=claude-sonnet-5-5 AGENT_EFFORT=medium REVIEW_MODEL=claude-opus-5-5 REVIEW_EFFORT=medium
# codex runner only:
export CODEX_HOME=<CODEX_HOME>
export AVIRON_BRINGUP_CODEX_HOME=$CODEX_HOME
export CODEX_BIN=<CODEX_BIN>
# claude runner only (0.54.0):
# export CLAUDE_BIN=$HOME/.local/bin/claude
# deepagents runner only: OPENAI_API_KEY (Claude models: ANTHROPIC_API_KEY) comes from the calling shell (never written into this file, a command line or a log)
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
$CODEX_BIN --version                                           # 0.53.x: codex-cli 0.169.1; 0.54.0: 기록만
CODEX_HOME=$CODEX_HOME $CODEX_BIN login status
# deepagents 러너
test -n "$OPENAI_API_KEY" && echo key set                      # 값은 출력하지 않는다. Claude 모델이면 ANTHROPIC_API_KEY
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
- **autoport:** 이전 run의 autoport가 남아 있으면, 접거나 취소한 run이면 지운다. 결과가 있는 run이면 아래 "산출물 백업"대로 측정 원자료를 빼고 압축·대조한 뒤 지운다.

## dry-run

장치, 모델 API 호출, Codex turn 없이 prompt, manifest, tooling을 확인한다(deepagents는 key 없이 돈다. codex는 `CODEX_BIN` 버전을 확인한다). 새 run 폴더가 생기고, 확인 뒤 지운다. 러너를 둘 다 쓸 서버면 러너마다 한 번씩 돌린다.

지울 폴더는 dry-run이 rc 0으로 끝났고, 앞뒤 폴더 목록을 비교해 새로 생긴 것이 정확히 하나일 때 그 폴더뿐이다. rc가 0이 아니면 지울 것이 없다. "가장 새 폴더"(`ls -td … | head -1`)를 지우지 않는다: 051 run 1(11-19 14:39)에서 dry-run이 rc 2로 폴더를 만들지 않아, 돌고 있던 run 폴더가 지워졌다.

```bash
RUNS=$CHECKOUT/bringup/artifacts/multigoal-runs
ls $RUNS > runs_before.txt   # 작업 폴더에서
./start.sh --dry-run; echo rc=$?
NEW=$(comm -13 runs_before.txt <(ls $RUNS)); echo "new=$NEW"   # rc 0이고 정확히 한 줄일 때만 R로 쓴다
R=$RUNS/$NEW
grep -E "^(runner|model_api|deepagents_version|codex_home|codex_bin|codex_version|graph_schema_version|plugin_mode|plugin_version|plugin_revision|reference_commit|reference_source_hash|batch_scope_operator|serving_after|stop_after_stage|device_stop_verifier|launch_note|tooling_status|serving_candidate_preview|stage_[0-8]_dry_run)" $R/manifest.txt
```

볼 값은 다음과 같다.

- `runner=`가 고른 러너다. deepagents면 `model_api=openai`(Claude 모델이면 `model_api=anthropic`, `model=claude-sonnet-5-5`, `review_model=claude-opus-5-5`, `review_effort=medium`)와 `deepagents_version`, graph `a0-graph-3`, codex면 `codex_home`·`codex_bin`·`codex_version`(0.53.x는 `codex-cli 0.169.1`), graph `a0-graph-2`가 있다.
- `plugin_mode=clone`, `plugin_version`·`plugin_revision`이 실행 clone(tag), `reference_commit`이 skills pin과 같고 `reference_source_hash`가 있다.
- `serving_after=benchmark-candidates`, `stop_after_stage=8`, `batch_scope_operator`가 지시한 batch, `device_stop_verifier=all`.
- `launch_note` 줄이 없다.
- `tooling_status`에서 device_profiler·perf_report가 available이다.
- `stage_0_dry_run`~`stage_8_dry_run=true`.
- `serving_candidate_preview`는 새 run이면 Stage 5 기록이 없어 `unavailable:<경로>`다(정상).

확인이 끝나면 위 조건(rc 0, 새 폴더 정확히 하나, 그 manifest에 `stage_0_dry_run=true`)을 다시 보고 `rm -rf "$R"` 한 뒤, `ls $RUNS`가 `runs_before.txt`와 같은지 본다.

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
  - 단가는 `usage.py`의 `PRICE`이고, 모델이나 가격표가 바뀌면 고친다. Sonnet 5.5·Opus 5.5 가격이 들어 있고(2026-11-03 표), Anthropic의 cache write(`usage.jsonl`의 `cache_write`)는 입력가의 1.25배로 센다.
  - Anthropic cache는 5분 뒤 사라진다. 장치 명령이 길면 `cache_write`가 커지므로 첫 Anthropic run에서 `cached`·`cache_write` 비율을 본다.
  - `watch_run050.py`의 `--cost-alerts`와 알림이 겹치므로, 둘 중 하나만 켠다. 감시 script 쪽을 끄려면 `--cost-alerts ""`로 띄운다.
  ```bash
  systemd-run --user --unit=costguard-r0NN-<model> -p StandardOutput=append:<work>/costguard.out -p StandardError=append:<work>/costguard.out \
    bash <plugin>/skills/a0-bringup/scripts/costguard.sh <work> <limit USD> 25,50,100,200
  ```
  `<plugin>`은 설치된 sungmin-plugin 경로다. 실행 서버에 없으면 두 파일을 작업 폴더로 복사해 쓴다.
- **사용량 감시(claude 러너만, 054 run 1):** 러너에는 계정 사용량 감시가 없다. 054 작업 폴더의 `claude_usage_watch.py`(121줄)를 복사해 unit으로 띄운다. stage log(`<run>/*.jsonl`)의 `rate_limit_event`(`unifiedWindows`의 `five_hour`·`seven_day` utilization·resetsAt·status)를 60 s마다 읽어 50·75·90·95·99%와 `allowed`가 아닌 status를 `events.log`에 적는다. 읽기만 하고 run을 멈추지 않는다. 한도 대기는 러너가 한다(`usage_limit_wait_*`). run 감시의 `--codex-bin $CLAUDE_BIN`은 Claude Code 버전이 바뀌면 줄을 내지만 문구가 "codex version"이다.
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
- deepagents: 모델 호출마다 token 사용량이 `<run>/usage.jsonl`에 role(`stage`, `subagent:<name>`, `review`)과 함께 쌓인다. 0.51.0부터 `status`가 `completed`가 아닌 줄에는 `detail`(response id, `incomplete_details` 전체, service tier, content block 종류, tool call 수)이 붙는다. Deep Agents 자체 파일은 `<run>/agent/`다.
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
- **deepagents 러너:** 에이전트는 러너 프로세스 안에서 돈다. 에이전트만 얼리는 절차는 operator.md에 없다(정해지지 않음). codex의 `kill -STOP`을 러너 프로세스에 옮겨 쓰지 않는다. 위 1~5 그대로 멈춘다. 운영자 정지는 돌고 있는 subagent도 다음 모델 호출 전에 끝낸다. 그러나 이미 시작한 리뷰는 판정까지 돈다(리뷰어에 정지 확인이 없음, 051 문제 8, 고치기 전까지). 051 run 3(11-19 23:09)에서 이 절차로 멈췄을 때 unit stop 뒤 리뷰가 8분, 54호출 3.96 USD를 더 쓰고 끝났다. 장치 위험은 없으니 기다린다.

하지 않는 것:

- 넓은 `pkill -f`를 쓰지 않는다.
- 장치를 연 프로세스를 강제로 죽이지 않는다. FLR, PCI remove/rescan, `tt-smi` reset을 하지 않는다. FW init이 실패하면 장치 작업을 멈추고 재부팅한다(사용자 확인). myA0는 [power.md](power.md) 절차(보드 전원 껐다 켜기 뒤 재부팅)로 한다.

wrapper가 `stop-device-work`(exit 126, 기한 종료 포함)로 끝났거나 wrapper 기록에 exit가 없으면(러너가 먼저 죽음):

- 장치를 다시 열지 않는다(`verify_device.py` 포함). hang 장치를 다시 열면 PCIe 이탈이 난다(026차 조사).
- 명령 log 끝에 mesh close가 있고 holder가 없을 때만, 사용자 승인 뒤 wrapper로 verifier를 1회 돌린다. 그 밖에는 재부팅한다(myA0는 [power.md](power.md)).
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

**deepagents 러너:** 인증은 모델 API key 하나다(`OPENAI_API_KEY`, Claude 모델이면 `ANTHROPIC_API_KEY`). 로그인 상태나 Codex home이 없다. key가 없으면 실제 launch가 시작 전에 거부된다. run 중 API 오류는 러너가 backoff로 재시도하고, 이어지면 `turn-failed`(exit 5)로 끝나며 오류 문장이 manifest `stage_N_turn_error`와 unit log에 남는다. 그것을 읽고 key·계정 문제면 셸의 key를 바로잡은 뒤 `resume.sh`로 같은 thread를 잇는다. key가 틀렸거나 계정 한도·잔액이 모자랄 때 어떤 오류로 나타나는지, 한도에 걸렸을 때 기다릴지 멈출지는 아직 정해지지 않았다(run 기록 없음, 러너에 한도 대기가 없음).

## 연속 run 후보와 serving stack

- **후보:** 러너가 entry stage(Stage 6, `--serving-after optimized-full-model`이면 Stage 5) 뒤 operator.md "Continuous run" 규칙으로 고르고 사용자 승인을 묻지 않는다. 고정하려면 `AVIRON_BRINGUP_SERVING_CANDIDATE`를 준다.
- **stack manifest는 run마다 새로 만든다.** 띄우기 직전의 checkout으로 만들고, 옛 manifest는 다시 쓰지 않는다. `--create` 전에 plugin checkout이 깨끗한지 확인한다. 남은 변경은 그대로 baseline이 된다(045차 044-15).
  ```bash
  $PY $SK/scripts/serving_stack.py --create $CHECKOUT/bringup/serving/stack-<date>-<tag>.json \
    --plugin $REPO/vllm-aviron-plugin --installed
  ```
  0.54.0부터 vLLM은 `python_env`에 패키지로 설치돼(`--vllm` 없음) manifest가 버전·출처 commit·파일 hash로 기록한다. 0.53.x는 `--vllm <checkout>`이 필요했고, myA0 `$REPO/vllm` checkout은 11-23에 지웠다.
- **run 뒤 plugin checkout:** `serving-complete` 뒤 plugin checkout이 baseline과 다르면, autoport를 지우기 전에 `third_party_patches/plugin.diff`와 대조하고 사용자에게 알린다.
- **vLLM core:** 설치된 그대로여야 한다(파일 hash). core를 고쳐야 하면 고친 것을 설치하고 새 manifest를 만든다.

## 산출물 백업

기존 산출물은 `$BACKUP`에 압축해 둔다. `bringup/references/`는 다음 run이 읽으므로 남긴다.

**autoport(`models/autoports/<model_dir>`):** run이 끝나면(`serving-complete`나 사용자가 정한 종료) 아래 순서로 한다. 원본 폴더 삭제까지 이 절차에 포함된다(11-20 사용자 지시). 장치 명령이 돌거나 다른 run이 그 autoport를 쓰는 동안에는 하지 않는다.

1. 측정 원자료는 백업하지 않고 버린다: Tracy 원자료(`*.tracy`), profile CSV(`profile_log_device.csv`, `tracy_ops_times.csv`)와 그 gzip 사본(`*.tracy.gz`, `*_ops_times.csv.gz`, `profile_log_device.csv.gz`; 054 run 1 Stage 1이 남김, skills 0.54.1부터는 남기지 않음), 텐서(`*.pt`, `*.tensorbin`: HF reference layer 출력·logits 등 다시 만들 수 있는 것), `__pycache__`.
2. 나머지(code, `doc/`, json·log·md)를 불투명 이름 `a0bk_<YYYYMMDDTHHMM>_<순번>.tgz`로 `$BACKUP`에 압축하고, `tar -d`로 원본과 대조한다.
3. 대조가 `identical`이고 holder·refcnt가 0이면 원본 폴더를 지운다. `models/autoports/`는 빈 폴더로 둔다.
4. sungmin 차수 문서의 백업 이름 대조표(예: `aviron-skills/rounds/051/조사/백업이름변경_myA0_20261120.md`)에 이름·내용·크기를 한 줄 더하고, run 기록에 백업 경로·크기·삭제 시각을 적는다.

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

- **이름:** 백업 이름에 모델·run·autoport 이름을 넣지 않는다. stage 에이전트가 같은 사용자로 돌아 `find … -iname "*<model>*"`로 이전 run 백업을 찾아 풀어 쓴 일이 있다(051 문제 9). 이름 대조는 sungmin 문서에만 두고 서버에는 두지 않는다.
- 측정 원자료까지 필요하다고 사용자가 정하면, 버릴 파일만 따로 같은 방식(불투명 이름, `tar -d`)으로 압축한다(051 run 4 `.pt` 41개 `a0bk_20261120T1526_38.tgz`).
- `bringup/artifacts/multigoal-runs/<run>/`(run 폴더)는 사용자가 정한 경우에만, 같은 방식으로 압축·대조한 뒤 지운다.
- 다른 서버의 산출물은 그 서버에서 압축·대조한 뒤 백업 위치로 옮긴다.

## 사람 포팅 비교 측정(지시가 있을 때)

사람 포팅은 tt-metal-e2 `models/tt_transformers`(`DecodersPrecision.performance`)다. autoport와 같은 장치·같은 plugin 도구로 TTFT/TPS(batch 1, 6길이 × 3회, 출력 100 token)와 MMLU(1,368)를 재서 autoport Stage 6(`doc/benchmark/<후보>.json` `rows[].runs[2]`)과 비교한다.

- **시작점:** 최신 작업 폴더 백업을 풀고 `setup.sh`처럼 sed로 경로·모델·revision·run-id·`AP_CAND`를 바꾼다.
  - Llama 3.1 8B W8A8(051, Python 3.12, e2 `3daa9ee902`): myA0 `/home/bos/_backup/a0bk_20261120T1449_37.tgz`
  - Qwen3 4B W8A8(050): `a0bk_20261119T0850_22.tgz`
  - Llama 3B·8B(046~048, Python 3.10): `a0bk_20261115T1936_14.tgz`
  - 백업 이름은 불투명하다. 내용은 sungmin `aviron-skills/rounds/051/조사/백업이름변경_myA0_20261120.md`에서 찾는다. 다 쓴 작업 폴더도 TT weight cache(`tt_cache/`)를 빼고 같은 방식으로 압축·대조한 뒤 지운다.
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
