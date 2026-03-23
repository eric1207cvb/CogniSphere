# Backend Auth MVP

這份文件定義 CogniSphere iOS client 已經預留好的最小後端驗證流程。目標是把 AI / OCR 權限判斷移到 server，不再只信任 app 自己送來的 entitlement header。

## Info.plist 設定

若要啟用新流程，app 端需要在 `Info.plist` 設定：

- `ProtectedSessionURL`
- `ProtectedChatURL`

兩個值都存在時，client 會先向 `ProtectedSessionURL` 換短效 token，再以 `Authorization: Bearer <token>` 打 `ProtectedChatURL`。若兩個值都沒填，client 會維持舊的 legacy chat endpoint。

## Session Endpoint

`POST /api/subscription/session`

Request headers:

- `Content-Type: application/json`
- `X-CogniSphere-App-User-ID: <app_user_id>`

Request body:

```json
{
  "app_user_id": "cognisphere-xxxx",
  "platform": "ios",
  "entitlement_id": "pro",
  "request_kind": "smart_scan",
  "subscription_state": {
    "is_subscriber": true,
    "updated_at": "2026-03-23T12:00:00Z"
  }
}
```

欄位說明：

- `app_user_id`: 與 RevenueCat `appUserID` 相同，server 應用這個值查真實 entitlement。
- `entitlement_id`: 目前 app 內使用的 entitlement，例如 `pro`。
- `request_kind`: `smart_scan`、`reference_image_ocr`、`pdf_summary`、`ocr_repair` 其中之一。
- `subscription_state`: client 最後一次看到的本地訂閱狀態，只能當提示，不能當最終信任來源。

Response body:

```json
{
  "token": "jwt-or-random-session-token",
  "expires_at": "2026-03-23T13:00:00Z",
  "subscription": {
    "entitlement_active": true,
    "product_id": "tw.yian.cognisphere.pro.monthly"
  },
  "quota": {
    "remaining_free_uses_today": 2
  }
}
```

最低必要欄位只有：

- `token`
- `expires_at`，可省略；若省略，client 會把 token 視為短效並在約 10 分鐘內重拿

## Protected Chat Endpoint

`POST /api/protected/chat`

Request headers:

- `Content-Type: application/json`
- `Authorization: Bearer <token>`
- `X-CogniSphere-App-User-ID: <app_user_id>`
- `X-CogniSphere-Entitlement-ID: <entitlement_id>`
- `X-CogniSphere-Request-Kind: <request_kind>`

Request body:

- 沿用目前既有 OpenAI-compatible chat payload，client 不需要額外改 prompt 結構。

Response body:

- 沿用目前既有 chat completion JSON 格式。

## Backend 驗證規則

Server 最低限度要做：

1. 驗證 `Authorization` token 是 backend 自己簽發且未過期。
2. 依 `app_user_id` 查 RevenueCat 或你自己的訂閱狀態來源，不信任 client 自報 `is_subscriber`。
3. 無有效 entitlement 時，改查 backend quota，至少做到 `app_user_id + day_key` 的每日限制。
4. 在真正把請求轉送上游 AI 前原子扣 quota，避免競態下白嫖。

## 建議錯誤碼

- `401`: token 無效或過期
- `402`: 沒有有效訂閱且免費額度已用完
- `403`: entitlement 或 request kind 不允許
- `429`: 達到 rate limit 或風控限制
- `503`: 上游 AI 暫時不可用

client 目前行為：

- `401` 時會先清掉舊 token，再重拿一次 session token 後重試同一個請求
- 其他狀態碼直接交由既有 UI 流程處理
