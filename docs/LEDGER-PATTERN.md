# 台帳（Google スプレッドシート）を AI から読み書きする型

任意の機能です。タスクや定例を1枚のスプレッドシートに集め、スケジュールタスクや各セッションの AI が同じ台帳を読み書きするための型を説明します。
**自分の台帳の ID・サービスアカウントのメール・実データは、このリポジトリには書かず、環境変数や自分のプロジェクトの文書に置きます。**

## 仕組み

1. Google Cloud にサービスアカウントを作り、台帳のスプレッドシートに「編集者」として共有する。
2. クラウド環境に、`iamcredentials.googleapis.com` 宛の通信にだけ認証を付けるネットワークシークレット（サービスアカウントの鍵）を登録する。鍵の中身はセッションから見えない。
3. セッションは `POST https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/<サービスアカウントのメール>:generateAccessToken` に本文 `{"scope":["https://www.googleapis.com/auth/spreadsheets"]}` を送り、短命（約1時間）のアクセストークンを得る。
4. そのトークンを `Authorization: Bearer` に付けて Sheets API v4 を呼ぶ。

`lib/ledger_sheets.py` が 3〜4 を行う最小のクライアントです。

## 人間が用意するもの

| 項目 | 内容 |
| --- | --- |
| スプレッドシート | 台帳の本体。タブ構成は自由（例: タスク／定例／受信箱／変更履歴） |
| サービスアカウント | 台帳に編集者として共有する。メールを `AI_KIT_LEDGER_SA` に |
| スプレッドシート ID | URL の `/d/` と `/edit` の間。`AI_KIT_LEDGER_SHEET_ID` に |
| ネットワークシークレット | 上の手順 2。登録は環境の設定画面で行う |
| コネクタ（任意） | Google Calendar など、台帳と合わせて使うもの |

環境変数 `AI_KIT_LEDGER_SHEET_ID` と `AI_KIT_LEDGER_SA` が無いとき、`lib/ledger_sheets.py` はそれを案内して終了します。

## サービスアカウントの権限（安全面）

ネットワークシークレットがある環境では、そのセッションは任意の範囲（scope）のアクセストークンを作れます。被害を小さくするため:

- サービスアカウントには、GCP プロジェクトの IAM ロールを付けない（台帳のシートに「編集者」として共有するだけ）。
- 専用のプロジェクトに作り、台帳以外のファイルは共有しない。
- 登録できたかの確認は、`python3 /home/user/ai-agent-kit/lib/ledger_sheets.py` が成功すること。

## 使い方

```bash
export AI_KIT_LEDGER_SHEET_ID=<スプレッドシート ID>
export AI_KIT_LEDGER_SA=<サービスアカウントのメール>
python3 /home/user/ai-agent-kit/lib/ledger_sheets.py            # タイトルとタブ一覧を表示（読み取りテスト）
```

Python からは `sys.path.insert(0, "/home/user/ai-agent-kit/lib")` のあと `from ledger_sheets import api` として `api("GET", "/values/<タブ名>!A1:Z50")` のように呼びます。

## 運用上の注意（AI エージェント向け）

- 書き込む前に、必ず対象のセルを読む。更新は該当セルだけにして、変更履歴タブに「いつ・どこを・変更前・変更後・理由」を残す。
- 推測で完了にしない。更新した内容は引用して報告する。
- 給与明細・パスワード・他人の個人情報は台帳に書かない。
- 書き込みが `sheets.googleapis.com` で 403 になるときは、そのセッションが手元のパソコンに接続されている（Remote Control が有効）ときに起きた例がある。接続を切るか、接続していないセッションから行う（原因は環境により異なる可能性がある）。
- アクセストークンは約1時間で切れる。`lib/ledger_sheets.py` は呼ぶたびに取り直す。
