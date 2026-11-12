---
name: a0-bringup
description: BOS N1 A0 모델 브링업(aviron-skills, Jira AISW-1580) 작업을 시작할 때 읽는 입구 지침. 현재 기준 요약 순서, 정본 위치(skills 실행 clone·tt-metal-e2·문서 저장소), 역할별 skill(a0-clone-run, bringup-watcher, skills-change-gate) 안내. A0 run, skills 수정, 차수 문서 작업 전에 적용한다.
---

# A0 모델 브링업

BOS N1 A0 단일 장치에서 HF 모델을 에이전트(Codex 러너, 2.0.0부터 LangGraph)로 bring-up하는 작업(Jira AISW-1580)의 입구다.

운영 문서와 기록은 문서 저장소 sungmin(myA0 `/home/bos/repo/sungmin`)의 `aviron-skills/`에 있다. 그 폴더의 `AGENTS.md`가 문서 지도, 차수 폴더 규칙, 기록 규칙, 옛 이름·branch → tag 대조를 정한다. 아래 `aviron-skills/…` 경로는 sungmin 저장소 기준이다.

## 시작할 때

`aviron-skills/AGENTS.md`, `aviron-skills/TODO.md`, 지금 차수 `aviron-skills/rounds/0NN/README.md`를 읽는다. 현재 기준(skills develop commit, tt-metal commit, 서버·run 상태)과 남은 할 일을 먼저 요약한다.

## 역할별 skill

- 모델 브링업 run은 **별도 지시가 없으면 [a0-clone-run](../a0-clone-run/SKILL.md) 방식으로 돌린다.** skills 실행 clone에서 러너(`run_bringup`)를 직접 띄우고, Stage 0 → 7 연속 run(`--serving-after 5`)으로 간다(0.40.0부터 stage 0~7; 3.0.0의 01 → 10, `--serving-after 8`은 옛 번호다). 시작 전 확인, dry-run, 시작, 재개, 후보 규칙, serving stack을 다룬다.
- run을 운영·감시할 때(watcher 역할)는 [bringup-watcher](../bringup-watcher/SKILL.md)를 따른다. 장치 정지가 아니면 멈추지 않고 고쳐서 끝까지 이어 가는 판단 규칙이다.
- 상태 보기, 멈추기(장치 안전), 인증, HF 참조, 백업 명령은 `aviron-skills/startingpoint.md`에 있다.
- skills 플러그인을 바꾸는 검토사항·개선안·구현은 [skills-change-gate](../skills-change-gate/SKILL.md)로 항목마다 근거·결함 종류·수정 성격·run 부담·구조 수정과의 관계를 먼저 거른다(042차 범위 점검에서 생긴 기준).

## 정본 위치

- **11-04부터(사용자 지시) 작업은 별도 지시가 없으면 myA0 `/home/bos/repo/` 안의 저장소에서 직접 한다.** 문서 저장소는 `/home/bos/repo/sungmin`, skills는 `/home/bos/repo/aviron-skills`, tt-metal-e2는 `/home/bos/repo/tt-metal-e2`이고, commit·push도 거기서 한다.
- 지침과 코드: skills 플러그인 `bos-model-bringup`(`bos-semi/aviron-skills`, marketplace `aviron-skills`, plugin ID `bos-model-bringup@aviron-skills`)이다. version `0.NN.x` = 차수 `0NN`(`aviron-skills/AGENTS.md` "차수 폴더 규칙")이고, 그 전 플러그인 `tt-model-bringup-a0`(1.0.x·2.0.0·3.0.0)과 branch 이력은 `aviron-skills/history.md`와 `aviron-skills/rounds/_legacy/`에 있다. 11-10부터(사용자) skills 수정·시험·commit은 별도 clone이 아니라 실행 clone myA0 `/home/bos/repo/aviron-skills`에서 직접 하고, run이 도는 동안에는 고치지 않는다. run 지침 변경은 `bos-model-bringup` 플러그인에서만 한다. tt-metal-e2 B2B 브랜치는 갱신하지 않는다.
- skills 저장소에는 branch `develop` 하나만 있고 버전은 tag `vX.Y.Z`로 구분한다. 지금 `develop`·tag와 차수는 `aviron-skills/TODO.md`에, 옛 branch → tag 대조는 `aviron-skills/AGENTS.md` "정본 위치"에 있다.
- checkout: myA0 `/home/bos/repo/tt-metal-e2`. run 산출물은 `bringup/`, autoport는 `models/autoports/`이고 둘 다 git 추적 밖이다. autoport 안 운영자 개입 기록은 autoport `doc/INTERVENTIONS.md`가 원본이다.

## 운영 규칙

- 장치 명령이 도는 중에는 러너를 멈추지 않는다. 기존 산출물은 지우지 않고 `/home/bos/_backup/`에 압축해 둔다. 장치 안전 절차는 `aviron-skills/startingpoint.md` "멈추기"에 있다.
