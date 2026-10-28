# DSH Notify Bridge

DeepSeek Harness 이벤트(턴 완료·승인 대기·질문 대기·오류)를 DSH Notify의 윈도 토스트로 바꾸는 **host 플러그인**이다. 포트·웹서버·데몬 없이 이벤트마다 `notify\send-toast.ps1` 을 짧게 실행한다.

## 등록

- 프로필(`~/.dsh/profiles/desktop`)의 `node_modules/@local/dsh-notify-bridge` 로 링크
- 프로필 `cordis.patch.yml` 의 `insert` 에 아래 엔트리 추가

```yaml
- insert:
    - id: dsh-notify-bridge
      name: '@local/dsh-notify-bridge'
      config:
        notifyRoot: 'C:/Users/nolit/Workspace/projects/DSH Notify'
        onComplete: true
        onApproval: true
        onQuestion: true
        onError: true
        completeCooldownMs: 5000
        debugLog: 'C:/Users/nolit/Workspace/projects/DSH Notify/cache/bridge.log'
```

## 이벤트

| DSH 이벤트 | 알림 |
|---|---|
| `api-session/status` (running=false) | `DSH 작업 완료` |
| `approval/request` | `DSH 승인 필요` (waterfall — `next()` 그대로 통과) |
| `user-questions/request` | `DSH 질문 대기` |
| `agent/error` | `DSH 오류` |

## 테스트

```powershell
node .\bridge\test.mjs
```
