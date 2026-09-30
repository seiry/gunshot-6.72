# Google Photos アプリ解析の索引

提供 IPA の静的解析、現在の実装、検証項目への入口です。クラスや selector の存在確認、mock test、実機・サーバーでの確認は区別してください。

| 対象 | 参照先 |
| --- | --- |
| 6.72.0 / 7.20.2 / 7.92.0 の API・ABI 差分、必要 OS | [6.72.0 互換性監査](google-photos-6.72.0.md) / [7.20.2 互換性監査](google-photos-7.20.2.md) / [6.72.0 contracts](objc/6.72.0-contracts.json) / [7.20.2 contracts](objc/7.20.2-contracts.json) |
| 全クラス・instance selector・encoding・static IMP | [機械可読索引と検索方法](objc/README.md) / [入力 hash・件数](objc/manifest.json) |
| 手動・自動バックアップの使い方、対応経路、診断 | [バックアップ転送](../native-routing.md) |
| 共通要求の移譲・再照合・画質 | [処理の解析と回帰修正](backup-routing.md) |
| native completion の内部依存 | [限定した関数の静的解析](completion-analysis.md) |
| 原本画質の表示と完了後同期 | [画質表示と同期](original-quality-display.md) |
| native SSO・ログイン中のアカウントとの連携 | [認証とアカウントメニュー](native-account.md) |
| 設定メニューのタップ処理 | [UI の解析と修正](account-menu-tap.md) |
| 純正の無制限ストレージ表示 | [表示専用 hook](unlimited-storage.md) |
| Go uploader・認証・永続キュー・IPC | [実装構成](../architecture.md) |
| パッケージの利用・jailed / LiveContainer | [README](../../README.md) / [jailed](../jailed.md) |
| 実機で確認すべき項目 | [検証チェックリスト](../device-validation.md) / [一括取込](../bulk-import.md) |

## 解析範囲と限界

instance-method 索引は 7.92.0 の本体と generated framework の 2 image が対象です。class method、category、Swift-only / C / C++ 関数、拡張 executable、全 call graph は対象外です。具体的な抽出範囲は[索引の説明](objc/README.md#抽出範囲と限界)を参照してください。

通常の PHAsset バックアップは転送・再照合の実装がありますが、locked folder の暗号化・鍵管理、編集 / CNDE / 生成コンテンツ、共有・partner sharing、既存 background URLSession まで網羅した保証はありません。native DB の schema / mutation 全体、私有 protobuf の全 descriptor、検索・顔認識・Lens・memories 等の全機能も未解析です。

native account 連携は実装済みですが、静的解析や CI は実認証、サーバー側の画質・quota、Live Photo の pairing / commit / 再生、端末での動作の証明にはなりません。未解析・未検証という記載から、機能の有無や安全性を断定しないでください。
