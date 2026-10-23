# はじめてクラウド環境に取り込む手順（順を追ったガイド）

このリポジトリ（ai-agent-kit）を、Claude Code のクラウド環境（claude.ai/code）で使えるようにするまでの手順です。
上から順に進め、各ステップの最後にある「確認」が通ってから次へ進んでください。AI エージェントがこのガイドを読んでいるときは、**人間にしかできない手順**（★）で人間に依頼し、残りは自分で実行します。
トークン・パスワード・鍵は、**チャットに貼らず**、環境の設定画面に入れてもらいます。

## 0. 先に決めること

- 使う助手を選ぶ: Codex（ChatGPT プラン）、Cursor、agy（Google AI Pro）。使わないものは用意しなくてよい。
- ログインを保存する場所を決める: 毎回ログインし直したくなければ、Google ドライブ（`AI_KIT_DRIVE_*`）か、セッションをまたいで残るフォルダ（`AI_KIT_STORE=dir:...`）。決めなければ、セッションが終わるとログインは消える。

## 1. ★ GitHub をつなぐ

**すでに GitHub をつないであり、このリポジトリがプロジェクトに登録済みなら、手順 1〜2 は飛ばしてよい。**（リポジトリの所有者かどうかではなく、Claude のクラウドから届くかどうかの設定なので、初回だけ要る。）

クラウドのセッションがリポジトリを clone するには、GitHub への接続が要ります。

1. `https://claude.ai/connect-github` で GitHub アカウントをつなぐ。
2. Claude の GitHub アプリを、**このリポジトリに**インストールする（`https://github.com/apps/claude/installations/select_target`）。「選択したリポジトリのみ」にしている場合は、ai-agent-kit が含まれていることを確認する。

確認: `claude.ai/code` を開いたとき、リポジトリの一覧に ai-agent-kit が出る。

## 2. ★ リポジトリをプロジェクトやタスクに登録する

- **プロジェクトで使う場合**: プロジェクトの設定の「リポジトリ（resources）」に ai-agent-kit を追加する。そのプロジェクトのセッションでは `/home/user/ai-agent-kit` に clone される。
- **スケジュールタスク（routine）で使う場合**: 各タスクの編集画面でリポジトリに ai-agent-kit を追加する。登録しないと、そのタスクのセッションにはキットが無い。
- **ほかのリポジトリのセッションで使う場合**: キットはリポジトリとして追加せず、手順 3 のセットアップスクリプトで clone し、そのリポジトリの `.claude/settings.json` に `SETUP.md` の SessionStart フックを足す（複数リポジトリのセッションではフックが読み込まれない）。

確認: 新しいセッションで `ls /home/user/ai-agent-kit` が成功する。

## 3. ★ クラウド環境を設定する

claude.ai/code の環境メニュー（歯車アイコン）から、使う環境（例: Default）を開きます。

1. **Setup script** に、キットを入れるコマンドを書く（`SETUP.md` の例。`<owner>` は自分の GitHub アカウント）。`SETUP.md` の例のとおり、clone 済みなら再 clone しない形にする。
2. **環境変数 / ネットワークシークレット**に、必要な値を登録する（値はここにだけ入れる）:
   - Cursor を使う: `CURSOR_API_KEY`
   - Drive にログインを保存する（取得のしかたは `SETUP.md`）: `AI_KIT_DRIVE_CLIENT_ID` / `AI_KIT_DRIVE_CLIENT_SECRET` / `AI_KIT_DRIVE_REFRESH_TOKEN` / `AI_KIT_DRIVE_ROOT_FOLDER_ID`
   - ログインの保存先をフォルダにする: `AI_KIT_STORE=dir:<セッションをまたいで残る場所>`（Drive を使うなら不要）
   - 台帳（任意）: `AI_KIT_LEDGER_SHEET_ID`、`AI_KIT_LEDGER_SA`（`LEDGER-PATTERN.md`）
3. **ネットワーク**: 既定の「Trusted」は許可リストだけを通す。助手の通信が `host_not_allowed` や 403 で止まったら、そのドメインを「許可するドメイン」に足す（どのドメインが要るかは、エラーに出たホスト名で判断する）。

注意: Setup script は、保存した環境変数やシークレットを**読めない**（読めるのはセッション開始後）。また、結果が保存されて数日再利用されることがあるので、変更が反映されないときはスクリプトを少し書き換えて保存し直す。

確認: 新しいセッションを開き、Setup script が成功して起動する。

## 4. 新しいセッションで診断する

```bash
bash /home/user/ai-agent-kit/doctor.sh
```

`OK` は準備できている項目。`TODO` は足りない設定で、書かれている場所と手順に従う。環境変数の値は表示されない。
`TODO` が無くなるまで、3〜4 を繰り返す（手順 1〜2 の確認が通らないときは、下の「つまずいたとき」を見る）。ログイン保存の `TODO` は任意（`SETUP.md`）。

## 5. ★ 助手にログインする（初回だけ）

- **Codex**: エージェントが `bash /home/user/ai-agent-kit/codex/login.sh` をバックグラウンドで実行し、出たコードを人間に伝える。人間が `https://auth.openai.com/codex/device` を開いてコードを入力する。
- **agy**: エージェントが `python3 /home/user/ai-agent-kit/agy/login_headless.py start` を実行し、出た URL を人間に伝える。人間が開いて Google でログインし、得たコードをエージェントに渡す（`login_headless.py code <コード>`、約25分以内）。
- **Cursor**: 手順 3 の `CURSOR_API_KEY` で足りる。

Drive などの保存先が設定されていれば、以降のセッションではログインが自動で復元される。
同じログインを複数の場所で同時に使うと、更新で片方が切れる。クラウド用は別にログインする。

確認: `bash doctor.sh` で、使う助手が `OK` になる。

## 6. 動作を確かめる

読み取り専用の小さな依頼で確認します。

```bash
bash /home/user/ai-agent-kit/codex/delegate.sh "このリポジトリの README の見出しを列挙して"
```

Cursor は `cursor/delegate.sh`、agy は `agy/delegate.sh` に同じ形で依頼できる。回答が返り、`.codex-runs/` などにログが残れば成功。

## 7. （任意）スケジュール・タスク管理を始める

`TASK-SYSTEM.md`（全体像）と `LEDGER-PATTERN.md`（台帳のつなぎ方）を読み、台帳とサービスアカウントを用意して、朝・夕・週次・月次のスケジュールタスクを作る。

## つまずいたとき

| 症状 | 原因と対処 |
| --- | --- |
| セッションにキットが無い | 手順 2 のリポジトリ登録が抜けている |
| Setup script が失敗する（clone で 128） | リポジトリが非公開で、認証が付かない。リポジトリを登録するか、公開にする（`SETUP.md`） |
| 変数が空 | Setup script の中では読めない。セッション開始後のコマンドで読む |
| 助手の通信が 403 / `host_not_allowed` | 手順 3 のネットワーク許可に、そのドメインを足す |
| 毎回ログインを求められる | ログインの保存先が未設定（手順 0・3） |
| 台帳の書き込みが 403 | 手元のパソコンに接続された（Remote Control が有効な）セッション。接続を切る |
