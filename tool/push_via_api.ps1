$ErrorActionPreference = 'Stop'
$repo = '820sz/ai-shangwaiyu'
$branch = 'master'
# diff 基准:一个本地提交,其 tree 与远端当前 tree 一致(增量同步)
# 首次(远端停在 v1.2.1)用 4a693160;之后每次同步后记下当时的本地 HEAD。
$diffBaseRef = if ($env:RF_DIFF_BASE) { $env:RF_DIFF_BASE } else { '4a693160' }
$diffBase = (git rev-parse $diffBaseRef).Trim()
$tmpLines = Join-Path $PWD '_tmp_tree_lines.jsonl'
$tmpShow = Join-Path $PWD '_tmp_blob_show.bin'
$tmpJson = Join-Path $PWD '_tmp_api_body.json'
$cacheFile = Join-Path $PWD 'tool\_blob_cache.json'

function GhRetry([string[]]$ghArgs, [int]$max = 6) {
  for ($i = 0; $i -lt $max; $i++) {
    try {
      $out = & gh @ghArgs 2>$null
      if ($out) {
        # gh 多行输出在 PS 里是数组:必须按换行拼回,否则各行被空格连成一行
        $joined = ($out | ForEach-Object { "$_" }) -join "`n"
        if ($joined.Trim().Length -gt 0) { return $joined.Trim() }
      }
    } catch { }
    Start-Sleep -Seconds 5
  }
  return $null
}

function Get-TreeEntries([string]$tsha) {
  $raw = GhRetry @('api', "repos/$repo/git/trees/$tsha", '--jq', '.tree[] | @json')
  if (-not $raw) { throw "TREE_FETCH_FAIL $tsha" }
  $raw | Out-File -Encoding utf8 -FilePath $tmpLines
  $list = @()
  foreach ($line in Get-Content $tmpLines) {
    if ($line.Trim().StartsWith('{')) { $list += $line.Trim() | ConvertFrom-Json }
  }
  return $list
}

if (-not (git cat-file -t $diffBase 2>$null)) { Write-Output 'BASE_CATFILE_FAIL'; exit 1 }

$local = (git rev-parse HEAD).Trim()
Write-Output "local HEAD = $local"

