# Bottle Mail 端到端验证脚本（PowerShell 5.1 / 7 均可）
# 用法:  powershell -ExecutionPolicy Bypass -File scripts/e2e-verify.ps1 -BaseUrl <url>
# 默认:  https://bottlemail.giftfor17.workers.dev
# 密码通过 Read-Host -AsSecureString 输入（不回显、不落盘、不打印）。
# 测试信件正文带 [TEST] 前缀，脚本结束时会自动删除；设备标记"开发测试设备"并撤销。
param(
    [string]$BaseUrl = "https://bottlemail.giftfor17.workers.dev"
)

$ErrorActionPreference = "Stop"
$script:Results = @()

function Step([string]$Name, [bool]$Ok, [string]$Detail = "") {
    $script:Results += [pscustomobject]@{ Step = $Name; Result = $(if ($Ok) { "PASS" } else { "FAIL" }); Detail = $Detail }
    Write-Host ("[{0}] {1} {2}" -f $(if ($Ok) { "PASS" } else { "FAIL" }), $Name, $Detail) -ForegroundColor $(if ($Ok) { "Green" } else { "Red" })
}

function Invoke-Api {
    param($Method, $Path, $Body = $null, $Headers = $null, $Session = $null)
    try {
        $params = @{ Method = $Method; Uri = "$BaseUrl$Path" }
        if ($Session) { $params.WebSession = $Session }
        if ($Headers) { $params.Headers = $Headers }
        if ($null -ne $Body) {
            $params.ContentType = "application/json"
            $params.Body = ($Body | ConvertTo-Json -Compress -Depth 6)
        }
        $response = Invoke-WebRequest @params -TimeoutSec 30
        return @{ Status = [int]$response.StatusCode; Content = $response.Content }
    } catch {
        $resp = $_.Exception.Response
        $status = 0
        $content = ""
        if ($resp) {
            $status = [int]$resp.StatusCode
            try {
                $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $content = $reader.ReadToEnd()
                $reader.Close()
            } catch { }
        } else {
            $content = $_.Exception.Message
        }
        return @{ Status = $status; Content = $content }
    }
}

# ---- 密码（不回显，用后清零） ----
$secure = Read-Host -Prompt "输入发信密码（不回显，仅用于本次验证）" -AsSecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# ---- 0. health ----
$h = Invoke-Api -Method GET -Path "/health"
Step "health 200" ($h.Status -eq 200) "status=$($h.Status)"

# ---- 1. 未登录发信应被拒绝 ----
$r = Invoke-Api -Method POST -Path "/api/letters" -Body @{ body = "[TEST] 未登录" }
Step "未登录发信 401" ($r.Status -eq 401) "status=$($r.Status)"

# ---- 2. 登录 ----
$page = Invoke-Api -Method GET -Path "/" -Session $session
$csrf = $session.Cookies.GetCookies($BaseUrl)["bottlemail_csrf"].Value
if (-not $csrf) { Step "获取 CSRF cookie" $false "no cookie" } else { Step "获取 CSRF cookie" $true "" }

$login = Invoke-Api -Method POST -Path "/api/session" -Body @{ password = $password } `
    -Headers @{ "X-CSRF-Token" = $csrf } -Session $session
Step "登录成功" ($login.Status -eq 200) "status=$($login.Status)"

$senderHeaders = @{ "X-CSRF-Token" = $csrf; "Origin" = $BaseUrl }

# ---- 3. 发信（中文 / 英文 / 换行 / Emoji，均带 [TEST] 前缀） ----
$testLetters = @()
$cases = @(
    @{ id = [guid]::NewGuid().ToString(); body = "[TEST] 你好呀，这是中文测试信。" },
    @{ id = [guid]::NewGuid().ToString(); body = "[TEST] Hello from the sender page." },
    @{ id = [guid]::NewGuid().ToString(); body = "[TEST] 第一行`n第二行`n第三行。" },
    @{ id = [guid]::NewGuid().ToString(); body = "[TEST] Emoji 测试 🌊🍾✨" }
)
foreach ($case in $cases) {
    $send = Invoke-Api -Method POST -Path "/api/letters" -Body @{ body = $case.body; client_request_id = $case.id } `
        -Headers $senderHeaders -Session $session
    Step "发信 201 ($($case.body.Substring(0, [Math]::Min(14, $case.body.Length)))…)" ($send.Status -eq 201) "status=$($send.Status)"
    if ($send.Status -eq 201) {
        $letter = $send.Content | ConvertFrom-Json
        $testLetters += $letter.id
    }
}

