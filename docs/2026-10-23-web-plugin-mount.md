# 웹 알림 플러그인 실운영 마운트 보고서

<!-- skeleton:
version: 1.0
kind: report
status: historical
updated: 2026-10-23
summary: Real-mount report for the web notification plugin: how it was mounted and what the live boot proved.
-->


> 상태: active · 최종 갱신: 2026-10-23 · git: main · 상위: [dsh-notify README](../README.md)

- 실제 프로필: `C:\Users\nolit\.dsh\profiles\web` (`DSH_PROFILE=web`)
- 플러그인: `@nolit/dsh-notify-web` (`plugin/`, 로컬 링크)
- 마운트 완료: 2026-10-23 06:0x KST

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 등록 | web 프로필 dependency + bundle + loader entry |
| 2 | 런타임 | Plugin Manager에서 활성화, Settings → 알림 표시 |
| 3 | 비침습 | 사이드바 DOM 추가 없음, Settings/Overlay만 사용 |
| 4 | 실측 | 권한 granted, 테스트 알림 전송 |
| 5 | 재현·복구 | 설치/활성화/확인 명령 |

## 1. 프로필 등록

```text
C:\Users\nolit\.dsh\profiles\web\package.json
  dependencies["@nolit/dsh-notify-web"] = "link:C:/Users/nolit/Workspace/projects/DSH Notify/plugin"
  dsh.profile.bundles += "@nolit/dsh-notify-web"
```

`node_modules\@nolit\dsh-notify-web`은 체크아웃 `plugin\`을 가리키는 Junction이다.
`dsh --dump-config --profile web`에 다음 entry가 포함된다.

```yaml
- id: dsh-notify-web
  name: '@nolit/dsh-notify-web'
  config:
    notifyOnComplete: true
    notifyOnApproval: true
    notifyOnQuestion: true
    notifyOnError: true
    completeCooldownMs: 5000
    soundEnabled: true
    soundSource: synth
    volume: 0.3
    suppressWhenFocused: false
    requireInteractionForApproval: true
    notifyOnSubagents: false
```

> 요청 표기의 `@local/dsh-notify-web`은 개념적 이름이고, 실제 패키지 ID는 `@nolit/dsh-notify-web`이다.
> DSH 프로필에는 실제 package.json name으로 등록해야 한다.

## 2. 런타임 마운트

DSH Plugins 페이지에서 `DSH 알림 (웹)` 항목의 토글을 **On**으로 전환했다.
이후 페이지를 새로고침하자 Settings 모달에 `알림` 탭이 나타났다.

- Settings → 알림
  - `DSH 알림`
  - `알림 켜짐`
  - `브라우저 알림 켜기`
  - `소리 켜기`
  - `테스트 알림`
  - 알림 종류: 턴 완료 / 도구 승인 필요 / 질문 대기 / 오류 / 서브에이전트 / 포커스 숨김
  - 소리: 알림 소리 사용 / 소리 소스
  - `권한: granted`

## 3. 비침습 확인

- 플러그인은 `settings.section`과 `shell.overlay`만 등록한다.
- 사이드바 footer/header에 새 DOM을 추가하지 않는다.
- 실제 화면에서도 기존 사이드바 항목(새 세션, 플러그인, 자동화 작업, 워크스페이스 관리자, 세션 검색, 계정 메뉴)은 그대로였다.
- `sidebar.footer.action`/`conversation.header`를 사용하지 않는 구현 계약을 유지한다.

## 4. 실측

| 항목 | 결과 |
|---|---|
| 프로필 dependency | `link:` Junction 확인 |
| 번들 목록 | `@nolit/dsh-notify-web` 포함 |
| `dsh --dump-config` | `dsh-notify-web` entry + config 확인 |
| Plugins 페이지 | `DSH 알림 (웹)` toggle **On** |
| Settings | `알림` 탭 표시 |
| 브라우저 권한 | `granted` |
| 테스트 알림 | `테스트 알림을 보냈습니다.` |
| 사이드바 변경 | 없음 |

## 5. 재현·복구

```powershell
dsh plugin --profile web add "link:C:/Users/nolit/Workspace/projects/DSH Notify/plugin"
dsh --dump-config --profile web
# DSH Plugins 페이지에서 DSH 알림 (웹) 토글 On
# Settings → 알림에서 권한/소리/테스트 확인
```

롤백:

```powershell
dsh plugin --profile web remove "@nolit/dsh-notify-web"
# 또는 Plugins 페이지에서 토글 Off
```

백업은 `C:\Users\nolit\.dsh\profiles\web\package.json.bak-notify-*` 및
`cordis.patch.yml.bak-notify-*`에 남겨 두었다.
