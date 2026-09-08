$csvPath = 'C:\Users\ormbo\OneDrive\Documents\2026\EA26\Report3.csv'
$lines = Get-Content -Path $csvPath

$xau_profit = 0.0
$eur_profit = 0.0
$thb_profit = 0.0

$xau_count = 0
$eur_count = 0
$thb_count = 0

$xau_win = 0
$eur_win = 0
$thb_win = 0

$xau_loss = 0
$eur_loss = 0
$thb_loss = 0

foreach ($line in $lines) {
    $cols = $line -split ','
    if ($cols.Length -ge 12) {
        $sym = $cols[2].Trim()
        if ($sym -eq 'XAUUSD' -or $sym -eq 'EURUSD' -or $sym -eq 'USDTHB') {
            $profitStr = $cols[10].Replace(' ', '').Trim()
            $swapStr = $cols[9].Replace(' ', '').Trim()
            $commStr = $cols[8].Replace(' ', '').Trim()
            
            if ([string]::IsNullOrWhiteSpace($profitStr) -eq $false -and $profitStr -ne '0.00' -and $profitStr -ne '0') {
                try {
                    $profit = [double]$profitStr
                    $swap = 0.0; if (![string]::IsNullOrWhiteSpace($swapStr)) { $swap = [double]$swapStr }
                    $comm = 0.0; if (![string]::IsNullOrWhiteSpace($commStr)) { $comm = [double]$commStr }
                    
                    $net_profit = $profit + $swap + $comm
                    
                    if ($sym -eq 'XAUUSD') {
                        $xau_profit += $net_profit
                        $xau_count++
                        if ($net_profit -gt 0) { $xau_win++ } else { $xau_loss++ }
                    }
                    elseif ($sym -eq 'EURUSD') {
                        $eur_profit += $net_profit
                        $eur_count++
                        if ($net_profit -gt 0) { $eur_win++ } else { $eur_loss++ }
                    }
                    elseif ($sym -eq 'USDTHB') {
                        $thb_profit += $net_profit
                        $thb_count++
                        if ($net_profit -gt 0) { $thb_win++ } else { $thb_loss++ }
                    }
                }
                catch { }
            }
        }
    }
}

Write-Host "XAUUSD | Trades: $xau_count | Win: $xau_win | Loss: $xau_loss | Net Profit: $xau_profit"
Write-Host "EURUSD | Trades: $eur_count | Win: $eur_win | Loss: $eur_loss | Net Profit: $eur_profit"
Write-Host "USDTHB | Trades: $thb_count | Win: $thb_win | Loss: $thb_loss | Net Profit: $thb_profit"
