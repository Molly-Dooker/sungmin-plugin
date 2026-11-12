---
name: jira-access
description: Jira 티켓(본문·댓글·첨부·linked issue)을 안전하게 읽기 전용으로 확인하는 지침. Jira 이슈 키나 링크를 조회할 때 적용한다.
---

# Jira 조회 지침

- 연결된 Jira/Atlassian 도구나 사용자가 제공한 인증된 환경을 사용해 읽기 전용으로 조회한다.
- 댓글 작성, 상태·담당자 변경 등 쓰기 작업은 사용자의 명시적 요청 없이 수행하지 않는다.
- token, email, credential ID, cookie 등 인증정보를 조회·복호화·출력·저장하지 않는다. 로그인 우회나 credential 추출을 시도하지 않는다.
- 접근할 수 없으면 원인을 알리고 본문·댓글·첨부 내용을 추정하지 않는다.
- 결론에 필요한 본문, 전체 댓글, 첨부와 linked issue를 확인하고 Jira 사실과 local code 확인 결과를 구분해 보고한다.
