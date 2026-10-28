# DSH Notify Web

> 상태: active · 최종 갱신: 2026-10-29 · 패키지: `@nolit/dsh-notify-web` v0.1.6 · 상위: [README.md](../README.md)

DeepSeek Harness의 턴 완료·도구 승인·질문·오류를 **브라우저 알림과 브라우저 소리**로 알리는 웹 전용 플러그인입니다. 로컬 앱, 포트, IPC, 파일 큐, 시스템 의존성이 없습니다.

## 인덱스

| § | 섹션 | 한 줄 요약 |
|---|---|---|
| 1 | 동작 | DSH 이벤트 4종 → Web Notification + Web Audio |
| 2 | 설치 | web 프로필에 링크/번들 등록 |
| 3 | 설정 위치와 권한 | Settings → 알림, 첫 사용 동의 카드 |
| 4 | 한계 | DSH 탭이 열려 있을 때만 동작 |
| 4.1 | 브라우저 호환성 | Chromium 검증, Firefox/Safari 정책 제약 |
| 5 | 프라이버시 | 네트워크/로컬 서버 없음, localStorage + IndexedDB |
| 6 | 개발 | `node --test` |
| 7 | 라이선스 | MIT + 사용자 주입 에셋 면책 |
| 8 | 구조 | 헤드리스 코어 + Settings/Overlay 어댑터 |

## 1. 동작

| DSH 이벤트 | 알림 |
|---|---|
| `api-session/status` (`running=false`) | 작업 완료. 루트 세션만, 5초 쿨다운 |
| `api-session/error` | 오류. 메시지 160자 절단 |
| `approval/request` | 승인 필요. 알림 후 즉시 `next()` 통과 |
| `user-questions/request` | 질문 대기. 알림 후 즉시 `next()` 통과 |

- 여러 탭이 열려 있으면 **한 탭만** 알림을 담당합니다(Web Locks, 폴백 localStorage).
- Chrome OS Notification이 허용되어 표시되면 **인페이지 토스트를 생략**합니다. 차단·미지원·생성 실패 시에만 토스트와 탭 제목으로 폴백해 중복 표시를 피합니다.
- 소리는 Web Audio로 합성한 2음 차임이 기본입니다. 사용자가 선택한 BYO 오디오를 IndexedDB에 저장해 사용할 수 있으며, 오디오 파일을 번들하지 않습니다.
- `agent/turn-stopping`, `agent/error`는 사용하지 않습니다(전자는 serial, 후자는 브라우저 미전달).

## 2. 설치

로컬 체크아웃:

```powershell
dsh plugin --profile web add "link:C:\path\to\DSH Notify\plugin"
```

그 다음 web 프로필의 `dsh.profile.bundles`에 `@nolit/dsh-notify-web`이 포함되어야 합니다. DSH Plugins 페이지에서 번들을 켜도 됩니다.

이 저장소에서는 백업/검증/재시작 안내를 포함한 스크립트를 사용할 수 있습니다.

```bash
./scripts/install-notify-live.sh
systemctl --user restart dsh-web.service
```

npm 배포 후:

```powershell
dsh plugin --profile web add @nolit/dsh-notify-web
```

설치 후 DSH 페이지를 새로고침합니다. `lib/client.js`가 없거나 문법 오류가 있으면 플러그인만 비활성화되고 DSH 코어는 계속 동작합니다.

## 3. 설정 위치와 권한

- **설정 → 알림**: DSH 공식 Settings 모달의 `settings.section`에 "알림" 섹션이 추가됩니다. 권한/소리/필터/BYO 오디오/테스트를 모두 여기서 설정합니다.
- 첫 실제 알림 이벤트에서 권한이 `default`이면 페이지당 1회 자동으로 `requestPermission()`을 시도합니다(Hermes WebUI와 동일한 동작). 브라우저가 사용자 제스처를 요구해 거부하면 화면 토스트·탭 제목·소리로 폴백합니다.
- 명시적으로 켜려면 페이지 우하단의 일회성 동의 카드에서 **알림 켜기**를 누르면 `requestPermission()`과 `AudioContext.resume()`이 같은 사용자 제스처로 실행됩니다.
- **나중에**를 누르면 카드가 다시 뜨지 않으며, 이후 Settings → 알림에서 변경할 수 있습니다.
- 브라우저/OS 알림 설정, 집중 지원, 탭 음소거에 따라 실제 표시/소리가 달라질 수 있습니다. 플러그인은 표시 여부를 확정할 수 없습니다.
- DSH 포트나 도메인이 바뀌면 새 출처가 되므로 권한과 소리를 다시 활성화해야 합니다.
- **원격 Chrome 접속**에서는 DSH 호스트가 아니라 **접속한 PC의 Chrome/OS 알림 설정**을 따릅니다. `http://<LAN-IP>:3080`은 보안 컨텍스트가 아니므로 Chrome이 OS 알림을 차단합니다. HTTPS 또는 SSH/로컬 포트포워딩으로 `http://127.0.0.1:3080`에 접속해야 OS 알림을 사용할 수 있습니다.
- DSH 호스트에서 브라우저를 직접 띄우는 경우에만 Linux `org.freedesktop.Notifications` 데몬이 필요합니다. 원격 브라우저 사용 시 호스트 데몬은 무관합니다.
- Settings → 알림의 **정보** 카드에서 최근 상태 이벤트와 최근 알림 전달 결과를 확인할 수 있습니다.
- 사이드바 푸터/헤더에는 아무 UI도 추가하지 않습니다. 접힘·좁은 화면·우측 패널 상태와 무관하게 Settings에서 설정합니다.

