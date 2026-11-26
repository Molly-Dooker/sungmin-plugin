# 보드 전원: 스마트 플러그와 myA0 hang 복구

myA0 A0 보드의 전원은 Home Assistant 스마트 플러그에 연결돼 있다. host의 `~/.bashrc`에 등록한 shell 함수로 이 플러그를 켜고 끈다. run은 myA0의 실행 clone에서 돌고, host가 ssh로 감시하다가 장치가 hang되면 host에서 보드 전원을 껐다 켜고 myA0를 재부팅한 뒤 같은 run을 재개한다. **이 플러그와 아래 복구 절차는 myA0 전용이다.** 다른 서버(AI001 등)에는 플러그가 없으므로 재부팅이 필요하면 사용자에게 알린다.

```text
+------+  bash -ic plug*  +------------------+  ssh -L 18123:8123  +----------------+     +------------+
| host |----------------->| _plug (bashrc)   |-------------------->| Home Assistant |---->| smart plug |
+------+                  | curl REST API    |                     | switch entity  |     | myA0 board |
   |                      +------------------+                     +----------------+     +------------+
   |  ssh myA0 sudo -n /usr/sbin/reboot                                                         | PCIe 01:00.0
   +----------------------------------------------------------------------------------> +------------+
   |  ssh myA0: watch the run, resume it after the reboot                               | myA0 host  |
   +----------------------------------------------------------------------------------> +------------+
```

## 플러그 명령

| 명령 | 동작 | 출력·종료 코드 |
|---|---|---|
| `plugstatus` | 스위치 상태 조회 | `on` 또는 `off` 한 줄, 성공 시 rc 0 |
| `plugon` | 보드 전원 켜기 | 출력 없음, 성공 시 rc 0 |
| `plugoff` | 보드 전원 끄기 | 출력 없음, 성공 시 rc 0 |

- 세 함수 모두 `_plug on|off|status`를 부른다. HA 주소·entity·터널 대상은 `type _plug`(대화형 shell에서)로 확인한다. 이 문서에 옮겨 적지 않는다.
- 인증 token은 `~/.config/home-assistant/token`에서 읽는다. token 내용은 출력하거나 기록하지 않는다.
- HA API(`127.0.0.1:18123`)가 응답하지 않으면 `_plug`가 ssh local forward를 background로 자동으로 연다. 실패하면 rc 1이다.
- 실패(curl·ssh 오류)는 rc가 0이 아니다. rc를 확인하고, 상태 변경 뒤에는 `plugstatus`로 실제 상태를 다시 본다.
- host에서만 실행한다. 원격 서버에는 이 함수가 없다. `~/.bashrc`는 비대화형 shell에서 바로 return하므로 대화형 shell로 부른다(`bash -c 'plugstatus'`는 "명령어를 찾을 수 없음"으로 실패한다).

```bash
bash -ic 'plugstatus; echo rc=$?' 2>/dev/null   # job control 경고(stderr)를 버린다
```

`plugstatus`는 언제든 해도 된다. `plugoff`·`plugon`은 보드 전원을 실제로 끊으므로 아래 복구 절차나 사용자가 이번 작업에서 전원 조작을 지시했을 때만 실행한다.

## myA0 hang 복구: 전원 껐다 켜기와 재부팅

**사용자에게 묻지 않고 바로 실행한다. 횟수 제한은 없다(11-26 사용자 지시).** hang이 날 때마다 아래 절차를 처음부터 하고, 복구 뒤 같은 run을 재개한다. 사용자에게는 끝난 뒤 보고한다.

### 언제

myA0 장치를 더 쓸 수 없을 때만 한다. host가 감시하다가 아래 가운데 하나를 보면 hang이다.

- 러너가 장치 작업을 멈췄고 자동 검증이 풀지 못함: launch가 끝났고(unit 없음) manifest 마지막 launch가 `run_status=stop-device-work`, `stop_reason=device-verifier-failed`.
- wrapper가 `stop-device-work`(exit 126)로 끝났거나 exit 기록이 없는데 명령 log에 mesh close가 없음, verifier 실패, FW init 실패.
- `/dev/bos/0`이나 PCI `01:00.0`이 사라짐(PCIe 이탈).
- 장치를 연 process가 끝나지 않아 장치를 놓지 않음.

하지 않는 경우:

- 러너 자동 검증이 통과해 같은 launch에서 이어 감(`device_verify_<n>=passed`). hang이 아니다.
- 장치 정지가 아닌 정지(`turn-failed`, `review-critical-fail` 등)이고 장치가 정상임. [watcher.md](watcher.md) "복구"를 따른다.
- 이 run 말고 다른 bring-up 러너(`graph_controller.py`)가 myA0에서 돌고 있음. 전원을 끊지 않고 사용자에게 알린다.

FLR, PCI remove/rescan, `tt-smi` reset은 이 절차로도 하지 않는다. hang 장치를 다시 열지 않는다(verifier 포함).

### 전 확인(myA0)

run이 있으면 새 장치 명령부터 막는다: `touch <run>/wrappers/STOP`. hang 명령의 drain은 끝나지 않으므로 기다리지 않는다. unit도 따로 멈추지 않는다(재부팅이 멈춘다). 그다음 지금 상태를 남긴다.

```bash
ssh myA0 'date "+%F %T"; uptime -s; fuser -v /dev/bos/0; ps -eo pid,etime,cmd | grep -E "[r]un_device_command|[g]raph_controller"; lspci -nn -s 01:00.0; ls -l /dev/bos/0; tail -5 <run>/manifest.txt'
```

`uptime -s`는 재부팅 확인에, manifest 끝(`run_status`·`stop_stage`·`stop_reason`)은 재개 방식 선택에 쓴다.

