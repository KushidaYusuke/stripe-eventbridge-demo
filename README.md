## 概要
- Stripe の Event Destination（Amazon EventBridge 連携）で受け取ったパートナーイベントを Lambda で処理し、DynamoDB に保存するシンプルなサンプルです。
- Terraform で EventBridge パートナーイベントバス、ルール、Lambda、IAM ロール/ポリシー、DynamoDB テーブルを作成します。


## 監視しているイベント

| 状態の変化          | 発火イベント                          |
| -------------- | ------------------------------- |
| サブスク作成         | `customer.subscription.created` |
| サブスクの内容が変更された  | `customer.subscription.updated` |
| トライアル終了後、請求書作成 | `invoice.created`               |
| 支払い成功          | `invoice.payment_succeeded`     |
| 支払い失敗          | `invoice.payment_failed`        |
| サブスクが削除/キャンセル  | `customer.subscription.deleted` |

EventBridge のルールでは上記 6 種類の `detail-type` のみを許可し、その他の Stripe イベントは Lambda に渡さないようフィルタしています。


## 事前準備
- Terraform v1.6 以上
- AWS アカウント（デフォルトは `ap-northeast-1`。必要なら `aws_region` を変更）
- Stripe アカウント（Event Destination で Amazon EventBridge を有効化できる権限）
- AWS CLI 資格情報が環境に設定済み

## 使い方
1. **Stripe 側で EventBridge を有効化**  
   Stripe Dashboard → Developers → Event destinations → Amazon EventBridge を追加。  
   表示されるパートナーイベントソース名を控えます（例: `aws.partner/stripe.com/12345/prod`）。

2. **変数を設定**  
   `terraform.tfvars` を作成し、少なくともパートナーソースのプレフィックスを指定します。
   ```hcl
   aws_region                     = "ap-northeast-1"
   stripe_event_source_name_prefix = "aws.partner/stripe.com/12345/prod"
   table_name                     = "stripe_webhooks"
   project_name                   = "stripe-eventbridge-demo"
   ```

3. **デプロイ**  
   ```bash
   terraform init
   terraform apply
   ```
   完了後に表示される出力で、作成された Lambda 名や DynamoDB テーブル名を確認できます。

4. **動作確認**  
   - Stripe の「Send test event」から任意のイベントを送信します。  
   - DynamoDB テーブル（デフォルト `stripe_webhooks`）に `event_id` をキーとしたレコードが作成されることを確認します。

5. **後片付け**  
   ```bash
   terraform destroy
   ```
   データ保持が不要なら DynamoDB テーブルも一緒に削除されます。

## 仕組み
- EventBridge パートナーイベントバスは Stripe のパートナーソース名と同名で作成されます。
- ルールはパートナーイベントバス上のうち、上記 6 つの `detail-type`（サブスク関連と請求/支払い関連）だけを Lambda に転送します。
- Lambda は受信イベントの `detail` から Stripe イベント ID を取得し、DynamoDB に idempotent に保存します（`event_id` が既に存在する場合はスキップ）。

## データフロー（Mermaid）
```mermaid
flowchart LR
    Stripe["Stripe\n(Event Destination)"]
    PartnerSource["EventBridge\nPartner Source"]
    Bus["EventBridge\nPartner Event Bus"]
    Rule["EventBridge Rule\n(source + detail-type)"]
    Lambda["Lambda\nhandler.py"]
    DDB["DynamoDB\n(event_id PK)"]
    Logs["CloudWatch Logs"]

    Stripe --> PartnerSource
    PartnerSource --> Bus
    Bus --> Rule
    Rule --> Lambda
    Lambda --> DDB
    Lambda --> Logs
```

## カスタマイズ例
- 監視するイベントタイプを増減したい場合: `main.tf` の `aws_cloudwatch_event_rule` にある `detail-type` 配列へ追記/削除してください。
- 保存項目を増やしたい場合: `lambda/handler.py` の `item` にフィールドを足してください。

## 注意点
- パートナーイベントソースは Stripe 側で有効化しないと `data.aws_cloudwatch_event_source` が見つかりません。先に Stripe 設定を完了させてください。
- `terraform.tfstate` は機密情報を含むためバージョン管理に含めないようにしてください。