## 4. 한계

- **DSH 탭이 열려 있을 때만** 알림이 동작합니다. 탭이 닫히거나 브라우저가 discard하면 알림이 없습니다. 서비스 워커 푸시 백엔드가 없기 때문입니다.
- 백그라운드 탭 타이머 스로틀, 브라우저 알림 정책, OS 방해 금지의 영향을 받습니다.
- 승인/질문 알림은 DSH 승인 UI를 대체하지 않습니다. 알림을 보여주고 `next()`를 그대로 통과시킵니다.
- 알림 본문은 고정 문구 + 세션 제목 80자입니다. 프롬프트/코드/도구 인자는 넣지 않습니다.

## 4.1 🌐 브라우저 호환성 안내 (Browser Compatibility)

### 공식 지원 및 검증 완료

- **Chromium 계열 브라우저**: Google Chrome, Microsoft Edge, Naver Whale, Brave 등
- OS 데스크톱 알림 배너, 고유 태그 기반 중복 드롭 방지, Web Audio 및 시스템 알림음 연동이 모두 정상 작동하도록 검증되었습니다.

### 미검증 및 플랫폼 제약 (Unverified / Browser Policy Limits)

- **Mozilla Firefox**: 브라우저 자체의 엄격한 자동 재생(Autoplay) 차단 정책으로 인해, 주소창 설정에서 '오디오 및 비디오 자동 재생 허용'을 수동으로 활성화하지 않으면 비동기 턴 완료 사운드가 무음 처리될 수 있습니다.
- **Apple Safari (macOS / iOS)**: 백그라운드 탭 동결(Tab Freeze) 및 사용자 제스처 기반 미디어 정책으로 인해 백그라운드 사운드 출력이 제한될 수 있습니다.
- Chromium 외 브라우저 환경은 동작을 보증하지 않으며, 안정적인 알림 수신을 위해 **Chromium 기반 브라우저 사용을 권장**합니다.

> **🔊 소리가 나지 않을 때 (최초 1회 브라우저 설정 및 오디오 엔진 갱신)**:
>
> 1. 브라우저 주소창 왼쪽의 **설정(조율기/자물쇠) 아이콘** 클릭 ➔ **'사이트 설정'**
> 2. **'소리'** 항목을 `자동(기본값)`에서 **'허용'**으로 변경
> 3. 단순 새로고침(`F5`)으로는 크롬 백그라운드 오디오 서비스가 갱신되지 않을 수 있으므로, **주소창에 `chrome://restart`를 입력하여 브라우저를 완전히 재시작**한 뒤 사용

## 5. 프라이버시

- `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource`를 새로 만들지 않습니다.
- 파일 시스템, `%LOCALAPPDATA%`, 로컬 포트, IPC를 사용하지 않습니다.
- 설정/동의 상태는 브라우저 `localStorage`에 저장합니다.
- 사용자 BYO 오디오 바이트는 브라우저 `IndexedDB`(`dsh-notify-web/audio`)에만 저장하며, 외부로 전송하지 않습니다.
- 외부 링크를 열지 않습니다. 알림 클릭은 DSH 탭에 포커스만 줍니다.

## 6. 개발

```powershell
node --test .\plugin\test\client.test.mjs
```

테스트는 브라우저 API(Notification, AudioContext, localStorage, Web Locks)를 모의 객체로 대체해 이벤트 필터/쿨다운/승인 통과/폴백/리더/설정을 검증합니다.

## 7. 라이선스와 에셋

- 코드: MIT. [LICENSE](LICENSE) 참조.
- 이 패키지는 폰트, 로고, 사운드 파일을 **번들하지 않습니다.** 기본 아이콘은 중립적인 시계 SVG이며, 알림에는 아이콘을 지정하지 않습니다.
- 사용자가 별도로 주입한 폰트/아이콘/사운드의 라이선스와 재배포 권리는 전적으로 사용자에게 있습니다. 저장소의 [에셋 정책](../docs/2026-10-23-asset-policy.md)을 따릅니다.
- DeepSeek 공식 로고/상표는 이 패키지에 포함되지 않습니다.

## 8. 구조

- `lib/client.js`
  - `createNotifyCore()` — React/슬롯을 모르는 헤드리스 엔진. 이벤트 필터/쿨다운/권한/Web Audio/IndexedDB/localStorage/탭 리더/토스트 큐를 담당합니다.
  - `makeSettingsSection()` — `settings.section` 어댑터. 상태를 구독하고 폼만 렌더링합니다.
  - `makeOverlay()` — `shell.overlay` 어댑터. 첫 사용 동의 카드와 폴백 토스트만 렌더링합니다.
- `lib/index.js` — Loader 등록용 no-op host. 통신/파일/포트 코드가 없습니다.
- UI는 `sidebar.footer.action`/`conversation.header`를 사용하지 않습니다.

