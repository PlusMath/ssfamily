# SS Family 관심기업 분석

8개 관심기업을 OpenDART 재무제표로 구성하는 정적 홈페이지입니다.

## 대상 기업

- 삼성전자(005930)
- KB금융(105560)
- 신한지주(055550)
- 기아(000270)
- 한화(000880)
- PKC(001340)
- 에이블씨엔씨(078520)
- HJ중공업(097230)

## DART 데이터 갱신

PowerShell에서 OpenDART 인증키를 현재 세션의 환경변수로 설정하고 실행합니다.

```powershell
$env:DART_API_KEY = '발급받은 40자리 인증키'
.\update_dart.ps1
```

기본값은 직전 사업연도의 사업보고서(`11011`)입니다. 다른 보고서는 다음처럼 지정합니다.

```powershell
.\update_dart.ps1 -BusinessYear 2026 -ReportCode 11013 # 1분기
.\update_dart.ps1 -BusinessYear 2026 -ReportCode 11012 # 반기
.\update_dart.ps1 -BusinessYear 2026 -ReportCode 11014 # 3분기
```

수집기는 종목코드로 DART 고유번호를 찾고, 연결재무제표(CFS)를 우선 요청한 뒤 없으면 별도재무제표(OFS)를 사용합니다. 결과는 `data/financials.json`에 저장됩니다.

## 로컬 실행

```powershell
.\serve.ps1
```

브라우저에서 `http://localhost:8792/`를 엽니다. `file://`로 직접 열면 브라우저의 JSON 요청 제한 때문에 데이터가 표시되지 않을 수 있습니다.

## 배포

전체 폴더를 GitHub Pages 등 정적 호스팅에 배포할 수 있습니다. `DART_API_KEY`는 생성된 JSON에 포함되지 않습니다.
