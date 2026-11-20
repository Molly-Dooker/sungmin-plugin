# 보드 전원: 스마트 플러그와 myA0 hang 복구

myA0 A0 보드의 전원은 Home Assistant 스마트 플러그에 연결돼 있다(2026-11-20부터). host의 `~/.bashrc`에 등록한 shell 함수로 이 플러그를 켜고 끈다. 장치가 hang돼 더 쓸 수 없으면 이 플러그로 보드 전원을 껐다 켜고 myA0를 재부팅한다. **이 플러그와 아래 복구 절차는 myA0 전용이다.** 다른 서버(AI001 등)에는 플러그가 없으므로 재부팅이 필요하면 사용자에게 알린다.

```text
+------+  bash -ic plug*  +------------------+  ssh -L 18123:8123  +----------------+     +------------+
| host |----------------->| _plug (bashrc)   |-------------------->| Home Assistant |---->| smart plug |
+------+                  | curl REST API    |                     | switch entity  |     | myA0 board |
   |                      +------------------+                     +----------------+     +------------+
   |  ssh myA0 sudo -n /usr/sbin/reboot                                                         | PCIe 01:00.0
   +----------------------------------------------------------------------------------> +------------+
                                                                                        | myA0 host  |
                                                                                        +------------+
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

### 언제

myA0 장치를 더 쓸 수 없을 때만 한다.

- [run.md](run.md) "멈추기"가 재부팅으로 보내는 경우: wrapper가 `stop-device-work`(exit 126)로 끝났거나 exit 기록이 없는데 명령 log에 mesh close가 없음, verifier 실패, FW init 실패.
- `/dev/bos/0`이나 PCI `01:00.0`이 사라짐(PCIe 이탈).
- 장치를 연 process가 끝나지 않아 장치를 놓지 않음.

**실행 전에 사용자 확인을 받는다.** 전원 차단은 돌고 있는 장치 명령과 결과를 잃게 한다. 장치를 쓰는 다른 사람·작업이 없는지도 함께 확인한다. FLR, PCI remove/rescan, `tt-smi` reset은 이 절차로도 하지 않는다.

### 전 확인(myA0)

run이 있으면 새 장치 명령부터 막는다: `touch <run>/wrappers/STOP`. hang 명령의 drain은 끝나지 않으므로 기다리지 않는다. unit도 따로 멈추지 않는다(재부팅이 멈춘다). 그다음 지금 상태를 남긴다.

```bash
ssh myA0 'date "+%F %T"; uptime -s; fuser -v /dev/bos/0; ps -eo pid,etime,cmd | grep "[r]un_device_command"; lspci -nn -s 01:00.0; ls -l /dev/bos/0'
```

`uptime -s`는 재부팅 확인에 쓴다.

### 순서(host)

```bash
date '+%F %T'
bash -ic 'plugstatus; plugoff || exit 1; [ "$(plugstatus)" = off ] || exit 2; sleep 5; plugon || exit 3; [ "$(plugstatus)" = on ] || exit 4' 2>/dev/null; echo rc=$?
```

| rc | 뜻 | 할 일 |
|---|---|---|
| 0 | off → 5초 → on 확인 | 재부팅으로 간다 |
| 1·2 | 끄기 실패, 또는 off가 확인되지 않음 | `plugstatus`를 한 번 더 본다. 상태가 바뀌지 않았으면 재부팅하지 말고 사용자에게 알린다 |
| 3·4 | 꺼진 뒤 켜기 실패 | `plugon`을 다시 하고 `plugstatus`가 `on`일 때만 재부팅한다. 켜지지 않으면 사용자에게 알린다(보드가 꺼진 채로 남음) |

```bash
ssh myA0 sudo -n /usr/sbin/reboot; echo rc=$?
```

- 연결이 끊기면서 rc 255가 나와도 정상이다. 재부팅됐는지는 아래 `uptime -s`로 본다.
- `sudo: a password is required`(rc 1)이면 아래 "sudo 설정"이 안 된 것이다. 비밀번호를 묻거나 다른 방법으로 넣지 않는다. 사용자에게 알린다(보드는 켜져 있으나 PCIe 재인식 전이므로 장치를 열지 않는다).

### 뒤 확인

ssh가 다시 될 때까지 기다린다. 반복 `sleep` 대신 Monitor의 until-loop를 쓴다(`until ssh -o ConnectTimeout=5 myA0 true; do sleep 10; done`). 부팅 시간은 아직 재지 않았다(미확인). 15분 안에 안 붙으면 사용자에게 알린다.

```bash
ssh myA0 'uptime -s; lspci -nn -s 01:00.0; ls -l /dev/bos/0; lsmod | grep -w bos'
```

| 항목 | 기대(11-20 확인 값) |
|---|---|
| `uptime -s` | 재부팅 명령 시각보다 뒤 |
| `lspci -nn -s 01:00.0` | `Co-processor [0b40]: Synopsys, Inc. DWC_usb3 / PCIe bridge [16c3:abcd]` |
| `/dev/bos/0` | `crw-rw-rw- root root 238, 0` |
| `lsmod` | `bos` module이 올라와 있음 |

하나라도 다르면 장치를 열지 않고 사용자에게 알린다. 전원 껐다 켜기는 사용자 확인 없이 다시 하지 않는다.

모두 맞으면 run은 [run.md](run.md) "멈추기"의 재부팅 뒤 경로로 같은 run을 재개한다: `resume-with.sh <run> '{"decision":"verified-resume","note":"<누구, 언제, 전원 껐다 켜기·재부팅>"}'`. user systemd unit과 감시 unit은 재부팅으로 없어졌으므로 [run.md](run.md) "시작"·"감시 unit"대로 다시 띄운다.

### 기록

시각, 명령별 rc, 플러그 전후 상태, `uptime -s` 전후, 뒤 확인 결과를 작업 보고에 적는다. run 중이었으면 autoport `doc/INTERVENTIONS.md`와 차수 `2_run/<n>_<model>.md`에도 적는다.

## sudo 설정(myA0, 사용자가 한 번)

재부팅 명령은 비밀번호 없이 `reboot` 하나만 허용하는 sudoers 규칙으로 돌린다. 에이전트는 sudo 비밀번호를 받거나 저장하지 않는다(파일·환경변수·명령줄·log 모두). 11-20 확인 때는 설정되지 않았다(`sudo -n true` → `a password is required`).

사용자가 host에서 한 번 실행한다(비밀번호는 사용자가 직접 입력한다).

```bash
ssh -t myA0 'echo "bos ALL=(root) NOPASSWD: /usr/sbin/reboot" | sudo tee /etc/sudoers.d/a0-reboot >/dev/null && sudo chmod 440 /etc/sudoers.d/a0-reboot && sudo visudo -cf /etc/sudoers.d/a0-reboot'
```

확인(재부팅하지 않음): `ssh myA0 sudo -n -l /usr/sbin/reboot`가 `/usr/sbin/reboot`를 출력하면 된다. 설정이 끝나면 이 절의 "11-20 확인 때는" 문장을 고친다.
