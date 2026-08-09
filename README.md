# SS Family 관심기업 분석

8개 관심기업을 다루는 정적 홈페이지입니다. 종목별 페이지(`stocks/*.html`)는 OpenDART 재무제표·Yahoo
Finance 시세·한경 컨센서스 등 실데이터를 페이지 안에 직접 기술해 넣은 완전 정적 HTML이며(런타임에
JSON을 fetch하지 않음), `file://`로 직접 열어도 그대로 동작합니다.

## 대상 기업

- 삼성전자(005930)
- KB금융(105560)
- 신한지주(055550)
- 기아(000270)
- 한화(000880)
- PKC(001340)
- 에이블씨엔씨(078520)
- HJ중공업(097230)

## 페이지 작성/갱신 방식

새 종목 추가나 재무데이터 갱신은 `data-collector`/`chart-builder`/`news-collector`/`stock-analyst`
서브에이전트로 DART·Yahoo Finance·네이버뉴스 데이터를 수집한 뒤 `stocks/NNN_CODE.html`을 직접
작성/수정하는 방식입니다(과거의 `data/stocks.json` + `js/app.js`/`js/stock.js` 동적 렌더링 구조는
제거됨). `data/financials.json`, `data/consensus.json`은 그 과정에서 모은 재사용 가능한 원본 데이터입니다.

가격·캔들차트는 로컬에만 있는 `update_daily_charts.ps1`(저장소에는 커밋하지 않음, kospi10000과 동일
컨벤션)로 평일 매일 자동 갱신됩니다.

## 로컬 실행

```powershell
.\serve.ps1
```

브라우저에서 `http://localhost:8792/`를 엽니다.

## 배포

전체 폴더를 GitHub Pages 등 정적 호스팅에 배포할 수 있습니다.
