# T05 红（CI 真编译红）— run 44608129270

- headSha: 6154e83（test(selection): 行带接线红用例——控制器注入改名 trailHitProvider→rowBandHitProvider，签名先行）
- conclusion: failure（rerun 后取得真红；首跑 build job 因『The job was not acquired by Runner of type hosted』macOS arm64 容量未获取——非代码红，如实记录）
- core-linux: PASS（57s，Core 在红提交上全绿）
- 红证据（build job，log 全文 4388 行见 ../red-compile-failure.log 同目录 t05/red-compile-failure.log）:
  - `LibraryViewController.swift:796:20: error: value of type 'LibrarySelectionController' has no member 'trailHitProvider'`（Build (simulator) / Build unsigned ipa / Performance tests 三处一致）
  - `** BUILD FAILED **`
- 语义：VC 旧调用点仍引用旧注入名 → T05 接线必须改为 rowBandHitTest 路径（预期红）
- 附件：red-meta.json