# ── 变更清单(含删除/重命名) ──
$changed = [System.Collections.Generic.HashSet[string]]::new()
$deleted = [System.Collections.Generic.HashSet[string]]::new()
foreach ($line in git diff-tree -r --name-status $diffBase 'HEAD') {
  $parts = $line.Trim() -split "`t"
  $status = $parts[0]
  if ($status.StartsWith('D')) { [void]$deleted.Add($parts[1].Trim().Replace('\','/')); continue }
  if ($status.StartsWith('A') -or $status.StartsWith('M')) { [void]$changed.Add($parts[1].Trim().Replace('\','/')); continue }
  if ($status.StartsWith('R') -or $status.StartsWith('C')) {
    [void]$deleted.Add($parts[1].Trim().Replace('\','/'))
    [void]$changed.Add($parts[2].Trim().Replace('\','/'))
  }
}
$files = @($changed | Where-Object { -not $_.StartsWith('cc-archive/') })
Write-Output "changed files: $($files.Count), deleted: $($deleted.Count)"

# ── blob 上传(带本地缓存,网络抖动可续传) ──
$cache = @{}
if (Test-Path $cacheFile) {
  try {
    $obj = Get-Content $cacheFile -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $cache[$p.Name] = $p.Value }
  } catch { }
}
$blobSha = @{}
$uploaded = 0
foreach ($f in $files) {
  $gitSha = (git rev-parse "HEAD:$f").Trim()
  if ($cache.ContainsKey($gitSha)) {
    $blobSha[$f] = $cache[$gitSha]
    continue
  }
  & cmd /c "git show HEAD:$f > $tmpShow" 2>$null
  if (-not (Test-Path $tmpShow)) { Write-Output "SHOW_FAIL $f"; exit 1 }
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($tmpShow))
  [IO.File]::WriteAllText($tmpJson, (@{ content = $b64; encoding = 'base64' } | ConvertTo-Json -Compress))
  $sha = GhRetry @('api', '-X', 'POST', "repos/$repo/git/blobs", '--input', $tmpJson, '--jq', '.sha')
  if (-not $sha) { Write-Output "BLOB_FAIL $f"; exit 1 }
  $blobSha[$f] = $sha
  $cache[$gitSha] = $sha
  [IO.File]::WriteAllText($cacheFile, ($cache | ConvertTo-Json -Compress))
  $uploaded++
  Write-Output "blob $f -> $($sha.Substring(0,8))"
}
Write-Output "blobs uploaded this run: $uploaded (cached: $($files.Count - $uploaded))"
Remove-Item $tmpJson -ErrorAction SilentlyContinue

# ── 目录集合 ──
$dirs = [System.Collections.Generic.HashSet[string]]::new()
[void]$dirs.Add('')
foreach ($f in $files) {
  $d = Split-Path $f -Parent
  while ($d -ne '') { [void]$dirs.Add($d.Replace('\','/')); $d = Split-Path $d -Parent }
}
# 被删除文件的父目录也必须重建!
# 否则当某个目录里"只有删除、没有新增/修改"时(v2.3.0 就踩到了:
# 单独删掉 lib/screens/input/widgets/ai_discovery_section.dart),
# 那个目录的 tree 不会被重新生成,被删的 entry 会永远留在远端树上 →
# 远端 tree 与本地 tree 不一致,TREE_MISMATCH_ABORT。
foreach ($f in $deleted) {
  $d = Split-Path $f -Parent
  while ($d -ne '') { [void]$dirs.Add($d.Replace('\','/')); $d = Split-Path $d -Parent }
}

# ── 拉取 base 树 ──
$dirSha = @{}
$entries = @{}
$parent = GhRetry @('api', "repos/$repo/git/ref/heads/$branch", '--jq', '.object.sha')
if (-not $parent) { Write-Output 'REMOTE_REF_FAIL'; exit 1 }
Write-Output "remote HEAD = $parent"
$rootTree = GhRetry @('api', "repos/$repo/git/commits/$parent", '--jq', '.tree.sha')
if (-not $rootTree) { Write-Output 'ROOT_TREE_LOOKUP_FAIL'; exit 1 }
$dirSha[''] = $rootTree
$pending = [System.Collections.Generic.Queue[string]]::new()
$pending.Enqueue('')
while ($pending.Count -gt 0) {
  $d = $pending.Dequeue()
  $list = Get-TreeEntries $dirSha[$d]
  $entries[$d] = $list
  foreach ($e in $list) {
    if ($e.type -eq 'tree') {
      $child = $e.path
      if ($d -ne '') { $child = "$d/$($e.path)" }
      $dirSha[$child] = $e.sha
      if ($dirs.Contains($child)) { $pending.Enqueue($child) }
    }
  }
}
Remove-Item $tmpLines -ErrorAction SilentlyContinue
Write-Output "fetched trees: $($entries.Count)"

# ── 从深到浅重建树 ──
$newTreeSha = @{}
$ordered = @($dirs | Where-Object { $_ -ne '' } | Sort-Object { ($_ -split '/').Length } -Descending)
foreach ($d in $ordered) {
  $out = @()
  $baseList = $entries[$d]
  if ($null -ne $baseList) {
    foreach ($e in $baseList) {
      $full = $e.path
      if ($d -ne '') { $full = "$d/$($e.path)" }
      if ($deleted.Contains($full)) { continue }
      if ($e.type -eq 'tree') {
        if ($newTreeSha.ContainsKey($full)) {
          $out += @{ path = $e.path; mode = $e.mode; type = 'tree'; sha = $newTreeSha[$full] }
          continue
        }
      } elseif ($blobSha.ContainsKey($full)) {
        $out += @{ path = $e.path; mode = $e.mode; type = $e.type; sha = $blobSha[$full] }
        continue
      }
      $out += @{ path = $e.path; mode = $e.mode; type = $e.type; sha = $e.sha }
    }
  }
  foreach ($f in $files) {
    $dir = Split-Path $f -Parent
    if ($dir -ne '') { $dir = $dir.Replace('\','/') }
    if ($dir -eq $d) {
      $name = Split-Path $f -Leaf
      if (-not ($out | Where-Object { $_.path -eq $name })) {
        $out += @{ path = $name; mode = '100644'; type = 'blob'; sha = $blobSha[$f] }
      }
    }
  }
  foreach ($child in $dirs) {
    if ($child -eq '') { continue }
    $cparent = Split-Path $child -Parent
    if ($cparent -ne '') { $cparent = $cparent.Replace('\','/') }
    if ($cparent -eq $d -and $newTreeSha.ContainsKey($child)) {
      $cname = Split-Path $child -Leaf
      if (-not ($out | Where-Object { $_.path -eq $cname })) {
        $out += @{ path = $cname; mode = '040000'; type = 'tree'; sha = $newTreeSha[$child] }
      }
    }
  }
  $out = @($out | Sort-Object -Property path)
  [IO.File]::WriteAllText($tmpJson, (@{ tree = @($out) } | ConvertTo-Json -Depth 6 -Compress))
  $sha = GhRetry @('api', '-X', 'POST', "repos/$repo/git/trees", '--input', $tmpJson, '--jq', '.sha')
  if (-not $sha) { Write-Output "TREE_POST_FAIL $d"; exit 1 }
  $newTreeSha[$d] = $sha
  Write-Output "tree $d -> $($sha.Substring(0,8))"
}
Remove-Item $tmpJson -ErrorAction SilentlyContinue

# ── 根树 ──
$out = @()
foreach ($e in $entries['']) {
  if ($deleted.Contains($e.path)) { continue }
  if ($e.type -eq 'tree') {
    if ($newTreeSha.ContainsKey($e.path)) {
      $out += @{ path = $e.path; mode = $e.mode; type = 'tree'; sha = $newTreeSha[$e.path] }
      continue
    }
  } elseif ($blobSha.ContainsKey($e.path)) {
    $out += @{ path = $e.path; mode = $e.mode; type = $e.type; sha = $blobSha[$e.path] }
    continue
  }
  $out += @{ path = $e.path; mode = $e.mode; type = $e.type; sha = $e.sha }
}
foreach ($f in $files) {
  if ($f -notmatch '/') {
    if (-not ($out | Where-Object { $_.path -eq $f })) {
      $out += @{ path = $f; mode = '100644'; type = 'blob'; sha = $blobSha[$f] }
    }
  }
}
foreach ($child in $dirs) {
  if ($child -eq '' -or $child -match '/') { continue }
  if ($newTreeSha.ContainsKey($child) -and -not ($out | Where-Object { $_.path -eq $child })) {
    $out += @{ path = $child; mode = '040000'; type = 'tree'; sha = $newTreeSha[$child] }
  }
}
$out = @($out | Sort-Object -Property path)
[IO.File]::WriteAllText($tmpJson, (@{ tree = @($out) } | ConvertTo-Json -Depth 6 -Compress))
$rootNew = GhRetry @('api', '-X', 'POST', "repos/$repo/git/trees", '--input', $tmpJson, '--jq', '.sha')
if (-not $rootNew) { Write-Output 'ROOT_TREE_FAIL'; exit 1 }
Remove-Item $tmpJson -ErrorAction SilentlyContinue
$localTree = (git rev-parse 'HEAD^{tree}').Trim()
Write-Output "local tree = $localTree"
Write-Output "api  tree  = $rootNew"
if ($rootNew -ne $localTree) { Write-Output 'TREE_MISMATCH_ABORT'; exit 2 }

# ── 提交 + 更新 ref ──
$msg = if ($env:RF_MSG) { $env:RF_MSG } else { (git log -1 --pretty=%B HEAD) -join "`n" }
[IO.File]::WriteAllText($tmpJson, (@{ message = $msg; tree = $rootNew; parents = @($parent) } | ConvertTo-Json -Compress))
$newCommit = GhRetry @('api', '-X', 'POST', "repos/$repo/git/commits", '--input', $tmpJson, '--jq', '.sha')
if (-not $newCommit) { Write-Output 'COMMIT_FAIL'; exit 1 }
Remove-Item $tmpJson -ErrorAction SilentlyContinue
Write-Output "commit -> $newCommit"
[IO.File]::WriteAllText($tmpJson, (@{ sha = $newCommit; force = $true } | ConvertTo-Json -Compress))
$refOut = GhRetry @('api', '-X', 'PATCH', "repos/$repo/git/refs/heads/$branch", '--input', $tmpJson, '--jq', '.object.sha')
Remove-Item $tmpJson -ErrorAction SilentlyContinue
if (-not $refOut) { Write-Output 'REF_UPDATE_FAIL'; exit 1 }
Write-Output "ref updated -> $refOut"
Write-Output 'PUSH_VIA_API_DONE'