### 순서(host)

보드 off → 5초 → on → 5초 → myA0 재부팅이다. 보드를 켠 직후 바로 재부팅하면 부팅 뒤 보드가 bus에 없었다(11-25 실증). 그래서 켠 뒤 5초를 둔다.

```bash
date '+%F %T'
bash -ic 'w(){ for i in 1 2 3 4 5; do [ "$(plugstatus)" = $1 ] && return; sleep 2; done; return 1; }; plugstatus; plugoff || exit 1; w off || exit 2; sleep 5; plugon || exit 3; w on || exit 4; sleep 5' 2>/dev/null; echo rc=$?
```

`w`는 상태를 2초 간격으로 최대 5번 본다. 플러그 상태가 명령 뒤 몇 초 늦게 바뀔 수 있다(11-24 17:08: `plugoff` 직후 `on`, 몇 초 뒤 `off`).

| rc | 뜻 | 할 일 |
|---|---|---|
| 0 | off → 5초 → on 확인 → 5초 | 재부팅으로 간다 |
| 1·2 | 끄기 실패, 또는 off가 확인되지 않음(보드는 켜져 있음) | 위 명령을 한 번 더 한다. 또 1·2면 재부팅하지 않고 사용자에게 알린다(플러그·HA 문제) |
| 3·4 | 꺼진 뒤 켜기 실패 | `plugon`을 다시 하고 `plugstatus`가 `on`이면 5초 뒤 재부팅한다. 켜지지 않으면 사용자에게 알린다(보드가 꺼진 채로 남음) |

```bash
ssh myA0 sudo -n /usr/sbin/reboot; echo rc=$?
```

- 연결이 끊기면서 rc 255가 나와도 정상이다. 재부팅됐는지는 아래 `uptime -s`로 본다.
- `sudo: a password is required`(rc 1)이면 아래 "sudo 설정"이 안 된 것이다. 비밀번호를 묻거나 다른 방법으로 넣지 않는다. 사용자에게 알린다(보드는 켜져 있으나 PCIe 재인식 전이므로 장치를 열지 않는다).

### 뒤 확인

ssh가 다시 될 때까지 기다린다. 반복 `sleep` 대신 Monitor의 until-loop를 쓴다(`until ssh -o ConnectTimeout=5 myA0 true; do sleep 10; done`). 15분 안에 안 붙으면 사용자에게 알린다.

```bash
ssh myA0 'uptime -s; lspci -nn -s 01:00.0; ls -l /dev/bos/0; lsmod | grep -w bos'
```

| 항목 | 기대(11-20 확인 값) |
|---|---|
| `uptime -s` | 재부팅 명령 시각보다 뒤 |
| `lspci -nn -s 01:00.0` | `Co-processor [0b40]: Synopsys, Inc. DWC_usb3 / PCIe bridge [16c3:abcd]` |
| `/dev/bos/0` | `crw-rw-rw- root root 238, 0` |
| `lsmod` | `bos` module이 올라와 있음 |

하나라도 다르면 장치를 열지 않고, "순서"부터 다시 한다(묻지 않는다). 다시 할 때마다 기록에 남긴다.

### 재개

재부팅으로 러너 unit과 감시 unit이 모두 없어졌다. [run.md](run.md) "시작 script"의 `launch-unit.sh`로 같은 run을 다시 띄우고 "감시 unit"도 다시 띄운다.

| 마지막 launch의 기록 | 재개 |
|---|---|
| `run_status=stop-device-work`(인터럽트 `await_ack`에서 기다림) | `resume-with.sh <run> '{"decision":"verified-resume","note":"watcher, <시각>: 보드 전원 껐다 켜기·재부팅 <n>번째(<이유>)"}'` |
| 그 밖(`stop_stage`가 있음, 또는 unit이 기록 없이 죽음) | `resume.sh <run> <stop_stage> -` |

재개 뒤 manifest에 새 `graph_launch=` 줄이 생겼는지 본다. 생기지 않고 unit이 끝났으면 옛 정지 기록이 그대로라 다시 hang으로 읽힌다. 그때는 전원을 끊지 말고 unit log를 읽어 재개가 거부된 이유를 고친다.

같은 명령에서 hang이 되풀이돼도 복구와 재개를 계속한다. 몇 번째인지와 hang한 명령을 보고에 적는다.

### 기록

시각, 명령별 rc, 플러그 전후 상태, `uptime -s` 전후, 뒤 확인 결과, 몇 번째 복구인지를 차수 `2_run/<n>_<model>.md`와 autoport `doc/INTERVENTIONS.md`에 적고 사용자에게 보고한다.

## sudo 설정(myA0, 사용자가 한 번)

재부팅 명령은 비밀번호 없이 `reboot` 하나만 허용하는 sudoers 규칙으로 돌린다. 에이전트는 sudo 비밀번호를 받거나 저장하지 않는다(파일·환경변수·명령줄·log 모두). myA0에는 `/etc/sudoers.d/a0-reboot`로 설정돼 있다(11-24 확인: `sudo -n -l /usr/sbin/reboot` → `/usr/sbin/reboot`, rc 0).

다시 설정해야 하면 사용자가 host에서 한 번 실행한다(비밀번호는 사용자가 직접 입력한다).

```bash
ssh -t myA0 'echo "bos ALL=(root) NOPASSWD: /usr/sbin/reboot" | sudo tee /etc/sudoers.d/a0-reboot >/dev/null && sudo chmod 440 /etc/sudoers.d/a0-reboot && sudo visudo -cf /etc/sudoers.d/a0-reboot'
```

확인(재부팅하지 않음): `ssh myA0 sudo -n -l /usr/sbin/reboot`가 `/usr/sbin/reboot`를 출력하면 된다.
