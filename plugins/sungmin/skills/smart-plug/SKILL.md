---
name: smart-plug
description: host shell의 스마트 플러그 명령(plugon·plugoff·plugstatus)으로 플러그 전원을 켜고 끄고 상태를 확인할 때 읽는다. 보드 장비 전원을 껐다 켜기(power cycle), 보드가 응답하지 않아 전원 재인가가 필요할 때, 플러그 상태 확인 요청에 적용한다.
---

# 스마트 플러그(plugon·plugoff·plugstatus)

host의 `~/.bashrc`에 등록한 shell 함수로 Home Assistant 스위치 하나를 켜고 끈다. 보드 장비 전원을 이 플러그에 연결해 원격으로 껐다 켤 예정이다(2026-11-20 기준 아직 보드는 연결 전).

```text
+------+  bash -ic plug*  +------------------+  ssh -L 18123:8123  +----------------+     +------------+
| host |----------------->| _plug (bashrc)   |-------------------->| Home Assistant |---->| smart plug |
+------+                  | curl REST API    |                     | switch entity  |     | (board PSU)|
                          +------------------+                     +----------------+     +------------+
```

## 명령

| 명령 | 동작 | 출력·종료 코드 |
|---|---|---|
| `plugstatus` | 스위치 상태 조회 | `on` 또는 `off` 한 줄, 성공 시 rc 0 |
| `plugon` | 전원 켜기 | 출력 없음, 성공 시 rc 0 |
| `plugoff` | 전원 끄기 | 출력 없음, 성공 시 rc 0 |

- 세 함수 모두 `_plug on|off|status`를 부른다. HA 주소·entity·터널 대상은 `type _plug`(대화형 shell에서)로 확인한다. skill에 옮겨 적지 않는다.
- 인증 token은 `~/.config/home-assistant/token`에서 읽는다. token 내용은 출력하거나 기록하지 않는다.
- HA API(`127.0.0.1:18123`)가 응답하지 않으면 `_plug`가 ssh local forward를 background로 자동으로 연다. 실패하면 rc 1이다.
- 실패(curl·ssh 오류)는 rc가 0이 아니다. rc를 확인하고, 상태 변경 뒤에는 `plugstatus`로 실제 상태를 다시 본다.

## 실행 방법

함수는 `~/.bashrc`에 있고 `~/.bashrc`는 비대화형 shell에서 바로 return하므로, agent의 Bash 도구에서는 대화형 shell로 부른다.

```bash
bash -ic 'plugstatus' 2>/dev/null   # job control 경고(stderr)를 버린다
bash -ic 'plugoff; echo rc=$?' 2>/dev/null
```

- host에서만 실행한다. 원격 서버에는 이 함수가 없다.
- `bash -c 'plugstatus'`(비대화형)는 "명령어를 찾을 수 없음"으로 실패한다.

## 전원 껐다 켜기

`plugoff`·`plugon`은 보드 전원을 실제로 끊는다. 사용자가 이번 작업에서 전원 조작을 지시했을 때만 실행하고, 실행 전에 보드를 쓰는 작업이 없는지 확인한다.

- 실행 전: 진행 중인 run·시험·장치 점유 process가 있으면 끄지 않고 사용자에게 알린다(전원 차단은 run을 깨고 결과를 잃게 한다).
- 순서: `plugstatus` → `plugoff` → `plugstatus`가 `off`인지 확인 → 잠시 대기 → `plugon` → `plugstatus`가 `on`인지 확인 → 보드 부팅·장치 인식을 원격 서버에서 확인.
- 끈 뒤 대기 시간, 켠 뒤 부팅·장치 인식까지 걸리는 시간과 확인 명령은 보드 연결 후 정한다(미확인). 정해지면 이 절에 적는다.
- 전원 조작 결과(시각, 명령, rc, 전후 상태)는 작업 보고에 함께 적는다.