# ---- 4. 幂等去重：同 client_request_id 重发返回 200 且同 id ----
$dup = Invoke-Api -Method POST -Path "/api/letters" -Body @{ body = $cases[0].body; client_request_id = $cases[0].id } `
    -Headers $senderHeaders -Session $session
if ($dup.Status -eq 200) {
    $dupData = $dup.Content | ConvertFrom-Json
    Step "同 client_request_id 去重" (($dupData.duplicate -eq $true) -and ($dupData.id -eq $testLetters[0])) "duplicate=$($dupData.duplicate)"
} else {
    Step "同 client_request_id 去重" $false "status=$($dup.Status)"
}

# ---- 5. 空正文 400 ----
$bad = Invoke-Api -Method POST -Path "/api/letters" -Body @{ body = "   " } -Headers $senderHeaders -Session $session
Step "空正文 400" ($bad.Status -eq 400) "status=$($bad.Status)"

# ---- 6. 生成激活码 ----
$codeResp = Invoke-Api -Method POST -Path "/api/admin/activation-codes" -Headers $senderHeaders -Session $session
$code = $null
if ($codeResp.Status -eq 201) {
    $codeData = $codeResp.Content | ConvertFrom-Json
    $code = $codeData.code
    Step "生成激活码 201" $true "expires_at=$($codeData.expires_at)"
} else {
    Step "生成激活码 201" $false "status=$($codeResp.Status)"
}

# ---- 7. 兑换设备令牌 ----
$token = $null
$deviceId = $null
if ($code) {
    $act = Invoke-Api -Method POST -Path "/api/devices/activate" -Body @{ code = $code; label = "开发测试设备" }
    if ($act.Status -eq 201) {
        $actData = $act.Content | ConvertFrom-Json
        $token = $actData.device_token
        $deviceId = $actData.device_id
        Step "兑换设备令牌 201" $true "label=$($actData.label)"
    } else {
        Step "兑换设备令牌 201" $false "status=$($act.Status)"
    }

    $reuse = Invoke-Api -Method POST -Path "/api/devices/activate" -Body @{ code = $code }
    Step "同码重复兑换 409" ($reuse.Status -eq 409) "status=$($reuse.Status)"
}

# ---- 8. 设备拉取信件 ----
if ($token) {
    $deviceHeaders = @{ Authorization = "Bearer $token" }
    $poll = Invoke-Api -Method GET -Path "/api/letters?after=0&limit=50" -Headers $deviceHeaders
    if ($poll.Status -eq 200) {
        $letters = ($poll.Content | ConvertFrom-Json).letters
        $testOnes = @($letters | Where-Object { $_.id -in $testLetters })
        Step "设备拉取到 4 封测试信" ($testOnes.Count -eq 4) "count=$($testOnes.Count)"
        $allTest = @($testOnes | Where-Object { $_.body.StartsWith("[TEST]") })
        Step "测试信带 [TEST] 前缀" ($allTest.Count -eq 4) "count=$($allTest.Count)"
        $unopened = @($testOnes | Where-Object { $null -eq $_.opened_at })
        Step "未读状态为 null" ($unopened.Count -eq 4) "count=$($unopened.Count)"

        # ---- 9. 打开 + 幂等 ----
        $first = $testOnes[0]
        $open1 = Invoke-Api -Method POST -Path "/api/letters/$($first.id)/open" -Headers $deviceHeaders
        if ($open1.Status -eq 200) {
            $open1Data = $open1.Content | ConvertFrom-Json
            $open2 = Invoke-Api -Method POST -Path "/api/letters/$($first.id)/open" -Headers $deviceHeaders
            $open2Data = $open2.Content | ConvertFrom-Json
            Step "打开信件幂等" (($open1Data.already_opened -eq $false) -and ($open2Data.already_opened -eq $true) -and ($open1Data.opened_at -eq $open2Data.opened_at)) "opened_at 一致"
        } else {
            Step "打开信件幂等" $false "status=$($open1.Status)"
        }
    } else {
        Step "设备拉取到 4 封测试信" $false "status=$($poll.Status)"
    }

    # ---- 10. 设备只读：不能发信 ----
    $deviceSend = Invoke-Api -Method POST -Path "/api/letters" -Body @{ body = "[TEST] 冒充" } -Headers $deviceHeaders
    Step "设备发信被拒 401" ($deviceSend.Status -eq 401) "status=$($deviceSend.Status)"
}

# ---- 11. 撤销设备并立即失效 ----
if ($deviceId) {
    $revoke = Invoke-Api -Method POST -Path "/api/admin/devices/$deviceId/revoke" -Headers $senderHeaders -Session $session
    Step "撤销设备 200" ($revoke.Status -eq 200) "status=$($revoke.Status)"
    $after = Invoke-Api -Method GET -Path "/api/letters?after=0" -Headers @{ Authorization = "Bearer $token" }
    Step "撤销后令牌立即失效 401" ($after.Status -eq 401) "status=$($after.Status)"
}

# ---- 12. 清理测试信件 ----
$cleaned = 0
foreach ($id in $testLetters) {
    $del = Invoke-Api -Method DELETE -Path "/api/letters/$id" -Headers $senderHeaders -Session $session
    if ($del.Status -eq 200) { $cleaned++ }
}
Step "清理测试信件" ($cleaned -eq $testLetters.Count) "deleted=$cleaned/$($testLetters.Count)"

$password = $null
$secure.Dispose()

Write-Host ""
Write-Host "=== 结果汇总 ==="
$script:Results | Format-Table -AutoSize
$failed = @($script:Results | Where-Object { $_.Result -eq "FAIL" })
if ($failed.Count -gt 0) {
    Write-Host "存在 $($failed.Count) 项失败" -ForegroundColor Red
    exit 1
}
Write-Host "全部通过" -ForegroundColor Green
exit 0
