---
name: aviron-transformers
description: aviron-transformers(bos-semi/aviron-transformers, tenstorrent/tt-transformers의 BOS 사본) 작업 — tt-metal-e2 도입, A0 모델 뼈대 세우기, 관련 커널·binding 변경 — 을 시작할 때 읽는 지침. 시작 순서, 코드 정본 위치, 작업 범위, 장치 점유·commit 규칙.
---

# aviron-transformers 작업

[bos-semi/aviron-transformers](https://github.com/bos-semi/aviron-transformers)(tenstorrent/tt-transformers의 BOS 사본)를 BOS N1 A0(tt-metal-e2) 위에서 돌게 하고 모델 뼈대를 세우는 작업이다.

계획·조사·기록은 문서 저장소 sungmin(myA0 `/home/bos/repo/sungmin`)의 `aviron-transformers/`에 있다. 그 폴더의 `AGENTS.md`가 문서 지도, 단계 폴더 규칙, 기록 규칙을 정한다. 아래 `aviron-transformers/…` 경로는 sungmin 저장소 기준이다.

## 시작할 때

`aviron-transformers/README.md` → `aviron-transformers/TODO.md` → 지금 단계 `phases/0N_<이름>/README.md` 순서로 읽는다.

## 정본 위치

- 코드: aviron-transformers 저장소 `develop`(AI005 `~/repo/bos-transformers`, myA0 skills 실행 clone submodule `/home/bos/repo/aviron-skills/plugins/bos-model-bringup/references/aviron-transformers`, AI006 `/mnt/new_ssd/sungmin_sdpa56225_20261017/tt-transformers`). 커널·binding 변경은 tt-metal-e2 작업 branch에서 한다(지금은 Qwen3.5 GDN op를 cherry-pick한 작업 branch, `9aa7cd8a24`).
- 코드·도구·인계 note(`examples/<model>/BRINGUP_HANDOVER.md` 등)는 aviron-transformers 저장소에 두고, 문서 저장소에는 문서만 둔다.

## 작업 범위

저장소 목적(뼈대 우선, 최적화 비목적)과 "뼈대가 정확하다"의 기준은 `aviron-transformers/README.md`에 있다. 이 기준이 작업 범위를 정한다.

## 장치와 commit

- 장치는 쓰기 직전마다 점유를 확인한다(AI005 `~/qwen35_logs/busy.sh`·`devrun.sh`). 공용 서버의 남의 작업·파일·container는 건드리지 않고, 지울 때는 사용자 승인을 받는다.
- aviron-transformers `develop`과 e2 작업 branch는 검증된 단위마다 commit·push한다. author는 `sungmin <lsm0729@bos-semi.com>`이고 AI 표기는 넣지 않는다. history를 다시 쓰는 force-push는 사용자 확인 뒤에 한다.
