$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

function Read-ReportSummary($filePath) {
    Write-Host "=========================================="
    Write-Host "Reading: $filePath"
    Write-Host "=========================================="
    $workbook = $excel.Workbooks.Open($filePath)
    $sheet = $workbook.Sheets.Item(1)
    $maxRow = $sheet.UsedRange.Rows.Count
    $maxCol = $sheet.UsedRange.Columns.Count

    for ($r = 1; $r -le [math]::min(55, $maxRow); $r++) {
        $rowStr = ""
        for ($c = 1; $c -le $maxCol; $c++) {
            $cellText = $sheet.Cells.Item($r, $c).Text
            $rowStr += "$cellText | "
        }
        Write-Host $rowStr
    }
    $workbook.Close($false)
}

Read-ReportSummary('C:\Users\ormbo\OneDrive\Documents\2026\EA26\ReportTester-7955618-14.xlsx')
Read-ReportSummary('C:\Users\ormbo\OneDrive\Documents\2026\EA26\ReportTester-7955618-15.xlsx')

$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
